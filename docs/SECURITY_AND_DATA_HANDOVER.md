# Security and data-transfer rules for casino handover

## Never put these values in the handover ZIP or frontend

- Database password / connection URI with embedded password.
- Supabase service-role key or secret API keys.
- JWT signing secret/private signing key.
- Edge Function secret values.
- SMTP, OAuth client secrets, payment-provider secrets, webhook signing secrets.

Set secrets directly in the recipient's secure secret manager. The `super-worker` source expects `PROJECT_URL`, `PUBLIC_KEY`, and `SERVICE_ROLE_KEY`; only the publishable key belongs in browser config. Check other deployed functions for their own environment variables before rollout.

## Production data requires a separate decision

The optional data dump may reveal user IDs, game rooms, action history, wallet balances and financial transactions. Keep it outside the normal source ZIP, encrypt it before transfer using a channel controlled by the casino, restrict access to named administrators, and record who received it. Follow the applicable Georgian and destination-jurisdiction privacy, AML, gambling, financial-record and retention requirements with qualified counsel.

Do not export passwords/password hashes or Supabase Auth internal tables through this application-schema export. Recreate identities with the destination Auth provider or follow an approved account-migration process.

## Destination safeguards

- New project owned by the recipient; separate from the source project.
- Rotate all secrets and keys; do not reuse source project credentials.
- Set correct Auth redirect URLs and SMTP/OAuth configuration.
- Verify RLS, grants, function `search_path`, `SECURITY DEFINER` ownership and execute privileges.
- Keep `super-worker` JWT verification enabled (`verify_jwt=true`) unless there is a separately reviewed reason to change it.
- Enable leaked-password protection before public launch and review security advisor findings.
- Perform financial reconciliation and payout tests before allowing real users or funds.
