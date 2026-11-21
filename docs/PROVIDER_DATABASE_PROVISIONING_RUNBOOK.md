# Provider Database Provisioning Runbook v1.0

Design-only provisioning instructions. No schema changes have been applied to the live ASIX Supabase project.

Use a dedicated provider_internal schema, separate provider_owner/provider_runtime roles, no direct table grants to runtime, and only approved SECURITY DEFINER functions. Restore V154 into isolated staging, generate a migration using the installed Supabase CLI workflow, validate RLS/grants/SQL/concurrency, then re-run existing Q-CARD financial smoke tests before any production decision.