# Account pool architecture

`internal/auth/auth.go`: LoadDir loads codearts-*.json and persists a local account_id for older files. OAuth cloud identity may be absent; local identity avoids overwrites without inventing cloud identities. cmd/login/account.go rejects selected-account duplication and refreshes a known existing account in place.

`internal/pool/pool.go`: Pool owns disabled state, cooldown kind/deadline, consecutive error count and active slots. PickExcluding favors healthy idle accounts; TryAcquire locks state and permits only configured concurrency. Validate checks expiration, refreshes when necessary and disables permanently expired credentials. Refresh is serialized per account and retains the original DPoP key/client binding.

`internal/server/handler.go`: chatCompletions derives conversation affinity, tries the previous successful account first, then eligible backups. Tried-account tracking avoids repeatedly selecting the same failed account. The account count expands the routing loop beyond the historical MaxRotate limit. The requested model is preserved across accounts.

Errors: model registration/benefit errors affect that account-model pair; rate/concurrency limits trigger soft cooldown; authentication failures disable after attempted refresh; server errors get longer cooldown. If no candidate can serve the request, the handler returns an explicit error, including Retry-After for rate/busy conditions. It does not implement waiting until recovery.

On success, account affinity is saved in the conversation-state file. Full messages are still sent for each turn. Account/session affinity is not a cache guarantee; fallback hashing of the first user message can collide across independent sessions with identical opening content.

Streaming failures after output begins are not retried on another account. Nonstreaming requests can fail over before a response is sent. Response headers identify local routing account and chat ID; successful-request logs include model and usage counts without adding prompts or keys.

`internal/upstream`: Signs requests with the actual chosen account's STS credentials and sends them to Huawei endpoints. Benefit-model metadata is per account; known seeds cover first requests before discovery. FetchModels performs optional benefit claiming, not a daily midnight job.

Windows helper: wait for idle, stop exact installed process and scheduled task, run OAuth login, then restore the proxy in finally. This prevents stale refresh writers during the desktop workflow. The inherited web-panel live credential reload is not the recommended path because refresh/replacement synchronization still requires improvement.

Backups, account credentials, logs and state remain in each user's runtime profile and are excluded from published archives.
