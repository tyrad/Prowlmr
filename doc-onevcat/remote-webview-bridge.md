# Remote WebView Bridge

## Purpose

Remote H5 pages loaded inside Prowl's remote `WKWebView` can post native notifications into the same notification pipeline used by terminal tasks.

Effects after a successful bridge call:

- The toolbar bell shows the notification in the unified popover.
- Native system notification or local sound follows the existing app settings.
- Clicking the notification in `Notifications` jumps back to the matching remote endpoint page.

## Bridge Name

Use the standard WebKit message handler:

```js
window.webkit.messageHandlers.prowlBridge.postMessage(payload)
```

Handler name: `prowlBridge`

## Supported Payload

Only one message type is supported right now:

```json
{
  "type": "notify",
  "title": "Task complete",
  "body": "Ready to review",
  "tag": "job-123"
}
```

Fields:

- `type`: required, must be `"notify"`.
- `title`: optional string. Leading and trailing whitespace is trimmed.
- `body`: optional string. Leading and trailing whitespace is trimmed.
- `tag`: optional string. Stored by native side for future use, but not interpreted yet.

Validation rules:

- After trimming, `title` and `body` cannot both be empty.
- If `title` is empty but `body` is not, native side uses `body` as the notification title and stores an empty body.
- Unsupported payloads are ignored silently.

## Security Rule

Bridge messages are accepted only when the current page URL is the same origin as the configured remote endpoint:

- Same scheme
- Same host
- Same port, with default normalization:
  - `http` -> `80`
  - `https` -> `443`

If the webview has navigated to another origin, `postMessage` still executes in H5, but native side ignores the payload.

## Example

```js
function notifyNative({ title, body = "", tag }) {
  const bridge = window.webkit?.messageHandlers?.prowlBridge
  if (!bridge) return false

  bridge.postMessage({
    type: "notify",
    title,
    body,
    tag,
  })
  return true
}

notifyNative({
  title: "Build passed",
  body: "main is ready for review",
  tag: "build-main-42",
})
```

## Recommended H5 Wrapper

If the page may also run in a regular browser, wrap the bridge call:

```js
export function postProwlNotification(title, body = "", tag) {
  const handler = window.webkit?.messageHandlers?.prowlBridge
  if (!handler) return false

  handler.postMessage({
    type: "notify",
    title,
    body,
    tag,
  })
  return true
}
```

## Current Scope

This bridge is intentionally narrow:

- H5 -> native only
- notification posting only
- clicking a notification restores the endpoint page only

Not included in this iteration:

- in-page route restoration
- native -> H5 callbacks
- notification read state sync back to H5
- notification de-duplication by `tag`
