import { BadRequestError } from '@js/errors';
import { parseBuffer } from 'bplist-parser';
import type { Readable } from 'node:stream';
import yauzl from 'yauzl';

interface IpaInfo {
  buildNumber: string;
  version: string;
  bundleId: string;
}

const INFO_PLIST_PATTERN = /^Payload\/[^/]+\.app\/Info\.plist$/;
const MAX_INFO_PLIST_BYTES = 1024 * 1024;

const decodeXmlText = ({ value }: { value: string }) =>
  value
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');

const xmlStringValue = ({ xml, key }: { xml: string; key: string }): string => {
  const match = new RegExp(`<key>${key}</key>\\s*<string>([\\s\\S]*?)</string>`).exec(xml);
  return match ? decodeXmlText({ value: match[1]! }).trim() : '';
};

const parseInfoPlist = ({ buffer }: { buffer: Buffer }): IpaInfo => {
  if (buffer.subarray(0, 6).toString('latin1') === 'bplist') {
    const [dict] = parseBuffer<Record<string, unknown>>(buffer);
    const text = ({ key }: { key: string }) => (typeof dict?.[key] === 'string' ? (dict[key] as string) : '');
    return {
      buildNumber: text({ key: 'CFBundleVersion' }),
      version: text({ key: 'CFBundleShortVersionString' }),
      bundleId: text({ key: 'CFBundleIdentifier' }),
    };
  }
  const xml = buffer.toString('utf8');
  return {
    buildNumber: xmlStringValue({ xml, key: 'CFBundleVersion' }),
    version: xmlStringValue({ xml, key: 'CFBundleShortVersionString' }),
    bundleId: xmlStringValue({ xml, key: 'CFBundleIdentifier' }),
  };
};

const readStream = ({ stream }: { stream: Readable }) =>
  new Promise<Buffer>((resolve, reject) => {
    const chunks: Buffer[] = [];
    stream.on('data', (chunk: Buffer) => chunks.push(chunk));
    stream.on('error', reject);
    stream.on('end', () => resolve(Buffer.concat(chunks)));
  });

/**
 * Reads only the zip's central directory and the Info.plist entry from disk, so a
 * multi-hundred-MB archive is never held in memory.
 */
const readInfoPlist = ({ filePath }: { filePath: string }) =>
  new Promise<Buffer>((resolve, reject) => {
    yauzl.open(filePath, { lazyEntries: true, validateEntrySizes: true }, (openError, zip) => {
      if (openError) return reject(openError);
      zip.on('error', reject);
      zip.on('end', () => reject(new Error('missing Info.plist')));
      zip.on('entry', (entry: yauzl.Entry) => {
        if (!INFO_PLIST_PATTERN.test(entry.fileName)) return zip.readEntry();
        if (entry.uncompressedSize > MAX_INFO_PLIST_BYTES) {
          zip.close();
          return reject(new Error('Info.plist is too large'));
        }
        zip.openReadStream(entry, (streamError, stream) => {
          if (streamError) return reject(streamError);
          readStream({ stream })
            .then(resolve, reject)
            .finally(() => zip.close());
        });
      });
      zip.readEntry();
    });
  });

/** Reads the app's version fields from an IPA's Payload/<name>.app/Info.plist (binary or XML). */
export const readIpaInfo = async ({ filePath }: { filePath: string }): Promise<IpaInfo> => {
  try {
    return parseInfoPlist({ buffer: await readInfoPlist({ filePath }) });
  } catch (error) {
    throw new BadRequestError({ message: `Not a readable IPA: ${(error as Error).message}` });
  }
};
