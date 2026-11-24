// Extract from supabase/functions/st8-gateway/index.ts (v0.8.0).
const ASIX2_STAGING_PROJECT_REF = "liiowoclsddlywabvmcg";

function assertStagingProject(): void {
  const configuredRef = env("ST8_STAGING_PROJECT_REF");
  if (env("ST8_ENVIRONMENT") !== "staging" || configuredRef !== ASIX2_STAGING_PROJECT_REF) {
    throw new Error("ST8_STAGING_ENVIRONMENT_REQUIRED");
  }

  let configuredUrl: URL;
  try { configuredUrl = new URL(requiredEnv("SUPABASE_URL")); }
  catch { throw new Error("ST8_STAGING_PROJECT_URL_INVALID"); }

  if (configuredUrl.protocol !== "https:"
      || configuredUrl.hostname !== `${ASIX2_STAGING_PROJECT_REF}.supabase.co`
      || configuredUrl.port !== ""
      || configuredUrl.username || configuredUrl.password
      || configuredUrl.pathname !== "/" || configuredUrl.search || configuredUrl.hash) {
    throw new Error("ST8_STAGING_PROJECT_URL_MISMATCH");
  }
}

// Called before URL/method/route handling, so no route can bypass the guard.
try {
  assertStagingProject();
} catch {
  return json({ status: "unknown", error: "STAGING_ONLY" }, 503);
}

// Both Supabase Auth user validation and privileged PostgREST RPC requests:
{
  cache: "no-store",
  redirect: "error",
  signal: AbortSignal.timeout(8_000),
}
