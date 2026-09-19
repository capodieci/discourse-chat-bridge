# Progress

## Done, deployed, and verified in a real browser

Phase 0 discovery, the plugin architecture decision, the domain model, Phase 1 infrastructure and Phase 2 in full. The plugin is live on `zoobc.pro` and the widget has been driven end to end in headless Chromium from `http://localhost:8000`, a genuinely different origin.

### What the browser test proved, on 2026-09-19

- Widget loads cross origin, mounts, opens its shadow root, renders the bubble at 56x56.
- **Style isolation holds.** A probe element on the host page sharing the widget's internal class names picked up none of its styling.
- Panel opens at 370x540 with the correct header and sign in prompt.
- The sign in popup opens and lands on `https://zoobc.pro/login`, the forum's own login.
- Cross origin `fetch` to `/chat-bridge/health` succeeds, so CORS is correct in a real browser and not only in curl.
- Signed in: channel list loads, a channel opens, the real forum message renders with author, avatar and timestamp, composer and sign out appear.
- **Sending works.** A message typed into the composer and sent with Enter reached Discourse and rendered back. It was deleted immediately afterwards.
- Zero console errors, zero page errors, zero failed requests across every run.

### Bugs the testing found, all fixed

1. **`/channels/list` returned 500.** The presenter asked a membership record for `unread_count`, which is not a method it has. Unread lives in `Chat::TrackingStateReport`. The 39 checks were all passing while this was broken, because they tested pure functions and had never handed the presenter a real Discourse object. Six integration checks now cover exactly that.
2. **`session/me` returned a raw `avatar_template`** instead of an absolute `avatar_url`, unlike every other endpoint. Now uses the presenter like the rest.
3. **Two checks used origins a real deployment might register**, so registering `localhost:8000` for testing made a check fail on uniqueness and look like a validation bug.
4. **The demo page reported "no widget script tag found"** on a page where the tag was present and working. Its inline script read the tag before the parser had reached it.

45 self checks now pass against the live forum.

### Testing leftovers, all cleaned up

- Test message deleted, test token revoked, `http://localhost:8000` removed from `cors_origins`, local server stopped.
- Production state confirmed afterwards: `cors_origins` back to the three real sites, zero active tokens, one live chat message, forum answering 200.

## Decided

- Architecture: Discourse plugin, Ruby. Approved by Rob, supersedes the brief's plugin-free and PHP rules.
- No separate bridge hostname. The plugin serves from `zoobc.pro` directly.
- Embedding targets: `https://zoobc.com`, `https://zoobc.foundation`, then `https://zoobc.network` and `https://zoobc.net`.
- Trust level 1 gate stays as it is. New signups cannot chat until they earn TL1.
- Staff accounts: not applicable any more, since no API keys are minted.

## Open questions for Rob

1. Approval for the rebuild command itself, which safety rule 2 requires to be explicit and specific.

## Not yet started

- Phase 2, the widget itself: login, one public channel, history, send, receive.
- Phases 3 through 6.
