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

const SUPPORTED_MAC_PLATFORMS = ['darwin-aarch64', 'darwin-x86_64'] as const;

const BUILT_IN_MANIFEST: UpdaterManifest = {
  version: '1.4.9',
  notes:
    'Hardens generated task titles, improves model failure visibility, and stabilizes execution UI state.',
  pub_date: '2026-05-15T14:53:28Z',
  platforms: {
    'darwin-aarch64': {
      signature:
        'dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9tIHRhdXJpIHNlY3JldCBrZXkKUlVRQk1yTnd5UkNOMzExRldvRUVKcHl5RzRHVmdvcFVWQlRVYXFUc2g2TUkrT1lWNlVTQU0xU3FLYTRsUkNCZkVGRUE5SzlOeVpKZ0xWZlZvODhaRG0zem5KS3ljaUk5UUFnPQp0cnVzdGVkIGNvbW1lbnQ6IHRpbWVzdGFtcDoxNzc4ODU2NzQ4CWZpbGU6U2FnZS5hcHAudGFyLmd6Cm1NVzZOVmV3R2RDSUg2bkdIUko3NDFrMUN0UnlrTW9TZXd1NmVpMy85cFBaSm1BUnJMTHkxWHJYcDNWRkxTRkRramFzWlNZTnUrV2NzeEdwYWNLY0JnPT0K',
      url: 'https://github.com/buuzzy/sage/releases/download/v1.4.9/Sage.app.tar.gz',
    },
  },
};

function readPlatformFromEnv(prefix: string): PlatformUpdate | null {
  const url = process.env[`${prefix}_URL`];
  const signature = process.env[`${prefix}_SIGNATURE`];

  if (!url && !signature) return null;
  if (!url || !signature) {
    console.warn(`[updater] incomplete platform env for ${prefix}`);
    return null;
  }

  return { signature, url };
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
  if (!version) {
    return null;
  }

  const darwinArm = readPlatformFromEnv('SAGE_UPDATER_DARWIN_AARCH64');
  const darwinIntel = readPlatformFromEnv('SAGE_UPDATER_DARWIN_X86_64');
  const platforms: Record<string, PlatformUpdate> = {};

  if (darwinArm) platforms['darwin-aarch64'] = darwinArm;
  if (darwinIntel) platforms['darwin-x86_64'] = darwinIntel;

  if (Object.keys(platforms).length === 0) {
    return null;
  }

  return {
    version,
    notes: process.env.SAGE_UPDATER_NOTES ?? '',
    pub_date: process.env.SAGE_UPDATER_PUB_DATE ?? new Date().toISOString(),
    platforms,
  };
}

function getManifest(): UpdaterManifest | null {
  return parseManifestFromEnv() ?? buildManifestFromEnv() ?? BUILT_IN_MANIFEST;
}

function isValidManifest(manifest: UpdaterManifest | null): manifest is UpdaterManifest {
  if (!manifest?.version || !manifest.platforms) return false;
  return SUPPORTED_MAC_PLATFORMS.some((platform) => {
    const update = manifest.platforms[platform];
    return Boolean(update?.url && update?.signature);
  });
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
