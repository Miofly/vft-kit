# Notebook / PAI-DSW Operations

Verified against the domestic ModelScope web application on 2026-08-18.

## Authentication Boundary

| Surface | Authentication | Base path |
|---|---|---|
| Studio deployment | `Authorization: Bearer $MODELSCOPE_API_KEY` | `/openapi/v1/studios` |
| Notebook / PAI-DSW | authenticated ModelScope browser cookie | `/api/v1/notebooks` |

A valid Bearer token does not authenticate Notebook calls. Run them inside the already authenticated browser
session. Do not extract, print, or persist the login cookie.

## Safe Workflow

1. Open `$MODELSCOPE_ENDPOINT/my/mynotebook/preset` in an authenticated browser session.
2. Read specs, images, and current instances before making changes.
3. Confirm accelerator type and whether the resource is free or billable.
4. Start only with a fresh `CaptchaVerify` issued by the page's safety-verification widget.
5. Poll the instance list until it reaches `Running` or a terminal failure state.
6. Return the instance ID, status, image, and opening URL without exposing session credentials.

Browser-side reads can use the page's existing cookie:

```javascript
const get = (path) => fetch(path, { credentials: "include" }).then((r) => r.json());

const [specs, images, instances] = await Promise.all([
  get("/api/v1/notebooks/specs?Channel=dsw"),
  get("/api/v1/notebooks/image?AcceleratorType=CPU"),
  get("/api/v1/notebooks?Channel=dsw"),
]);
```

## Endpoints

| Operation | Method | Path |
|---|---|---|
| List resource specs and quota | GET | `/api/v1/notebooks/specs?Channel=dsw` |
| List images | GET | `/api/v1/notebooks/image?AcceleratorType={CPU|GPU|AMD}` |
| List current/history instances | GET | `/api/v1/notebooks?Channel=dsw` |
| Start an instance | POST | `/api/v1/notebooks` |
| Stop an instance | PUT | `/api/v1/notebooks/stop` |

The web application currently sends this start payload:

```json
{
  "Channel": "dsw",
  "AcceleratorType": "CPU",
  "Image": "<Version returned by the image API>",
  "CaptchaVerify": "<fresh platform-issued verification result>"
}
```

`CaptchaVerify` is a security control, not reusable configuration. Never omit, forge, replay, log, save, or
commit it. If verification appears, hand the same browser session to the user. After they finish, resume in that
session so the page can submit the fresh result normally.

## States

Treat `Running` as ready. Continue polling transitional states such as `Creating`, `Starting`, or `Pending`.
Treat `Failed`, `Stopped`, and `Deleted` as terminal for the current attempt and report the API's error details.

Do not start a paid resource without explicit user authorization. A displayed quota does not prove the next
instance is free; trust the current spec response and page labels.

## Browser Handoff

With ego-browser, keep one named task space for the operation. Use `handOffTaskSpace` when ModelScope presents
interactive verification, then `takeOverTaskSpace` after the user confirms completion. Do not open a second
session because the verification result belongs to the original authenticated page.
