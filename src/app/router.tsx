import { lazy, Suspense } from 'react';
import { createBrowserRouter } from 'react-router-dom';
import {
  HomePage,
  LibraryPage,
  LoginPage,
  SetupPage,
  TaskDetailPage,
} from '@/app/pages';
import { isMobile } from '@/shared/lib/platform';

import { AuthGuard } from '@/components/auth-guard';
import { SetupGuard } from '@/components/setup-guard';

// Mobile app shell (lazy-loaded, only on mobile)
const MobileApp = lazy(() => import('./mobile/MobileApp'));

function MobileShell() {
  return (
    <Suspense
      fallback={
        <div className="bg-background flex h-screen items-center justify-center">
          <div className="text-muted-foreground text-sm">Loading...</div>
        </div>
      }
    >
      <MobileApp />
    </Suspense>
  );
}

// Desktop routes (unchanged)
const desktopRoutes = [
  {
    path: '/login',
    element: <LoginPage />,
  },
  {
    path: '/',
    element: (
      <AuthGuard>
        <SetupGuard>
          <HomePage />
        </SetupGuard>
      </AuthGuard>
    ),
  },
  {
    path: '/task/:taskId',
    element: (
      <AuthGuard>
        <SetupGuard>
          <TaskDetailPage />
        </SetupGuard>
      </AuthGuard>
    ),
  },
  {
    path: '/library',
    element: (
      <AuthGuard>
        <SetupGuard>
          <LibraryPage />
        </SetupGuard>
      </AuthGuard>
    ),
  },
  {
    path: '/setup',
    element: <SetupPage />,
  },
];

// Mobile routes — single shell handles all navigation internally
// Note: No SetupGuard on mobile — model config will be handled within MobileApp
const mobileRoutes = [
  {
    path: '/login',
    element: <LoginPage />,
  },
  {
    path: '*',
    element: (
      <AuthGuard>
        <MobileShell />
      </AuthGuard>
    ),
  },
];

export const router = createBrowserRouter(
  isMobile ? mobileRoutes : desktopRoutes
);
