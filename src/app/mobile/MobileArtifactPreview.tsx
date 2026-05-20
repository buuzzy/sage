/**
 * MobileArtifactPreview
 *
 * Bottom-sheet style artifact viewer for mobile.
 * Renders charts, tables, code, and other artifact types optimized for touch.
 *
 * Usage:
 *   <MobileArtifactPreview
 *     artifact={artifact}
 *     onClose={() => setShowPreview(false)}
 *   />
 */

import { useRef, useState } from 'react';
import { cn } from '@/shared/lib/utils';
import { ChevronDown, Download, Share2, X } from 'lucide-react';

import { ArtifactRenderer } from '@/components/artifacts/ArtifactRenderer';
import type { Artifact } from '@/components/artifacts/types';

interface MobileArtifactPreviewProps {
  artifact: Artifact;
  onClose: () => void;
  onDownload?: () => void;
}

export function MobileArtifactPreview({
  artifact,
  onClose,
  onDownload,
}: MobileArtifactPreviewProps) {
  const [sheetHeight, setSheetHeight] = useState<'peek' | 'mid' | 'full'>('mid');
  const dragRef = useRef<HTMLDivElement>(null);
  const startY = useRef(0);
  const startHeight = useRef<'peek' | 'mid' | 'full'>('mid');

  // Handle bottom sheet drag
  const handleDragStart = (e: React.TouchEvent) => {
    startY.current = e.touches[0].clientY;
    startHeight.current = sheetHeight;
  };

  const handleDragMove = (e: React.TouchEvent) => {
    if (!dragRef.current) return;

    const deltaY = e.touches[0].clientY - startY.current;
    const threshold = 50;

    if (deltaY > threshold && startHeight.current !== 'peek') {
      setSheetHeight(startHeight.current === 'full' ? 'mid' : 'peek');
    } else if (deltaY < -threshold && startHeight.current !== 'full') {
      setSheetHeight(startHeight.current === 'peek' ? 'mid' : 'full');
    }
  };

  // Calculate height percentages based on state
  const getHeightClass = () => {
    switch (sheetHeight) {
      case 'peek':
        return 'h-[35vh]';
      case 'mid':
        return 'h-[60vh]';
      case 'full':
        return 'h-[90vh]';
      default:
        return 'h-[60vh]';
    }
  };

  // Get artifact file extension for display
  const fileExt = artifact.filename
    ? artifact.filename.split('.').pop()?.toLowerCase()
    : artifact.type;

  return (
    <div className="fixed inset-0 z-50 bg-black/30 animate-in fade-in">
      {/* Backdrop - tap to close */}
      <div className="absolute inset-0" onClick={onClose} />

      {/* Bottom sheet */}
      <div
        ref={dragRef}
        onTouchStart={handleDragStart}
        onTouchMove={handleDragMove}
        className={cn(
          'bg-background fixed bottom-0 left-0 right-0 rounded-t-2xl shadow-lg z-50',
          'transition-all duration-300 ease-out overflow-hidden flex flex-col',
          getHeightClass()
        )}
      >
        {/* Drag handle */}
        <div
          className="border-border shrink-0 border-b px-4 py-3 flex items-center justify-between"
          onTouchStart={handleDragStart}
          onTouchMove={handleDragMove}
        >
          <div className="flex items-center gap-3 flex-1">
            {/* Drag indicator */}
            <div className="bg-muted-foreground/30 w-8 h-1 rounded-full" />

            {/* Title and type */}
            <div className="flex-1 min-w-0">
              <p className="text-foreground text-sm font-medium truncate">
                {artifact.filename || 'Artifact'}
              </p>
              <p className="text-muted-foreground text-xs">
                {artifact.type} {fileExt && `• ${fileExt.toUpperCase()}`}
              </p>
            </div>
          </div>

          {/* Close button */}
          <button
            onClick={onClose}
            className="hover:bg-muted text-muted-foreground hover:text-foreground ml-2 p-2 rounded-lg transition-colors"
          >
            <X className="size-4" />
          </button>
        </div>

        {/* Content area - scrollable */}
        <div className="flex-1 overflow-y-auto overflow-x-hidden">
          <div className="p-4">
            <ArtifactRenderer
              artifact={artifact}
              onClose={onClose}
              isCompact={true}
            />
          </div>
        </div>

        {/* Action buttons - sticky footer */}
        <div className="border-border shrink-0 border-t bg-muted/30 px-4 py-3 flex gap-2">
          {/* Download button (if applicable) */}
          {['pdf', 'xlsx', 'docx', 'csv'].includes(fileExt || '') && (
            <button
              onClick={onDownload}
              className="flex-1 bg-primary text-primary-foreground rounded-lg px-3 py-2 text-sm font-medium flex items-center justify-center gap-2 active:opacity-80 transition-opacity"
            >
              <Download className="size-4" />
              下载
            </button>
          )}

          {/* Share button (for web/mobile) */}
          {['html', 'code', 'json'].includes(fileExt || '') && (
            <button
              onClick={() => {
                if (navigator.share && artifact.code) {
                  navigator.share({
                    title: artifact.filename,
                    text: artifact.code,
                  }).catch(err => console.log('Share failed:', err));
                }
              }}
              className="flex-1 bg-muted text-foreground rounded-lg px-3 py-2 text-sm font-medium flex items-center justify-center gap-2 active:opacity-80 transition-opacity"
            >
              <Share2 className="size-4" />
              分享
            </button>
          )}

          {/* Height adjuster button */}
          <button
            onClick={() => {
              if (sheetHeight === 'peek') setSheetHeight('mid');
              else if (sheetHeight === 'mid') setSheetHeight('full');
              else setSheetHeight('peek');
            }}
            className="hover:bg-muted text-muted-foreground hover:text-foreground p-2 rounded-lg transition-colors"
            title={sheetHeight === 'full' ? '缩小' : '展开'}
          >
            <ChevronDown
              className={cn(
                'size-4 transition-transform',
                sheetHeight === 'full' && 'rotate-180'
              )}
            />
          </button>
        </div>
      </div>
    </div>
  );
}

