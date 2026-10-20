# Browser login and multi-account isolation

## Browser login

Use one named ego-browser task space for the user task. Complete it with `keep: false` unless the user needs the live page.

When a private wrapper reserves a dedicated space for a scheduled task, other AI Studio tasks must not reuse it. Existing user authorization to resume/reclaim that task carries across retries; follow the documented ownership-specific claim/takeOver API. `useOrCreateTaskSpace` metadata is not a Page-capable TaskSpace; use `taskSpace(id)` and enumerate managed Pages instead of assuming a stale page label exists. CAPTCHA, QR login and 2FA still require the handoff below.

1. Open `https://aistudio.baidu.com` in the task space.
2. If logged out, click the normal login control and call `handOffTaskSpace`.
3. Ask the user to finish password, QR, captcha, or 2FA in the visible browser.
4. Continue only after the user confirms; call `takeOverTaskSpace` and verify the logged-in UI.

Never ask for, read, store, inject, or replay cookies/passwords. Do not use `AISTUDIO_ACCESS_TOKEN` to bypass web login.

For a second AI Studio account, isolate by ego lite profile, not by task space: every space on one profile shares its cookie jar, so logging in another account there signs out the first. Create the space with `taskSpace(name, { profileId })` (list ids with `profiles()`), verify `listTaskSpaces()` reports that `profileId`, and pass `profileId` explicitly for every scheduled space because ego creates unpinned spaces in the most recently active profile. Private wrappers own the account-to-profile mapping.
