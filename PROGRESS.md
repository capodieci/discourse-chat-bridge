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

Still to do:

1. `public/widget.js`, vanilla JS in a Shadow DOM: corner bubble, panel, channel list, message list, composer.
2. The `Transport` object with `start`, `stop`, `onEvents`, backed by MessageBus.
3. A demo page on a different origin to prove the popup and CORS end to end.
4. Tests for the sanitizer, the origin checks, and the permission checks.

The new endpoints are written but **not deployed**. The plugin running on the forum is still the Phase 1 version. Deploying is a `git pull` in the container plus a Rails restart, which needs approval.

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
