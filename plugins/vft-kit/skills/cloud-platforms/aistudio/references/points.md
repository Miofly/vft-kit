# Points workflow

## Points workflow

Read the current rules page before automation because rewards and limits can change. Prefer truthful, useful actions and stop if the page conflicts with this skill.

Default daily sequence:

1. Sign in if eligible.
2. Run one existing free project once; do not start paid/GPU resources.
3. Fork one relevant, high-quality public project not already forked.
4. Join one free, relevant course not already joined.
5. Register for one open, free contest only when it needs no payment, team creation, sensitive data, or additional terms acceptance.
6. Complete eligible new-user or learning-map tasks only when the actual action is performed.

Current UI can open actions in a new tab, redirect legacy routes, or reuse a different existing project/runtime. After Fork or runtime actions, verify the resulting `project/edit/<id>` is the intended project, hover the live resource status card to read the actual hardware and displayed points/hour, and recheck `/my/project`. The selected pre-start card and a Codelab URL are not sufficient proof. If the project ID differs, the live card shows a nonzero price, or any unexpected project is `运行中`, stop it immediately and verify every project is `未运行` before continuing.

For sign-in, inspect `/my/project` first: hover the top blue console icon (`.header-tool-item-console`) to open the account/points popover, then click the highlighted current-day sign-in item. Verify the reward toast, total-points delta, and `已签到` state. Do not conclude sign-in is unavailable from `/overview` alone, and do not invent or call an internal endpoint. Treat reward values shown in the live points panel as authoritative when they conflict with an older rules document. For courses opened in a zero-size popup, close the popup and navigate an existing real tab directly to the course URL, then verify enrollment under `/my/learn`.

Require confirmation before commenting, changing the avatar, creating content from user material, or publishing a project/dataset. The private daily-points wrapper may run an explicitly authorized, licensed ModelScope allowlist rotation; it must cap creation at one new dataset per day, record sources, avoid duplicates, and refuse visibility toggles. Never mass-create, duplicate, empty-comment, immediately delete, repeatedly publish low-quality content, or perform other activity whose primary purpose is gaming points.

If the user explicitly authorizes the current task “公开数据集积分+5”, an existing suitable dataset may be published, or a clearly licensed public dataset such as a ModelScope benchmark may be imported into a new AI Studio dataset and published, after checking its contents, license, and final public status. Do not create a duplicate dataset or toggle visibility solely to retrigger a reward; an already-public dataset is a verification result, not a reason to mutate it.

There may be no points ledger. Verify each action by its success toast/task state and, when visible, the total-points delta. Report completed, skipped, blocked, and unverified items separately.

For daily acceptance, reload the document and reopen the points popover; a query-only SPA navigation can retain old state. Read only the unique visible, fully loaded panel and record the account's calendar date, capture time, URL, total points and each task row. Do not delete popover DOM to simulate freshness. Earlier `已签到` days, a previously public project, an accumulated log, a prior final report, or an Agent process exit=0 cannot prove today's completion. Missing/hidden/conflicting rows are unverified; any required `去完成` row prevents an overall success result. Bind sign-in click verification to the same highlighted index and observed reward delta, not just the count of historical completed days. Recheck exact created/published IDs, real dataset files and target runtime state separately. Scheduled wrappers should isolate each run's artifacts and independently read the final UI before returning success; serialize retries and verify previous child processes have ended before starting another run.
