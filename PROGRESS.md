# Progress

## Done

- Phase 0, discovery. Read-only inspection of the host and of the installed Discourse source. Delivered `docs/discovery-report.md`. The server was not modified in any way.

## Next

- Blocked on one decision: Discourse plugin versus external bridge. See section 13 of the discovery report. No code will be written until this is settled, because the two paths share almost nothing.

## Open questions for Rob

1. Architecture: plugin or external bridge. Recommendation is plugin, for the reasons in the discovery report.
2. Which external origin should be allowed to embed the widget first. Default if unanswered: `https://zoobc.pro` plus a local test page.
3. `chat_allowed_groups` is currently trust level 1 and above, so brand new signups cannot use chat. This conflicts with the stated requirement that chat works immediately on signup. Lowering it to include trust level 0 increases spam exposure. Decision needed.
4. RAM resize to 4 GB, permanent. Agreed in principle, not yet performed.

## Not yet started

- Phases 1 through 6.
