import { getOtaManifest, openOtaPackage } from '@services/app-updates/ota-manifest.service';
import type { Request, Response } from 'express';

// iOS fetches these links without any session, so a failure is a bare 403 that reveals nothing.
const forbidden = ({ res }: { res: Response }) => res.status(403).type('text/plain').send('forbidden');

// An unexpected failure answers a bare 500 too, not Express's HTML error page.
const failed = ({ res }: { res: Response }) => {
  if (res.headersSent) return res.destroy();
  return res.status(500).type('text/plain').send('error');
};

export const manifestHandler = async (req: Request, res: Response) => {
  try {
    const manifest = await getOtaManifest({ token: req.params[0]! });
    if (manifest === null) return forbidden({ res });
    res.set('Cache-Control', 'no-store').type('application/xml').send(manifest);
  } catch {
    failed({ res });
  }
};

export const downloadHandler = async (req: Request, res: Response) => {
  try {
    const pkg = await openOtaPackage({
      token: req.params.token!,
      fileName: req.params.fileName!,
      markStarted: req.method === 'GET',
    });
    if (!pkg) return forbidden({ res });
    // sendFile answers HEAD and Range requests, which iOS's installer may use.
    res.sendFile(
      pkg.filePath,
      {
        headers: { 'Content-Type': 'application/octet-stream', 'Cache-Control': 'no-store' },
        cacheControl: false,
        lastModified: false,
        etag: false,
        dotfiles: 'allow',
      },
      (error) => {
        if (error) failed({ res });
      },
    );
  } catch {
    failed({ res });
  }
};
