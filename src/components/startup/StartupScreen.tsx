import { AlertTriangle, Check, ChevronDown, Loader2, RefreshCw } from 'lucide-react';

import { Logo } from '@/components/common/logo';
import { cn } from '@/shared/lib/utils';

export interface StartupStep {
  id: string;
  label: string;
  description?: string;
  status: 'pending' | 'active' | 'done' | 'error';
}

export interface StartupDiagnostic {
  label: string;
  value: string;
  tone?: 'default' | 'success' | 'warning' | 'error';
}

interface StartupScreenProps {
  title?: string;
  subtitle?: string;
  steps: StartupStep[];
  diagnostics?: StartupDiagnostic[];
  error?: string;
  onRetry?: () => void;
  compact?: boolean;
}

export function StartupScreen({
  title = 'Preparing Sage',
  subtitle = 'Setting up your local workspace and conversation engine.',
  steps,
  diagnostics = [],
  error,
  onRetry,
  compact = false,
}: StartupScreenProps) {
  const completedSteps = steps.filter((step) => step.status === 'done').length;
  const activeStep = steps.find((step) => step.status === 'active');
  const progress =
    steps.length === 0 ? 100 : Math.round((completedSteps / steps.length) * 100);

  return (
    <div className="bg-background text-foreground relative flex min-h-svh items-center justify-center overflow-x-hidden overflow-y-auto px-6 py-6">
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_20%,var(--primary)_0%,transparent_34%)] opacity-[0.07]" />
      <div className="pointer-events-none absolute inset-x-0 top-0 h-32 bg-linear-to-b from-primary/8 to-transparent" />
      <div className="pointer-events-none absolute inset-x-12 bottom-0 h-40 rounded-full bg-primary/5 blur-3xl" />

      <div
        className={cn(
          'border-border/70 bg-background/82 relative w-full rounded-3xl border shadow-[0_24px_80px_rgba(0,0,0,0.08)] backdrop-blur-xl',
          'max-h-[calc(100svh-3rem)] overflow-y-auto',
          'animate-in fade-in-0 zoom-in-95 duration-500',
          compact ? 'max-w-sm p-6' : 'max-w-lg p-8'
        )}
      >
        <div className="flex flex-col items-center text-center">
          <div className="relative mb-5 flex size-20 items-center justify-center">
            <div className="absolute inset-0 rounded-3xl border border-primary/20 bg-primary/8" />
            <div className="absolute inset-1 rounded-[1.35rem] border border-primary/15 animate-pulse" />
            <div className="border-border/80 bg-background/90 relative flex size-16 items-center justify-center rounded-2xl border shadow-sm">
              <Logo className="[&_img]:size-10" />
            </div>
          </div>

          <h1 className="text-foreground text-xl font-semibold tracking-tight">
            {title}
          </h1>
          <p className="text-muted-foreground mt-2 max-w-sm text-sm leading-relaxed">
            {subtitle}
          </p>
        </div>

        <div className="mt-7">
          <div className="mb-2 flex items-center justify-between text-xs">
            <span className="text-muted-foreground">
              {activeStep?.label ?? (error ? 'Needs attention' : 'Ready')}
            </span>
            <span className="text-muted-foreground tabular-nums">
              {error ? 'Paused' : `${progress}%`}
            </span>
          </div>
          <div className="bg-muted h-1.5 overflow-hidden rounded-full">
            <div
              className={cn(
                'h-full rounded-full transition-all duration-500',
                error ? 'bg-destructive' : 'bg-primary'
              )}
              style={{ width: `${error ? Math.max(progress, 8) : progress}%` }}
            />
          </div>
        </div>

        <div className="mt-7 space-y-3">
          {steps.map((step) => (
            <div
              key={step.id}
              className={cn(
                'flex items-start gap-3 rounded-2xl border px-3 py-3 transition-colors',
                step.status === 'active'
                  ? 'border-primary/30 bg-primary/8'
                  : step.status === 'error'
                    ? 'border-destructive/30 bg-destructive/8'
                    : 'border-transparent bg-muted/30'
              )}
            >
              <div className="mt-0.5 flex size-5 shrink-0 items-center justify-center">
                {step.status === 'done' ? (
                  <Check className="text-primary size-4" />
                ) : step.status === 'error' ? (
                  <AlertTriangle className="text-destructive size-4" />
                ) : step.status === 'active' ? (
                  <Loader2 className="text-primary size-4 animate-spin" />
                ) : (
                  <div className="bg-muted-foreground/30 size-1.5 rounded-full" />
                )}
              </div>
              <div className="min-w-0 text-left">
                <div className="text-foreground text-sm font-medium">
                  {step.label}
                </div>
                {step.description && (
                  <div className="text-muted-foreground mt-0.5 text-xs leading-relaxed">
                    {step.description}
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>

        {error && (
          <div className="border-destructive/25 bg-destructive/8 text-destructive mt-5 rounded-2xl border px-4 py-3 text-sm leading-relaxed">
            {error}
          </div>
        )}

        {diagnostics.length > 0 && (
          <details className="group border-border/70 bg-muted/20 mt-5 rounded-2xl border px-4 py-3">
            <summary className="text-muted-foreground flex cursor-pointer list-none items-center justify-between text-xs font-medium">
              Startup diagnostics
              <ChevronDown className="size-3.5 transition-transform group-open:rotate-180" />
            </summary>
            <div className="mt-3 space-y-2">
              {diagnostics.map((item) => (
                <div
                  key={item.label}
                  className="flex items-start justify-between gap-4 text-xs"
                >
                  <span className="text-muted-foreground">{item.label}</span>
                  <span
                    className={cn(
                      'max-w-[60%] wrap-break-word text-right font-medium',
                      item.tone === 'success'
                        ? 'text-primary'
                        : item.tone === 'warning'
                          ? 'text-amber-600 dark:text-amber-400'
                          : item.tone === 'error'
                            ? 'text-destructive'
                            : 'text-foreground'
                    )}
                  >
                    {item.value}
                  </span>
                </div>
              ))}
            </div>
          </details>
        )}

        {onRetry && (
          <button
            type="button"
            onClick={onRetry}
            className="bg-primary text-primary-foreground hover:bg-primary/90 mt-5 inline-flex h-10 w-full items-center justify-center gap-2 rounded-xl text-sm font-medium transition-colors"
          >
            <RefreshCw className="size-4" />
            Retry
          </button>
        )}
      </div>
    </div>
  );
}
