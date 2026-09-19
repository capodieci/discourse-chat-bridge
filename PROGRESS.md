# Progress

## Done

- Phase 0, discovery. Read-only inspection of the host and of the installed Discourse source. Delivered `docs/discovery-report.md`. The server was not modified in any way.
- Architecture settled: a Discourse plugin, not an external bridge. See `docs/decisions.md` record 0002.
- Domain model written for the chosen architecture. See `docs/domain-model.md`. Three tables instead of the twelve the brief anticipated.

## Next: Phase 1

Write the plugin skeleton, then install it. In this order, because the rebuild that installs it should happen once, with everything it needs already in place.

1. Plugin skeleton: `plugin.rb`, migrations for the three tables, the auth endpoints, a health endpoint. No widget yet.
2. Push to GitHub so `app.yml` can reference it.
3. One rebuild, which does two things at once: installs the plugin, and sets `DISCOURSE_ENABLE_CORS: true`. Preceded by a backup, an `app.yml` copy, and a disk and RAM check, per the safety rules.
4. Set `cors_origins` to the target sites in the admin UI. No downtime.
5. Verify the forum is exactly as before: homepage, login, chat, live updates, uploads.

Prerequisite: the RAM resize to 4 GB should happen first. A rebuild with 44 plugins on 2 GB of RAM, while the forum is live, is the riskiest operation in this project.

## Decided

- Architecture: Discourse plugin, Ruby. Approved by Rob, supersedes the brief's plugin-free and PHP rules.
- No separate bridge hostname. The plugin serves from `zoobc.pro` directly.
- Embedding targets: `https://zoobc.com`, `https://zoobc.foundation`, then `https://zoobc.network` and `https://zoobc.net`.
- Trust level 1 gate stays as it is. New signups cannot chat until they earn TL1.
- Staff accounts: not applicable any more, since no API keys are minted.

## Open questions for Rob

1. When would you like to do the RAM resize, and do you want me to take a Discourse backup immediately before it?
2. The rebuild in step 3 is the only forum downtime in the whole project. Is there a time of day that is quietest for your users?

## Not yet started

- Phases 2 through 6.
