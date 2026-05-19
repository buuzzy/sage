/**
 * MobileHeader — simplified top navigation bar for mobile.
 * Shows: hamburger menu | title | (optional back button)
 */

import { ArrowLeft, Menu } from 'lucide-react';

interface MobileHeaderProps {
  title: string;
  onMenuPress: () => void;
  showBack?: boolean;
  onBackPress?: () => void;
}

export function MobileHeader({
  title,
  onMenuPress,
  showBack,
  onBackPress,
}: MobileHeaderProps) {
  return (
    <header className="border-border/30 flex h-12 shrink-0 items-center gap-3 border-b px-4">
      {showBack ? (
        <button
          onClick={onBackPress}
          className="text-muted-foreground hover:text-foreground -ml-1 flex size-8 items-center justify-center rounded-lg"
        >
          <ArrowLeft className="size-5" />
        </button>
      ) : (
        <button
          onClick={onMenuPress}
          className="text-muted-foreground hover:text-foreground -ml-1 flex size-8 items-center justify-center rounded-lg"
        >
          <Menu className="size-5" />
        </button>
      )}

      <h1 className="text-foreground min-w-0 flex-1 truncate text-base font-medium">
        {title}
      </h1>
    </header>
  );
}
