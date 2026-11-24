## 0.7.1 — alert delivery lease and destination hardening

- Alert webhook URLs now require an exact configured hostname allowlist; wildcard hosts, IP literals, localhost/local/internal names, custom ports, credentials, fragments and non-HTTPS URLs are rejected.
- The dispatcher claims one outbox alert at a time and finishes its lease before claiming the next, preventing later alerts from expiring while queued behind earlier slow webhook requests.
- Added runtime coverage for the exact-host allowlist, unsafe destinations, serial claim/finish ordering and retry result accounting.
- Added `ST8_ALERT_WEBHOOK_ALLOWED_HOSTS` to the staging environment template and documented receiver/worker requirements.
- This is a local staging-tooling hardening release only. No database migration, webhook configuration, Edge Function deployment, ST8 live request or Production change was made.
