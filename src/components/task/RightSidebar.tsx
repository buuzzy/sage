import { startTransition, useEffect, useRef, useState } from 'react';
import { API_BASE_URL } from '@/config';
import type { AgentMessage } from '@/shared/hooks/useAgent';
import { cn } from '@/shared/lib/utils';
import { useLanguage } from '@/shared/providers/language-provider';
import {
  ChevronDown,
  ChevronRight,
  Code2,
  ExternalLink,
  File,
  FileCode2,
  FileEdit,
  FileImage,
  FileSpreadsheet,
  FileText,
  FileType,
  Folder,
  FolderOpen,
  FolderSearch,
  Globe,
  Layers,
  ListTodo,
  Loader2,
  Music,
  Package,
  Presentation,
  Search,
  Sparkles,
  Table,
  Terminal,
  Type,
  Video,
  Wrench,
  X,
} from 'lucide-react';

import type { Artifact, ArtifactType } from '@/components/artifacts';

const API_URL = API_BASE_URL;

// Re-export types for backwards compatibility
export type { Artifact, ArtifactType };


import {
  type ToolUsage,
  type WorkingFile,
  type SkillsDirInfo,
  getFileIconByExt,
  getToolIcon,
  isMcpTool,
  isSkillTool,
  getSkillMCPInfo,
  extractMcpTools,
  ToolPreviewModal,
  FileTreeItem,
  EmptyState,
  CollapsibleSection,
  extractUsedSkillNames,
  extractExternalFolders,
  getFileIcon,
  getArtifactType,
  extractArtifacts,
} from './right-sidebar-helpers';

export function RightSidebar({
  messages,
  isRunning: _isRunning,
  artifacts: externalArtifacts,
  selectedArtifact,
  onSelectArtifact,
  workingDir,
  sessionFolder: _sessionFolder,
  onSelectWorkingFile,
  filesVersion = 0,
}: RightSidebarProps) {
  const { t } = useLanguage();
  const [selectedTool, setSelectedTool] = useState<ToolUsage | null>(null);
  const [showAllArtifacts, setShowAllArtifacts] = useState(false);
  const [showAllTools, setShowAllTools] = useState(false);
  const [workingFiles, setWorkingFiles] = useState<WorkingFile[]>([]);
  const [loadingFiles, setLoadingFiles] = useState(false);
  const [skillsDirs, setSkillsDirs] = useState<
    { name: string; files: WorkingFile[] }[]
  >([]);
  const [loadingSkills, setLoadingSkills] = useState(false);
  const [outputExpanded, setOutputExpanded] = useState(true);
  const [editedExpanded, setEditedExpanded] = useState(true);

  // Read directory via API (uses Node.js fs on backend)
  async function readDirViaApi(dirPath: string): Promise<WorkingFile[]> {
    try {
      console.log('[RightSidebar] readDirViaApi called with:', dirPath);
      const response = await fetch(`${API_URL}/files/readdir`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ path: dirPath, maxDepth: 3 }),
      });

      console.log(
        '[RightSidebar] readDirViaApi response status:',
        response.status
      );

      if (!response.ok) {
        console.error('[RightSidebar] readDirViaApi response not ok');
        return [];
      }

      const data = await response.json();
      console.log('[RightSidebar] readDirViaApi data:', data);

      if (!data.files || !Array.isArray(data.files)) {
        console.error(
          '[RightSidebar] readDirViaApi: no files array in response'
        );
        return [];
      }

      if (data.error) {
        console.warn(
          '[RightSidebar] readDirViaApi: API returned error:',
          data.error
        );
      }

      // Convert API response to WorkingFile format with isExpanded
      function addExpandedFlag(files: WorkingFile[], depth = 0): WorkingFile[] {
        return files.map((file) => ({
          ...file,
          isExpanded: false, // Default all folders to collapsed
          children: file.children
            ? addExpandedFlag(file.children, depth + 1)
            : undefined,
        }));
      }

      return addExpandedFlag(data.files);
    } catch (err) {
      console.error(`[RightSidebar] Failed to fetch directory:`, err);
      return [];
    }
  }

  // Cache for loaded working directory to avoid redundant loads
  const workingDirCacheRef = useRef<{
    dir: string;
    files: WorkingFile[];
    version: number;
  } | null>(null);

  // Load files from working directory via API
  // Refresh when workingDir changes, artifacts change, or files are added (e.g., attachments)
  useEffect(() => {
    let cancelled = false;

    async function loadWorkingFiles() {
      console.log(
        '[RightSidebar] loadWorkingFiles called with workingDir:',
        workingDir
      );
      if (!workingDir || !workingDir.startsWith('/')) {
        console.log('[RightSidebar] workingDir is empty or invalid');
        setWorkingFiles([]);
        setLoadingFiles(false);
        return;
      }

      // Check cache: skip loading if same dir and version
      const cache = workingDirCacheRef.current;
      if (
        cache &&
        cache.dir === workingDir &&
        cache.version === filesVersion &&
        cache.files.length > 0
      ) {
        // Use cached data, no need to reload
        setWorkingFiles(cache.files);
        setLoadingFiles(false);
        return;
      }

      setLoadingFiles(true);
      try {
        const files = await readDirViaApi(workingDir);
        if (cancelled) return;

        // Update cache
        workingDirCacheRef.current = {
          dir: workingDir,
          files,
          version: filesVersion,
        };

        // Use startTransition to mark this as a low-priority update
        startTransition(() => {
          setWorkingFiles(files);
        });
      } catch {
        if (cancelled) return;
        setWorkingFiles([]);
      } finally {
        if (!cancelled) {
          setLoadingFiles(false);
        }
      }
    }

    loadWorkingFiles();

    return () => {
      cancelled = true;
    };
  }, [workingDir, externalArtifacts.length, filesVersion]);

  // Get used skill names from messages
  const usedSkillNames = extractUsedSkillNames(messages);

  // Load skills folders (only for used skills)
  useEffect(() => {
    async function loadSkillsFiles() {
      // Only load if there are used skills
      if (usedSkillNames.size === 0) {
        setSkillsDirs([]);
        setLoadingSkills(false);
        return;
      }

      setLoadingSkills(true);
      try {
        const dirs = await fetchSkillsDirs();
        const results: { name: string; files: WorkingFile[] }[] = [];

        for (const dir of dirs) {
          const allFiles = await readDirViaApi(dir.path);
          // Filter to only show used skills (match by folder name)
          const filteredFiles = allFiles.filter((file) => {
            // Check if folder name matches any used skill
            return file.isDir && usedSkillNames.has(file.name);
          });

          if (filteredFiles.length > 0) {
            results.push({ name: dir.name, files: filteredFiles });
          }
        }

        setSkillsDirs(results);
      } catch {
        setSkillsDirs([]);
      } finally {
        setLoadingSkills(false);
      }
    }

    loadSkillsFiles();
  }, [usedSkillNames.size]); // Re-run when used skills change

  // Extract artifacts from messages
  const internalArtifacts = extractArtifacts(messages);
  const artifacts =
    externalArtifacts.length > 0 ? externalArtifacts : internalArtifacts;

  // Artifacts with show more/less (max 10)
  const visibleArtifacts = showAllArtifacts
    ? artifacts
    : artifacts.slice(0, 10);
  const hasMoreArtifacts = artifacts.length > 10;

  // MCP tools only
  const mcpTools = extractMcpTools(messages);
  const visibleTools = showAllTools
    ? mcpTools
    : mcpTools.slice(0, DEFAULT_VISIBLE_COUNT);
  const hasMoreTools = mcpTools.length > DEFAULT_VISIBLE_COUNT;

  // Extract external folders (folders outside workingDir that were accessed)
  // Extract and deduplicate external folders (keep only parent paths)
  const externalFoldersRaw = extractExternalFolders(messages, workingDir);
  const externalFolders = externalFoldersRaw.filter((folder) => {
    // Remove if another folder is a parent of this one
    return !externalFoldersRaw.some(
      (other) => other !== folder && folder.startsWith(other + '/')
    );
  });

  // Get display path (shorten to folder name only)
  const getFolderName = (path: string) => path.split('/').pop() || path;

  // Open folder in system
  const handleOpenFolder = async (folderPath: string) => {
    console.log('[RightSidebar] handleOpenFolder called with:', folderPath);
    try {
      // Handle ~ paths - let backend resolve it
      const response = await fetch(`${API_URL}/files/open`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: folderPath, expandHome: true }),
      });
      const data = await response.json();
      console.log('[RightSidebar] handleOpenFolder response:', data);
      if (!data.success) {
        console.error('[RightSidebar] Failed to open folder:', data.error);
      }
    } catch (err) {
      console.error('[RightSidebar] Error opening folder:', err);
    }
  };

  return (
    <div className="scrollbar-blend bg-background flex h-full flex-col overflow-x-hidden overflow-y-auto">
      {/* 1. Workspace Section */}
      <CollapsibleSection
        title={t.task.workspace || 'Workspace'}
        defaultExpanded={true}
      >
        {/* Output folder subsection */}
        <div className="mt-1 mb-3">
          <div className="mb-1 flex items-center gap-1">
            <button
              onClick={() => setOutputExpanded(!outputExpanded)}
              className="text-muted-foreground hover:text-foreground flex items-center gap-1 transition-colors"
            >
              {outputExpanded ? (
                <ChevronDown className="size-3" />
              ) : (
                <ChevronRight className="size-3" />
              )}
              <span className="text-xs font-medium">
                {t.task.outputFolder || 'Output'}
              </span>
            </button>
            {workingDir && (
              <button
                onClick={() => handleOpenFolder(workingDir)}
                className="text-muted-foreground hover:text-foreground ml-auto p-0.5 transition-colors"
                title={t.task.openInFinder}
              >
                <ExternalLink className="size-3" />
              </button>
            )}
          </div>
          {outputExpanded && (
            <>
              {!workingDir ? (
                <p className="text-muted-foreground py-1 text-sm">
                  {t.task.waitingForTask}
                </p>
              ) : loadingFiles ? (
                <div className="text-muted-foreground flex items-center gap-2 py-1">
                  <Loader2 className="size-4 animate-spin" />
                  <span className="text-sm">{t.common.loading}</span>
                </div>
              ) : workingFiles.length === 0 ? (
                <EmptyState icon={Folder} description={t.task.outputsDesc} />
              ) : (
                <div className="max-h-[200px] space-y-0.5 overflow-y-auto">
                  {workingFiles.map((file) => (
                    <FileTreeItem
                      key={file.path}
                      file={file}
                      onSelectFile={onSelectWorkingFile}
                      onSelectArtifact={onSelectArtifact}
                    />
                  ))}
                </div>
              )}
            </>
          )}
        </div>

        {/* Edited folders subsection */}
        {externalFolders.length > 0 && (
          <div>
            <div className="mb-1 flex items-center gap-1">
              <button
                onClick={() => setEditedExpanded(!editedExpanded)}
                className="text-muted-foreground hover:text-foreground flex items-center gap-1 transition-colors"
              >
                {editedExpanded ? (
                  <ChevronDown className="size-3" />
                ) : (
                  <ChevronRight className="size-3" />
                )}
                <span className="text-xs font-medium">
                  {t.task.editedFolders || 'Edited'}
                </span>
              </button>
            </div>
            {editedExpanded && (
              <div className="space-y-0.5">
                {externalFolders.map((folder) => (
                  <button
                    key={folder}
                    onClick={() => handleOpenFolder(folder)}
                    className="hover:bg-accent/50 flex w-full items-center gap-1.5 rounded-md py-1 text-left transition-colors"
                  >
                    <span className="size-4 shrink-0" />
                    <FolderOpen className="text-muted-foreground/60 size-3.5 shrink-0" />
                    <span className="text-foreground/80 truncate text-sm">
                      {getFolderName(folder)}
                    </span>
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
      </CollapsibleSection>

      {/* 2. Artifacts Section */}
      <CollapsibleSection title={t.task.artifacts} defaultExpanded={true}>
        {artifacts.length === 0 ? (
          <EmptyState icon={Package} description={t.task.noArtifacts} />
        ) : (
          <>
            <div
              className={cn(
                'space-y-1',
                showAllArtifacts && 'max-h-[300px] overflow-y-auto'
              )}
            >
              {visibleArtifacts.map((artifact) => {
                const IconComponent = getFileIcon(artifact.type);
                const isSelected = selectedArtifact?.id === artifact.id;

                return (
                  <button
                    key={artifact.id}
                    onClick={() => onSelectArtifact(artifact)}
                    className={cn(
                      'flex w-full cursor-pointer items-center gap-1.5 rounded-md px-2 py-1 text-left transition-colors',
                      isSelected ? 'bg-accent/60' : 'hover:bg-accent/30'
                    )}
                  >
                    <IconComponent
                      className={cn(
                        'size-3.5 shrink-0',
                        isSelected
                          ? 'text-foreground/70'
                          : 'text-muted-foreground/60'
                      )}
                    />
                    <span
                      className={cn(
                        'truncate text-sm',
                        isSelected ? 'text-foreground' : 'text-foreground/80'
                      )}
                    >
                      {artifact.name}
                    </span>
                  </button>
                );
              })}
            </div>
            {hasMoreArtifacts && (
              <button
                onClick={() => setShowAllArtifacts(!showAllArtifacts)}
                className="text-muted-foreground hover:text-foreground w-full py-2 text-center text-xs transition-colors"
              >
                {showAllArtifacts
                  ? 'Show less'
                  : `Show ${artifacts.length - 10} more`}
              </button>
            )}
          </>
        )}
      </CollapsibleSection>

      {/* 3. Tools Section - MCP tools */}
      <CollapsibleSection title={t.task.tools} defaultExpanded={false}>
        {mcpTools.length === 0 ? (
          <EmptyState icon={Wrench} description={t.task.noTools} />
        ) : (
          <>
            <div
              className={cn(
                'space-y-1',
                showAllTools && 'max-h-[300px] overflow-y-auto'
              )}
            >
              {visibleTools.map((tool) => {
                const IconComponent = getToolIcon(tool.name);
                return (
                  <button
                    key={tool.id}
                    onClick={() => setSelectedTool(tool)}
                    className={cn(
                      'group flex w-full cursor-pointer items-center gap-1.5 rounded-md py-1 text-left transition-colors',
                      'hover:bg-accent/50',
                      tool.isError && 'text-red-400'
                    )}
                  >
                    <IconComponent
                      className={cn(
                        'size-3.5 shrink-0',
                        tool.isError
                          ? 'text-red-400'
                          : 'text-muted-foreground/60'
                      )}
                    />
                    <span className="text-foreground/80 truncate text-sm">
                      {tool.displayName}
                    </span>
                    {tool.isError && (
                      <span className="shrink-0 rounded bg-red-500/10 px-1 py-0.5 text-[10px] text-red-500">
                        Error
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
            {hasMoreTools && (
              <button
                onClick={() => setShowAllTools(!showAllTools)}
                className="text-muted-foreground hover:text-foreground w-full py-2 text-center text-xs transition-colors"
              >
                {showAllTools
                  ? 'Show less'
                  : `Show ${mcpTools.length - DEFAULT_VISIBLE_COUNT} more`}
              </button>
            )}
          </>
        )}
      </CollapsibleSection>

      {/* 4. Skills Section */}
      <CollapsibleSection title={t.task.skills} defaultExpanded={false}>
        {loadingSkills ? (
          <div className="text-muted-foreground flex items-center gap-2 py-2">
            <Loader2 className="size-4 animate-spin" />
            <span className="text-sm">{t.common.loading}</span>
          </div>
        ) : usedSkillNames.size === 0 ? (
          <EmptyState icon={Sparkles} description={t.task.noSkills} />
        ) : skillsDirs.length === 0 ? (
          // Show skill names only if skill files couldn't be loaded
          <div className="max-h-[300px] space-y-1 overflow-y-auto">
            {Array.from(usedSkillNames).map((skillName) => (
              <div
                key={skillName}
                className="flex items-center gap-2 rounded-md px-2 py-1.5"
              >
                <Sparkles className="text-muted-foreground/60 size-3.5 shrink-0" />
                <span className="text-foreground/80 truncate text-sm">
                  {skillName}
                </span>
              </div>
            ))}
          </div>
        ) : (
          // Show skill files/content
          <div className="max-h-[300px] space-y-0.5 overflow-y-auto">
            {skillsDirs.map((dir) => (
              <div key={dir.name}>
                {dir.files.map((file) => (
                  <FileTreeItem
                    key={file.path}
                    file={{ ...file, isExpanded: false }}
                    onSelectFile={onSelectWorkingFile}
                    onSelectArtifact={onSelectArtifact}
                  />
                ))}
              </div>
            ))}
          </div>
        )}
      </CollapsibleSection>

      {/* Tool Preview Modal */}
      {selectedTool && (
        <ToolPreviewModal
          tool={selectedTool}
          onClose={() => setSelectedTool(null)}
        />
      )}
    </div>
  );
}

// Export types for external use
export type { WorkingFile };
