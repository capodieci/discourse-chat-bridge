# Progress

## State

The plugin is live on `zoobc.pro` and in use. Sign in, channels, history, sending, direct messages and people search all work and have been verified in a real browser from another origin. Rob and another member have held a real conversation through it.

Two commands to check an install, both read only and safe against production:

```sh
docker exec app rails runner /var/www/discourse/plugins/discourse-chat-bridge/tests/loadcheck.rb
docker exec app rails runner /var/www/discourse/plugins/discourse-chat-bridge/tests/checks.rb
```

## Plan

Work these in order. Each is a complete deliverable: finish it, verify it in a browser where that applies, commit, push, then stop for review. Do not start the next one in the same pass.

### 1. Voice messages [DONE 2026-09-19]

Verified end to end in a real browser with a fake microphone, and in the forum's own chat.

- [x] Audio formats added to `authorized_extensions`: `m4a`, `webm`, `ogg`, `oga`, `mp3`. Recorded in `docs/server-changes.md` with the undo command.
- [x] Recording picks its format by preference rather than taking the first the browser offers. This turned out to matter: Discourse renders `m4a` and `ogg` as a player but `webm` is absent from its `FileHelper.supported_audio` list, so a webm recording arrives as a plain attachment. Chromium supports `audio/mp4` in `MediaRecorder`, verified rather than assumed, so in practice every browser produces a format the forum renders properly.
- [x] A record control with a live timer, a cancel button and a five minute cap. **Click to start and click to stop, not hold to record.** Hold works badly on desktop and conflicts with text selection, and a five minute message would mean five minutes of holding a mouse button.
- [x] Upload through `UploadCreator` as the visitor, so the file never leaves the process and the visitor's own extension policy and size limits apply. Attaching is restricted to uploads that visitor created, otherwise a client could attach any upload id on the forum, including someone else's private attachment.
- [x] Playback inline, using the browser's own audio controls, which give duration and a progress bar for free and behave the way people expect.
- [x] Confirmed in the forum's own chat: a voice message sent from the widget appears to ordinary members as a playable audio player with its duration, not a download link.
- [x] Microphone requested at the moment of use, and every track stopped afterwards so the browser stops showing a recording indicator.

#### Two bugs found by testing

1. **The sanitizer stripped audio entirely.** `audio` and `source` were not in the allow list, so a voice message would have rendered as an empty bubble.
2. **Attachments are not in cooked HTML at all.** A message that is only a recording has an empty `cooked` string and its file hanging off the `uploads` association, so a presenter reading `cooked` shows nothing. Attachments are now passed as data and the widget builds the player, which also means a future change to Discourse's markup cannot silently break playback.

### 2. Admin page, all per site settings [DONE 2026-09-19]

Built as a server rendered page at **`https://zoobc.pro/chat-bridge/admin`**, after finding that plugin JavaScript compiles into the application bundle at container build time, so an Ember page would have needed a full rebuild to appear and another for every change while building it. Rob chose the server rendered route with that in front of him. It deploys with a restart like the rest of the plugin and cannot break when Discourse changes its admin conventions.

- [x] Per site theme validation and storage. `accent` must be an exact hex colour, `position` is an enum, `launcher_label` is capped. Checked against named colours, `rgb()`, `url()`, `expression()` and a value carrying a semicolon, all refused.
- [x] Widget honours the theme. Verified in a browser: accent reached the bubble and header as `rgb(142, 68, 173)`, the panel moved to the left corner, and the panel title changed.
- [x] Per site feature toggles for direct messages and voice messages, enforced on the server as well as hidden in the widget, because hiding a button is not a permission check. Verified: with direct messages off, the New message button was absent while the microphone remained.
- [x] Staff only admin endpoints, inheriting Discourse's own admin controller. They keep `cors_origins` in step, including removing an origin when a site is disabled, renamed or deleted, while keeping one another enabled site still uses.
- [x] The page itself. Lists every site with its colour, corner, panel title, toggles, active session count and a ready to copy script tag. A site whose origin has fallen out of `cors_origins` is flagged, because that failure is silent in the browser.
- [x] The security warning sits on the page and beside the origin field, saying that a listed site can act as your members.
- [x] The single channel option, offering only open category channels, with a note that everyone in a pinned channel sees everyone's messages and that direct messages are off for such a site.

#### Verified in a browser as a real administrator

A temporary administrator was created for this, used, and deleted. Editing accent, corner and panel title saved and survived a reload. An accent of `red; background:url(//evil)` was refused with a readable message rather than reaching a stylesheet.

**One thing changed on a live site during testing and was reverted:** the zoobc.com theme was briefly set to purple, bottom-left and "Talk to us" while proving the save path, then reset. Subsequent theme testing used the disabled localhost site instead.

#### Coverage note

The single channel select was added after the browser session and its logic verified directly rather than through the page: the channel list and the pinning behaviour were confirmed, but that one control has not been clicked in a browser. It uses the same mechanism as the five fields that were.

### 3. What the visitor can change [DONE 2026-09-19]

A settings panel behind a gear in the panel header. Verified in a browser.

- [x] Notification sound on or off, and light or dark instead of following the system. Verified: forcing dark while the browser reported a light system preference turned the panel background to `rgb(31, 33, 36)` while the host page stayed light, which also demonstrates the Shadow DOM isolation.
- [x] Per viewer preferences in `localStorage`, wrapped in try/catch, and confirmed to survive a reload.
- [x] Mute a channel. Stored on the account rather than in the browser, because it is a real Discourse membership setting. Verified in the database afterwards: `channel=General following=true muted=true`.

#### Notes on the choices

The notification sound is synthesised with the Web Audio API rather than shipped as a file. No request, no asset to cache or go stale, and nothing that can be blocked as a third party resource on the host page. It plays once when enabled, so the choice is audible rather than a claim, and only for messages from someone else.

Appearance required moving the widget's palette to custom properties and defining it twice: once under the media query, skipped when the visitor has chosen light, and once for an explicit dark choice. A media query cannot be overridden by a class, so a single definition would have made the setting a one way door.

Sound and appearance are kept in the browser rather than on the account, because they are preferences about a device. An account level setting would follow someone onto a shared computer. Muting is the opposite case and is deliberately on the account, so it follows the person back to the forum.

#### The bug this found

`state.prefs = loadPrefs()` ran fifteen lines before `PREFS_KEY` was assigned. `var` hoisting meant the key was `undefined` at that point, so `localStorage.getItem(undefined)` returned null and the defaults won every time. Saving worked perfectly, which is exactly what made it invisible: the value was in storage, it was simply never read back. Only reloading the page in a browser showed it.

### 4. Ready for other people to install

This is the point of the project.

- [ ] `README.md` rewritten for a stranger: what it is, a screenshot, the install steps, the settings that must change, and what it does not do.
- [ ] `SECURITY.md` with the threat model in plain words, especially the CORS with credentials trade and the trust level gate.
- [ ] `CONTRIBUTING.md` and `CHANGELOG.md`.
- [ ] A compatibility note naming the Discourse version this is tested against, and `tests/loadcheck.rb` as the thing to run after an upgrade.
- [ ] A draft announcement for meta.discourse.org, in prose rather than bullets.

### Not in scope

Voice and video calls, one to one and group. Dropped by Rob on 2026-09-19. Decisions 0009 and 0010 record the reasoning and what they would cost, so this can be picked up later without redoing the thinking.

## Conventions for this work

- Verify against the installed Discourse source rather than memory. It has been wrong four times so far, and each time the source settled it in minutes.
- Anything user facing gets driven in a real browser before it is called done. Every feature so far has shipped with a bug that only a browser found.
- Clean up after testing: delete test users, revoke tokens, remove test origins from `cors_origins`, and confirm the database is as it was.
- Never touch `app.yml` or rebuild without Rob's explicit yes for that specific command.

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
