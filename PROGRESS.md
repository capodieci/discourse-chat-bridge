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

### 2. Admin page, all per site settings

Built after voice so the voice toggle is part of it from the start rather than bolted on.

- [ ] Per site theme validation and storage: `accent` as a strict hex colour, `position` as an enum of `bottom-right` or `bottom-left`, `launcher_label` as plain text. The `theme` column already exists and is already delivered to the widget by `/api/session/me`.
- [ ] Widget honours the theme. Accent drives the bubble, header and send button. Position moves the bubble and panel to the chosen corner, including in the mobile fullscreen rules.
- [ ] Per site feature toggles: direct messages on or off, voice messages on or off, and the single channel option for support style deployments.
- [ ] Staff only admin endpoints to list, create, update and disable sites. Guarded by Discourse's staff check and never by a bridge token: the widget API is for visitors on other websites, administration is a forum concern.
- [ ] The admin page itself, under Admin, Plugins. A list of sites, a form per site, and the generated script tag ready to copy.
- [ ] The security warning lives **on the form**, beside the origin field, not in a document. Registering a site grants it cross origin access with credentials, so a cross site scripting hole on that site reaches forum accounts. An admin adding a partner's site must be told at the moment they add it.
- [ ] Note on the one channel option that a shared channel means everyone sees everyone's messages, and that direct messages are disabled for such a site by design.

### 3. What the visitor can change

Small, and worth doing because the alternative is people asking Rob.

- [ ] A settings menu in the panel: notification sound on or off, and light or dark instead of following the system.
- [ ] Per viewer preferences live in `localStorage`, wrapped in try/catch, because they are conveniences and must not break the widget when storage is blocked.
- [ ] Mute a channel, which is a real Discourse membership setting rather than a widget one, so it follows the person back to the forum.

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
