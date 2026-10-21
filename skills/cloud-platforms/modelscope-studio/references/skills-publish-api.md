# ModelScope Skills: publish-from-GitHub API contract

Captured from real create traffic on `modelscope.cn` (frontend `2.13.164`) on 2026-10-10, then
replayed headlessly for a 27-skill repository. Everything below is verified by request **and**
independent readback unless explicitly marked *probed only*.

## Authentication: browser session, not SDK token

Skill creation has **no** working token path:

- `POST /api/v1/skills` and `POST /api/v1/skills/github/parse` return `401 {"Code":10010101003,
  "Message":"user not logged in"}` without a session cookie.
- `POST /openapi/v1/skills` exists (returns `401 InvalidAuthentication`, not 404) but is not the
  route the web UI uses; whether an SDK Bearer token satisfies it is **unverified**.
- Read routes are public: `GET /api/v1/skills/{owner}/{name}` and
  `GET /openapi/v1/skills/{owner}/{name}` need no auth at all, which makes verification cheap.

So the write flow runs inside a logged-in browser page (`page.fetch` = `window.fetch` with the
page's cookies). `scripts/publish-skills.mjs` does exactly that through ego-lite and never reads a
token, cookie, or credential file.

Login identity check used before any write: `GET /api/v1/users/login/info` → `Data.Name`.

## Endpoints

| # | Method & path | Body | Returns |
|---|---|---|---|
| 1 | `POST /api/v1/skills/github/parse` | `{"GithubUrl":"https://github.com/<user>/<repo>"}` | `Data.RepoInfo{LatestCommitId,LatestCommitIdUrl}`, `Data.SkillsInfo[]` |
| 2 | `POST /api/v1/skills/user_repeat` | `{"Source":"github","SourceURL":"<tree url>","PageSize":20,"PageNumber":1}` | `Data.Skills[]`, `Data.TotalCount` — non-empty = already published by you |
| 3 | `POST /api/v1/skills/official_repeat` | same as 2 | same shape — non-empty = published by someone else (web UI then offers a claim flow) |
| 4 | `POST /api/v1/skills/github/skillInfo` | `{"GithubUrl":"<tree url>","FilePaths":["<repo path>/SKILL.md"]}` | `Data.SkillInfo[0]{Name,DisplayName,Description,Avatar,License,Developer}` |
| 5 | `GET /api/v1/catalogues?Business=skills` | — | catalogue list; each has `CatalogID`, `Name`, `ChineseName`, `ID` |
| 6 | `POST /api/v1/skills` | see payload below | `Code:200, Success:true`; the web UI then routes to `/skills/{owner}/{name}/setting` |
| 7 | `POST /api/v1/skills/{owner}/{name}/check-update` | `{"Path":"<owner>","Name":"<name>"}` | `Data.Status` = `up_to_date` when GitHub has nothing new. This is what the 手动同步 button calls |
| 8 | `GET /api/v1/skills/{owner}/{name}/repo/files?Revision=master&Recursive=true` | — | `Data.Files[]{Name,Path,Type}` — the synced skill repo tree (`tree`/`blob`) |
| 9 | `PUT /api/v1/users/privilege` | `{"Path":"skills/<owner>","Name":"<name>"}` | `Data.AccessLevel` (50 = owner). Called on settings-page load |

*Probed only* (route exists — anonymous request returns 401 — but not exercised, because a bad
body could mutate or delete a live skill):

- `PUT /api/v1/skills/{owner}/{name}` — metadata edit (the 编辑 button). Note the web create form
  does **not** preselect 所有者, so a blind replay of an edit form risks clearing a field; capture
  the real save request before scripting it.
- `DELETE /api/v1/skills/{owner}/{name}` — the 删除 Skill button.
- `POST /api/v1/skills/{owner}/{name}/sync` — exists alongside `check-update`; `check-update` is
  the one the UI actually calls.
- `PATCH /api/v1/skills/{owner}/{name}` — does **not** exist (404).

## Step 1 response shape

`SkillsInfo[]` describes every `SKILL.md` found in the repository:

```json
{
  "Name": "web-scrape",
  "DisplayName": "",
  "Description": "",
  "SkillPath": "plugins/kit/skills/web-automation/web-scrape/SKILL.md",
  "GithubUrl": "https://github.com/<user>/<repo>/tree/main/plugins/kit/skills/web-automation/web-scrape",
  "SkillGithubUrl": "https://github.com/<user>/<repo>/blob/main/.../SKILL.md",
  "FileList": ["SKILL.md", "scripts/worker.py"]
}
```

- `DisplayName`/`Description` are empty here; endpoint 4 fills them from the SKILL.md frontmatter.
- `FileList` paths are relative to the skill directory and become the synced file set.
- `GithubUrl` (the `tree/...` URL) is the identity key for endpoints 2/3 and the `SourceUrl` field.

## Step 6 payload (verbatim from a successful create)

```json
{
  "Name": "notify",
  "DisplayName": "notify",
  "SourceUrl": "https://github.com/<user>/<repo>/tree/main/plugins/kit/skills/agent-ops/notify",
  "Path": "<owner>",
  "License": "Apache License 2.0",
  "Visibility": 5,
  "Description": "…from SKILL.md frontmatter…",
  "L1": "developer-tools",
  "Tags": [],
  "SourceAvatar": "https://resouces.modelscope.cn/proxy-image/<id>.png",
  "AutoSyncEnabled": 1,
  "Files": [{ "FilePath": "SKILL.md" }, { "FilePath": "scripts/send_ntfy.py" }],
  "SourceDeveloper": "<github owner>",
  "Source": "github"
}
```

Field notes:

- `Name` is the skill slug and is **immutable after creation** (the form says 创建后不可更改).
- `Path` is the ModelScope owner (form label 所有者). The web form leaves it **empty** and only
  fails on submit with `所有者不能为空!` — always set it explicitly when scripting.
- `L1` is a `CatalogID` from endpoint 5. Verified values: `skill-management`, `developer-tools`,
  `marketing-seo`, `frontend-development`, `ai-media`, `code-quality-testing`,
  `mobile-development`, `cloud-devops`, `scientific-tool`, `other`.
- `Visibility`: `5` = 公开. The 非公开 value was not captured.
- `License`: endpoint 4 usually returns `""`; the UI falls back to the first entry of its license
  list, `Apache License 2.0`.
- `SourceAvatar` comes from endpoint 4 (`Avatar`) — ModelScope derives an icon from the GitHub repo.
- `AutoSyncEnabled`: `1` makes ModelScope re-pull from GitHub periodically; `0` freezes the copy.
- `Files` decides what lands in the skill's own ModelScope repo. It mirrors the GitHub tree, so
  filter build artefacts (`__pycache__/`, `*.pyc`, `.DS_Store`) yourself — the platform does not.

## Verification (do not trust the create response)

The create call only reports `Success`. Confirm each skill with public, cookie-free reads:

```bash
curl -s "https://modelscope.cn/api/v1/skills/<owner>/<name>"        # SourceURL, Visibility, AutoSyncEnabled, L1.CatalogID, ReadMeContent
curl -s "https://modelscope.cn/openapi/v1/skills/<owner>/<name>"    # install_command, auto_sync_enabled, sync_status, tags
```

`ReadMeContent` is the synced SKILL.md body, so a non-empty value proves the file sync ran, and
`SourceURL` must equal the `tree/...` URL you submitted. Endpoint 8 proves the rest of the file
set arrived. `scripts/publish-skills.mjs` performs this readback per skill and flags mismatches.

## Web UI equivalents

`https://modelscope.cn/skills/create?template=github` is a 3-step wizard (导入Github → 选择
Skills → 确认创建) and creates **one** skill per run, with a single-select radio list. Form field
ids map 1:1 to the payload keys (`Name`, `DisplayName`, `SourceUrl`, `Path`, `License`,
`Visibility`, `Description`, `L1`, `Tags`, `SourceAvatar`, `AutoSyncEnabled`, `Files`). Per-skill
management lives at `/skills/{owner}/{name}/setting` (编辑 / 手动同步 / 删除).

## Publish Skills from a GitHub Repository

ModelScope Skills (`https://modelscope.cn/skills`) can be created from any public GitHub repo that
holds `SKILL.md` directories. The web wizard publishes one skill per run; `scripts/publish-skills.mjs`
publishes or re-syncs a whole repository through the same internal endpoints, headlessly.

Prerequisites: a public GitHub repo, and ego-lite logged in to the ModelScope account that will own
the skills (the script verifies the session identity and aborts on a mismatch). No API token,
cookie, or credential file is read — the calls run as `page.fetch` inside the logged-in page,
because skill creation has no working token route. See `references/skills-publish-api.md` for the
endpoint contract, payload fields, and the routes that are only probed.

```bash
SCRIPT=scripts/publish-skills.mjs

# 1. Plan: what would be created, with which catalogue, description and file set (no writes)
node $SCRIPT --repo https://github.com/<user>/<repo> --owner <modelscope-user> --profile <egoProfileId>

# 2. Publish everything the plan listed
node $SCRIPT --repo ... --owner ... --apply --report /tmp/publish-report.json

# 3. Later: re-pull already-published skills from GitHub (the 手动同步 button, for the whole repo)
node $SCRIPT --repo ... --owner ... --sync

# Narrow a run, override the default catalogue, or check the script offline
node $SCRIPT --repo ... --owner ... --apply --only skill-a,skill-b
node $SCRIPT --repo ... --owner ... --category developer-tools
node $SCRIPT --selftest
```

Behaviour worth knowing:

- Default is **dry-run**; nothing is created without `--apply`.
- Already-published skills are skipped, not duplicated (`user_repeat`); a skill published by
  someone else is reported as `skip-exists-official` and left alone — claiming it is a web-UI flow.
- `--config <file.json>` reads the same keys (`repo`, `owner`, `profile`, `space`, `category`,
  `category_map`, `license`, `visibility`, `autoSync`, `exclude`, `delayMs`) from a `skill_publish`
  object, so a private wrapper can hold the personal defaults and the command stays short.
- `category_map` keys are skill names or any parent directory name; values must be catalogue ids
  from `GET /api/v1/catalogues?Business=skills`. Unknown ids are flagged, not silently sent.
- Description, display name, icon and GitHub developer come from the platform's own SKILL.md parse,
  so frontmatter quality shows up directly on the published page.
- Each created skill is read back through the **public** detail route (`SourceURL`, `Visibility`,
  `AutoSyncEnabled`, `L1.CatalogID`, non-empty `ReadMeContent`) plus the synced repo tree; exit code
  is non-zero on any create failure, readback mismatch, or warning.
- `AutoSyncEnabled=1` keeps the published copy following GitHub. The sync only sees **pushed**
  commits — publish after the change is on the default branch, then `--sync` to pull immediately.
