# Progress

## Done

- Phase 0, discovery. Delivered `docs/discovery-report.md`, with host specifics kept out of the public repository in `docs/local/`.
- Architecture settled: a Discourse plugin, not an external bridge. See `docs/decisions.md` record 0002.
- Domain model written. Three tables instead of the twelve the brief anticipated. See `docs/domain-model.md`.
- Phase 1 complete and installed. The plugin is live on the forum.

## Phase 1 result, verified on 2026-09-19

- Backup taken and verified before any change. `app.yml` backed up, then changed by exactly two additions.
- One rebuild. Forum verified healthy afterwards: homepage, `/latest`, `/login`, `/chat`, `/about` all 200. Data intact at 8 users, 319 posts, 261 topics.
- Plugin cloned from GitHub by the container, three migrations ran, `GET /chat-bridge/health` returns 200.
- CORS verified by request. A registered origin gets the plugin's own strict headers. An unregistered origin is refused at the application layer.
- `auth/start` verified: an unknown site key returns 403, a valid one redirects an anonymous visitor to the forum login.
- Three sites registered: `https://zoobc.com`, `https://zoobc.foundation`, `https://zoobc.network`. `https://zoobc.net` planned for later.

## Known issues and debts

1. The forum was upgraded from `2026.8.0` to `2026.9.0` as a side effect of the rebuild, because `./launcher rebuild` always pulls the latest image. This was not flagged before approval. It should be flagged every future time.
2. Three August backups were lost to the retention policy after the backup command was run three times. The two duplicate 19 September copies have since been deleted with Rob's approval, so retention is back to three of five slots. The August backups are not recoverable.
3. `DISCOURSE_ENABLE_CORS` is global, not scoped to the plugin. Every Discourse endpoint now accepts cross origin requests from the two listed sites with credentials. See decision 0005.
4. The plugin ships `CLAUDE.md`, `PROGRESS.md` and `docs/` into the container, because the repository root is the plugin root. Harmless, but untidy for a public release. Worth cleaning up before Phase 6.

## Next: Phase 2, the widget

The server side works and is reachable. What does not exist yet is anything a visitor can see.

Done, written and verified against real forum data, but not yet deployed:

- **Bridge endpoints.** `channels/list`, `channels/mark_read`, `messages/history`, `messages/send`. These call Discourse's own service objects (`Chat::ListUserChannels`, `Chat::ListChannelMessages`, `Chat::CreateMessage`, `Chat::UpdateUserChannelLastRead`) with the bridge guardian, so permissions are Discourse's answer and not ours.
- **`ChatBridge::Sanitizer`.** A second strict pass over Discourse's `cooked` HTML before it crosses to another origin. Uses `Rails::HTML5::SafeListSanitizer`, already present, so no new dependency.
- **`ChatBridge::Presenter`.** Small stable shapes for the widget, so no Discourse serializer is ever exposed to a third party site.
- **`authorized_channel`** in the base controller. Channel ids from the browser are checked against both Discourse's guardian and the site's allow list on every request, and a refused channel returns the same answer as a missing one so the endpoint cannot be used to discover private channels.

- **`public/widget.js`.** Vanilla JS, no build step, rendered entirely inside a Shadow DOM so host page CSS cannot reach it and its own CSS cannot leak out. Corner bubble with unread badge, channel list, message list, composer. Enter sends, Shift and Enter makes a new line. Light and dark both handled through `prefers-color-scheme`. Sign in opens a popup and the token arrives by `postMessage`, with the origin and the state value both checked before it is accepted. No cookies anywhere.
- **Translations.** English is inlined so one script tag is enough with no extra round trip. `data-strings-url` loads another language, and any key missing from it falls back to English, so a partial translation degrades key by key instead of breaking the interface. `public/widget.strings.en.json` is the canonical table for translators and is verified to have exactly the same keys as the inlined one.
- **`Transport`.** Present as an object with `start`, `stop` and `onEvents` and nothing else. The current implementation refetches recent history on an adaptive interval, 3 seconds while open, 12 closed, 30 when the tab is hidden. Crude but correct, and replaceable by MessageBus without any other part of the widget changing.

- **Transport reworked, and MessageBus ruled out for now.** A browser on another domain cannot authenticate to `/message-bus`: its CORS policy allows four request headers and none carries a bearer token, and Discourse's query parameter auth route is restricted to RSS and calendar endpoints. The one header that does work, `X-Shared-Session-Key`, is a session equivalent credential and would turn a cross site scripting hole on an embedding site into full forum account takeover. Rejected. See `docs/decisions.md` record 0006, which also describes the safe way to get real time back.
- **`/api/channels/updates`.** Two integers per channel, two indexed queries, no serializers and no message bodies. The widget polls this and only asks for messages when something actually moved. Exponential backoff on failure, so a struggling forum is not hammered.

- **`demo/index.html`.** A deliberately plain page whose only job is to be somewhere the forum is not. It reports its own origin against the bridge's, checks the health endpoint, confirms the widget mounted and its shadow root opened, and measures whether any widget CSS escaped into the page. Also lists what each failure mode means, so a broken integration diagnoses itself.
- **`tests/checks.rb`.** 39 self checks covering the sanitizer, origin validation, token hashing, revocation, expiry and single use nonces. Written as a plain script rather than RSpec so it runs against a real installation, including production, where no test database exists. Everything that writes runs inside a transaction that always rolls back, and one of the checks verifies the rollback happened.

**All 39 checks pass against the live forum**, run without modifying the deployed plugin. Verified afterwards that the database was unchanged: three sites, zero tokens, zero nonces.

- **`tests/loadcheck.rb`.** A pre-flight that catches what a syntax check cannot: unresolvable constants, a route pointing at a missing action, an error code with no translation, Discourse internals moved by an upgrade. Run against a fresh clone of the repository before deploying: **clean**, all 9 routes map to real actions, all 11 constants resolve, all 7 error codes have translations.

Phase 2 is code complete and every check that can be run without deploying has been run and passes.

## The one thing that cannot be checked from here

The widget has never run in a browser. Every line of Ruby is verified against the live forum; not one line of JavaScript has executed anywhere. Deploying is `git pull` in the container plus a Rails restart, roughly ten seconds, no rebuild. Rollback is `git checkout` of the previous commit and another restart.

Until that happens, treat all of Phase 2 as written but unproven.

## Open, needs a decision from Rob

1. Deploy Phase 2 and drive the demo page against it.
2. Capability scoped MessageBus channels, to restore instant delivery without handing embedding sites a session equivalent credential. See `docs/decisions.md` record 0006.

None of the Phase 2 work is **deployed**. The plugin running on the forum is still the Phase 1 version. Deploying is a `git pull` in the container plus a Rails restart, roughly ten seconds of interruption rather than a rebuild, and it needs approval.

The Ruby has been verified against real forum data. The widget has only been syntax checked and audited by reading: it has never run in a browser, because that requires deploying. Treat it as unproven until it has.

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
