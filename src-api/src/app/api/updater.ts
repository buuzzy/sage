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

const BUILT_IN_MANIFEST: UpdaterManifest = {
  version: '1.4.6',
  notes:
    'Stabilizes desktop update checks by serving the Tauri updater manifest from Railway instead of GitHub release asset redirects.',
  pub_date: '2026-05-15T03:14:57Z',
  platforms: {
    'darwin-aarch64': {
      signature:
        'dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9tIHRhdXJpIHNlY3JldCBrZXkKUlVRQk1yTnd5UkNOMzdpbEQ1a0Y4UVhzRVFvS3FFVmpZaitqMGl4VTR6bndWR1BxV01PV1p5NnVVdHNqVDBKaEwrSWdpSWFnbWlqL1Z1V1MzSjR6SDREa3QrRHNVVVdJS3c0PQp0cnVzdGVkIGNvbW1lbnQ6IHRpbWVzdGFtcDoxNzc4ODE0ODg3CWZpbGU6U2FnZS5hcHAudGFyLmd6Ci8ydDBjbnZRTmVPaUdKckNuYlROdENlYloxWFZXSGJOeVZPaC9TV0wvaVFiRk44OHR6NnZWcnVrYVBlbTNZM2dOK0QrTDBHeGdSd083QU8yV2MwOURBPT0K',
      url: 'https://github.com/buuzzy/sage/releases/download/v1.4.6/Sage.app.tar.gz',
    },
  },
};

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
  return parseManifestFromEnv() ?? buildManifestFromEnv() ?? BUILT_IN_MANIFEST;
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
