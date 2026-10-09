# Windows local account pool

Runtime: `%USERPROFILE%\.codearts2api\bin`. DSH continues to use `http://127.0.0.1:7866/v1` and its existing local key.

Desktop entry `CodeArts 账号管理.cmd` opens a menu:

1. Add: finish DSH tasks, then sign out of the current Huawei browser account before signing into another account. After waiting for active requests, the helper stops the proxy during browser login and restores it afterwards to prevent stale background refresh overwriting credentials. A known duplicate cloud account is refreshed instead of counted twice. When cloud identity cannot be resolved, distinct quotas are not verified.
2. Re-login: select an existing entry and authenticate the same account. The old credential file is backed up and updated in place, keeping local routing identity.
3. Reload/status: waits up to 60 seconds for active requests to end, restarts the proxy to safely load saved credentials, and shows disabled/cooling/busy states without inference calls.

The pool tries the requested model on each eligible account at most once per routing pass. Rate/concurrency limits cause a temporary cooldown; auth failure disables an account until re-login; unavailable models are skipped for that account. Successful conversation affinity is persisted across proxy restarts. Busy accounts can use idle backups. This preserves affinity where possible but does not guarantee cache hits or eliminate provider-wide limits.

After streaming starts, the proxy does not switch and replay output. If all accounts are limited/busy it returns HTTP 429 with Retry-After; if no credentials are usable for other reasons it returns a clear failure. More accounts cannot guarantee uninterrupted service or additional quota when they share the same upstream identity/limit.

`task-proxy.log` includes successful request local account ID, requested model, and response usage (estimated if the upstream omitted usage). These counts are not the official daily benefit deduction ledger. API keys, STS secrets and chat bodies are not added to these new log lines.

Use Huawei's own login pages for passwords and verification codes. Account files contain sensitive credentials; do not share or commit them. The official free-benefit offer is documented for use inside CodeArts; this external proxy is unofficial.
