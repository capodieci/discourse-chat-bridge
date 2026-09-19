# Progress

## Done

- Phase 0, discovery. Read-only inspection of the host and of the installed Discourse source. Delivered `docs/discovery-report.md`. The server was not modified in any way.
- Architecture settled: a Discourse plugin, not an external bridge. See `docs/decisions.md` record 0002.
- Domain model written for the chosen architecture. See `docs/domain-model.md`. Three tables instead of the twelve the brief anticipated.

- RAM resized to 4 GB and disk grown by 20 GB. Verified: 1.8 GB available, swap back to zero, 60 G free, forum returning HTTP 200. Recorded in `docs/server-changes.md`.
- Phase 1 code written. Repository restructured to the Discourse plugin convention, with `plugin.rb` at the root so the repo can be cloned directly by `app.yml`. Fourteen Ruby files, all syntax checked against the container's own Ruby interpreter.

## Next: install the plugin

Waiting on Rob's explicit approval for the rebuild, per safety rule 2. The exact plan:

1. Take a Discourse backup and confirm the file exists on disk.
2. Copy `app.yml` to a timestamped backup beside it.
3. Add the plugin clone hook and `DISCOURSE_ENABLE_CORS: true` to `app.yml`.
4. `./launcher rebuild app`, once. This is the only forum downtime in the project.
5. Verify the forum is exactly as before: homepage, login, chat, live updates, uploads.
6. Turn on `chat_bridge_enabled`, set `cors_origins`, register the first site with `rake chat_bridge:site:add`.
7. Confirm `GET /chat-bridge/health` answers.

Rollback if anything goes wrong: restore the timestamped `app.yml` and rebuild again. The plugin adds three new tables and touches no existing ones, so removing it cannot damage forum data.

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
