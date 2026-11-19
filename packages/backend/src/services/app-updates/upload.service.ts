import {
  API_ERROR_CODES,
  APP_UPDATE_MAX_BYTES,
  type AppUpdatePlatform,
  type AppUpdateUploadResult,
} from '@bt/shared/types';
import { BadRequestError, ConflictError, CustomError } from '@js/errors';
import crypto from 'node:crypto';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { Transform, type Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';

import { readIpaInfo } from './ipa-info';
import { buildFileName, buildFilePath, getSlot, storageRoot, updateSlot } from './storage';

const tooLarge = () =>
  new CustomError(413, API_ERROR_CODES.payloadTooLarge, 'The build exceeds the 1 GiB upload limit.');

const notNewer = ({ build, currentBuild }: { build: number; currentBuild: number }) =>
  new ConflictError({ message: `Build ${build} is not newer than the current build ${currentBuild}.` });

/**
 * Streams the request body to disk as the platform's new current build. The archive's own
 * Info.plist must carry the same build number, otherwise the installed app would read an
 * older number and offer itself again.
 */
export const uploadAppUpdate = async ({
  platform,
  build,
  commit,
  notes,
  body,
  contentLength,
}: {
  platform: AppUpdatePlatform;
  build: number;
  commit: string;
  notes: string;
  body: Readable;
  contentLength: number | null;
}): Promise<AppUpdateUploadResult> => {
  if (contentLength !== null && contentLength > APP_UPDATE_MAX_BYTES) throw tooLarge();
  const { current: knownCurrent } = await getSlot({ platform });
  if (knownCurrent && build <= knownCurrent.build) throw notNewer({ build, currentBuild: knownCurrent.build });

  await fsp.mkdir(storageRoot(), { recursive: true });
  // A temp file per upload, so a retry racing the first attempt cannot write into the file the first one is about to move into place.
  const tempPath = path.join(storageRoot(), `.${platform}-${build}-${crypto.randomUUID()}.part`);
  const digest = crypto.createHash('sha256');
  let size = 0;
  const meter = new Transform({
    transform(chunk: Buffer, _encoding, callback) {
      size += chunk.length;
      if (size > APP_UPDATE_MAX_BYTES) return callback(tooLarge());
      digest.update(chunk);
      callback(null, chunk);
    },
  });

  try {
    await pipeline(body, meter, fs.createWriteStream(tempPath));
    if (size === 0) throw new BadRequestError({ message: 'The upload body is empty.' });

    const info = await readIpaInfo({ filePath: tempPath });
    if (info.buildNumber !== String(build)) {
      throw new BadRequestError({
        message: `The archive is build ${JSON.stringify(info.buildNumber)}, not ${build}.`,
      });
    }

    const sha256 = digest.digest('hex');
    const file = buildFileName({ platform, build });
    return await updateSlot({
      platform,
      fn: async ({ slot }) => {
        if (slot.current && build <= slot.current.build) {
          throw notNewer({ build, currentBuild: slot.current.build });
        }
        if (slot.current?.bundleId && slot.current.bundleId !== info.bundleId) {
          throw new ConflictError({
            message: `Bundle id ${info.bundleId} does not match the current build's ${slot.current.bundleId}.`,
          });
        }
        await fsp.rename(tempPath, buildFilePath({ file }));
        return {
          slot: {
            current: {
              build,
              version: info.version,
              bundleId: info.bundleId,
              commit: commit.slice(0, 40),
              notes: notes.trim().slice(0, 2000),
              size,
              sha256,
              uploadedAt: new Date().toISOString(),
              file,
            },
            previous: slot.current,
          },
          result: { build, version: info.version, bundleId: info.bundleId, size, sha256 },
        };
      },
    });
  } finally {
    await fsp.rm(tempPath, { force: true });
  }
};
