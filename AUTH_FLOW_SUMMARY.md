# Sage Auth Flow - Quick Reference

## The Problem
iOS app cannot authenticate with Railway backend because:
1. Frontend has JWT (from Supabase) but sends it in **request body**
2. Backend middleware expects it in **Authorization header**
3. `SAGE_API_TOKEN` hardcoding in app would expose secrets

## The Gap Visualized

```
iOS Frontend                Railway Backend
─────────────              ────────────────
fetch(/agent, {            if (SAGE_API_TOKEN):
  body: {                     check Authorization header
    accessToken: JWT          ✗ No header sent = 401
  }
})
```

## Current Auth Modes

| Platform | Location | Auth Check | Status |
|----------|----------|-----------|--------|
| Desktop (Tauri) | localhost:2026 | IP == 127.0.0.1 | ✓ Works |
| iOS (Capacitor) | Railway | `Authorization: Bearer` | ✗ Fails |

## Key Files

**Frontend**:
- `src/config/index.ts` - Determines API base URL
- `src/shared/lib/supabase.ts` - Gets JWT via `getCurrentAccessToken()`
- `src/shared/hooks/useAgent.ts` - Sends requests to `/agent` with `accessToken` in body

**Backend**:
- `src-api/src/app/middleware/local-only.ts` - Auth middleware (2 modes)
- `src-api/src/app/api/agent.ts` - Agent endpoint
- `src-api/src/shared/supabase/client.ts` - Supabase client factory

## The Solution

**Use Supabase JWT as universal auth token**

1. Frontend: Send `Authorization: Bearer ${accessToken}` header
2. Backend: Validate JWT signature instead of checking hardcoded token
3. Railway env: Remove `SAGE_API_TOKEN`, keep Supabase config
4. Result: iOS works, Desktop still works, secrets not exposed

## Implementation Priority

1. Backend JWT validation function
2. Update middleware to accept JWT header
3. Frontend: Add Authorization header to requests
4. Remove `SAGE_API_TOKEN` from `.env.ios` and Railway

---

**Full analysis**: See `AUTH_FLOW_ANALYSIS.md`
