/**
 * useCloudProviders — React hook for cloud provider management
 *
 * 桥接 providers-sync.ts 和 ModelSettings UI。
 * 提供与旧 settings.providers[] 兼容的接口，但数据源是云端。
 */

import { useCallback, useEffect, useRef, useState } from 'react';

import {
  fetchProviders,
  createCloudProvider,
  updateCloudProvider,
  deleteCloudProvider,
  setDefaultCloudProvider,
  testCloudProvider,
  type CloudProvider,
  type CreateProviderPayload,
  type UpdateProviderPayload,
  type TestResult,
} from '@/shared/sync/providers-sync';
import { supabase } from '@/shared/lib/supabase';

export interface UseCloudProvidersReturn {
  /** 云端 provider 列表 */
  providers: CloudProvider[];
  /** 是否正在加载 */
  loading: boolean;
  /** 错误信息 */
  error: string | null;
  /** 是否已登录 */
  isAuthenticated: boolean;
  /** 刷新列表 */
  refresh: () => Promise<void>;
  /** 创建 provider */
  create: (payload: CreateProviderPayload) => Promise<CloudProvider>;
  /** 更新 provider */
  update: (id: string, payload: UpdateProviderPayload) => Promise<CloudProvider>;
  /** 删除 provider */
  remove: (id: string) => Promise<void>;
  /** 设为默认 */
  setDefault: (id: string) => Promise<void>;
  /** 测试连通性 */
  test: (id: string) => Promise<TestResult>;
}

export function useCloudProviders(): UseCloudProvidersReturn {
  const [providers, setProviders] = useState<CloudProvider[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const mountedRef = useRef(true);

  // Check auth state
  useEffect(() => {
    const checkAuth = async () => {
      const { data: { session } } = await supabase.auth.getSession();
      setIsAuthenticated(!!session);
    };
    checkAuth();

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setIsAuthenticated(!!session);
    });

    return () => {
      subscription.unsubscribe();
    };
  }, []);

  // Fetch providers on mount and auth change
  const refresh = useCallback(async () => {
    if (!isAuthenticated) {
      setProviders([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const data = await fetchProviders();
      if (mountedRef.current) {
        setProviders(data);
      }
    } catch (err) {
      if (mountedRef.current) {
        setError(err instanceof Error ? err.message : 'Failed to load providers');
      }
    } finally {
      if (mountedRef.current) {
        setLoading(false);
      }
    }
  }, [isAuthenticated]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  useEffect(() => {
    return () => {
      mountedRef.current = false;
    };
  }, []);

  const create = useCallback(async (payload: CreateProviderPayload): Promise<CloudProvider> => {
    const provider = await createCloudProvider(payload);
    await refresh();
    return provider;
  }, [refresh]);

  const update = useCallback(async (id: string, payload: UpdateProviderPayload): Promise<CloudProvider> => {
    const provider = await updateCloudProvider(id, payload);
    await refresh();
    return provider;
  }, [refresh]);

  const remove = useCallback(async (id: string): Promise<void> => {
    await deleteCloudProvider(id);
    await refresh();
  }, [refresh]);

  const setDefault = useCallback(async (id: string): Promise<void> => {
    await setDefaultCloudProvider(id);
    await refresh();
  }, [refresh]);

  const test = useCallback(async (id: string): Promise<TestResult> => {
    return await testCloudProvider(id);
  }, []);

  return {
    providers,
    loading,
    error,
    isAuthenticated,
    refresh,
    create,
    update,
    remove,
    setDefault,
    test,
  };
}
