# Changelog

## v0.1.1

- Normalize Windows 8.3 temporary paths in installer tests before comparing configuration paths. Unicode path checks remain enabled.

## v0.1.0

- Persistent local account identities prevent credential overwrite when OAuth omits cloud identity fields.
- Account failover on concurrency/rate/auth/model errors, with one attempt per limited account and one retry after successful authentication refresh.
- Idle-account selection and persisted successful conversation affinity.
- Cooldown responses include Retry-After; cooldown kinds survive restart.
- Windows installer, start/stop/account-management desktop entries, random local API keys and installation backups.
- Release packaging excludes credentials, logs and local state; includes SHA-256 checksums.
- Regression tests cover anonymous logins, known duplicates, failover, expired credentials, cooldown, busy accounts, restart affinity and no replay after streaming begins.

All-account waiting/heartbeat recovery, proactive quota tracking, daily quota freeze/reset and guaranteed uninterrupted DSH execution are **not implemented** in this release.
