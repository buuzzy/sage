import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'ai.sage.app',
  appName: 'Sage',
  webDir: 'dist',
  server: {
    // Use capacitor:// scheme (default) — avoids CORS issues with https://localhost
    // allowNavigation allows the WebView to make requests to these domains
    allowNavigation: ['sage-production-28e1.up.railway.app'],
  },
};

export default config;
