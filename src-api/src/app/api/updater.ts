import { Hono } from 'hono';

export const updaterRoutes = new Hono();

interface PlatformUpdate {
  signature: string;
  url: string;
}

interface UpdaterManifest {
  version: string;
  notes?: string;
  pub_date?: string;
  platforms: Record<string, PlatformUpdate>;
}

function parseManifestFromEnv(): UpdaterManifest | null {
  const raw = process.env.SAGE_UPDATER_MANIFEST_JSON;
  if (!raw) return null;

  try {
    return JSON.parse(raw) as UpdaterManifest;
  } catch (error) {
    console.error('[updater] invalid SAGE_UPDATER_MANIFEST_JSON:', error);
    return null;
  }
}

function buildManifestFromEnv(): UpdaterManifest | null {
  const version = process.env.SAGE_UPDATER_VERSION;
  const url = process.env.SAGE_UPDATER_DARWIN_AARCH64_URL;
  const signature = process.env.SAGE_UPDATER_DARWIN_AARCH64_SIGNATURE;

  if (!version || !url || !signature) {
    return null;
  }

  return {
    version,
    notes: process.env.SAGE_UPDATER_NOTES ?? '',
    pub_date: process.env.SAGE_UPDATER_PUB_DATE ?? new Date().toISOString(),
    platforms: {
      'darwin-aarch64': {
        signature,
        url,
      },
    },
  };
}

function getManifest(): UpdaterManifest | null {
  return parseManifestFromEnv() ?? buildManifestFromEnv();
}

function isValidManifest(manifest: UpdaterManifest | null): manifest is UpdaterManifest {
  if (!manifest?.version || !manifest.platforms) return false;
  const darwinArm = manifest.platforms['darwin-aarch64'];
  return Boolean(darwinArm?.url && darwinArm?.signature);
}

updaterRoutes.get('/latest.json', (c) => {
  const manifest = getManifest();
  if (!isValidManifest(manifest)) {
    return c.json(
      {
        error:
          'Updater manifest is not configured. Set SAGE_UPDATER_MANIFEST_JSON or SAGE_UPDATER_* variables.',
      },
      503,
      {
        'Cache-Control': 'no-store',
      }
    );
  }

  return c.json(manifest, 200, {
    'Cache-Control': 'no-cache, no-store, must-revalidate',
  });
});
