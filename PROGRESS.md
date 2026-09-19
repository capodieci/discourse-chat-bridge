# Progress

## Live and working

The plugin is deployed on `zoobc.pro` and the widget has been driven end to end in headless Chromium from another origin, including the cold path where the visitor has no forum session and logs in through the forum's own login form.

## Phase 2 verification, 2026-09-19

Both sign in paths confirmed working, on desktop and at phone width:

- Already signed in to the forum: popup opens, authorises, closes itself, widget signs in.
- **Not signed in**: popup goes to the forum login, the visitor logs in, the popup returns, authorises and closes, and the widget signs in. This is the path most visitors take, and it was completely broken.
- Channel list, message history with real content, composer, send, mobile fullscreen.
- 50 self checks and the load pre-flight both clean.

## The four production bugs found by testing against the real thing

1. **Content Security Policy blocked the handshake script.** Discourse serves `script-src` with a nonce and `'strict-dynamic'`, under which `'self'` and host allow lists are ignored, so neither an inline script nor an external file runs without the nonce. The popup rendered "Signed in, you can close this window" from static HTML while its script never executed. The page now reports success only after the script has run, so this class of failure is visible rather than a page lying about having worked.
2. **`window.opener` was severed.** Discourse serves `Cross-Origin-Opener-Policy: same-origin-allow-popups`, which cuts the opener when the opening page is on another origin, permanently. Every visitor not already signed in passes through `/login`, so `postMessage` could never work for the common case.
3. **The COOP override had to be an `after_action`.** Discourse sets that header in an `after_action` gated on `spa_boot_request?`, true for any plain GET, so setting it in a `before_action` was silently overwritten.
4. **Cloudflare was caching `widget.js` for a year.** Discourse serves plugin public assets with `max-age=31536000, immutable`, correct for fingerprinted filenames and wrong for a file whose URL must stay stable. `cf-cache-status: HIT` confirmed the embedding site was running the old widget and would have kept doing so. Every fix shipped would have reached nobody, with nothing visible from outside to say so.

## How signing in works now

1. The widget asks `/api/auth/begin` for a handshake and keeps the returned secret in memory. Only the id goes into the popup URL, so the address bar, history and any referrer leak nothing usable.
2. The popup signs the visitor in through the forum and marks the handshake authorised against their user id. It mints nothing, so no usable credential is ever stored.
3. The widget polls `/api/auth/claim` with the id and the secret. The token is minted at claim time, exactly once, for a caller that proves it knows the secret, compared in constant time.

`postMessage` survives only as a shortcut to poll immediately when the opener happened to survive. Nothing depends on it.

## The widget URL changed

```
https://zoobc.pro/chat-bridge/widget.js
```

Not `/plugins/discourse-chat-bridge/widget.js`. The old path is served with a one year immutable cache policy and cannot be updated. The new one is served by a controller with `max-age=300`, `must-revalidate` and an ETag.

**Cloudflare currently overrides that to `max-age=14400`.** The origin sends 300 and Cloudflare rewrites it, which is its Browser Cache TTL setting. Until that is set to respect origin headers, a released fix takes up to four hours to reach browsers.

## Testing leftovers, all removed

Test user deleted, 10 tokens revoked, 11 handshake rows cleared, test messages deleted, `http://localhost:8000` removed from `cors_origins`, local server stopped. Production confirmed afterwards: 8 users, 1 live chat message, 0 active tokens, 0 handshakes, `cors_origins` back to the three real sites, forum answering 200.

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
