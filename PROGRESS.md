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

### 1. Admin page, appearance and sites

- [ ] Per site theme validation and storage: `accent` as a strict hex colour, `position` as an enum of `bottom-right` or `bottom-left`, `launcher_label` as plain text. The `theme` column already exists and is already delivered to the widget by `/api/session/me`.
- [ ] Widget honours the theme. Accent drives the bubble, header and send button. Position moves the bubble and panel to the chosen corner, including in the mobile fullscreen rules.
- [ ] Staff only admin endpoints to list, create, update and disable sites. These are guarded by Discourse's staff check and never by a bridge token: the widget API is for visitors on other websites, administration is a forum concern.
- [ ] The admin page itself, under Admin, Plugins. A list of sites, a form per site, and the generated script tag shown ready to copy.
- [ ] The security warning lives **on the form**, beside the origin field, not in a document. Registering a site grants it cross origin access with credentials, so a cross site scripting hole on that site reaches forum accounts. An admin adding a partner's site must be told at the moment they add it.
- [ ] A one channel option, for support style deployments. Note in the page that a shared channel means everyone sees everyone's messages, and that direct messages are disabled for such a site by design.

### 2. Ready for other people to install

This is the point of the project, so it comes before more features.

- [ ] `README.md` rewritten for a stranger: what it is, a screenshot, the install steps, the settings that must change, and what it does not do.
- [ ] `SECURITY.md` with the threat model in plain words, especially the CORS with credentials trade and the trust level gate.
- [ ] `CONTRIBUTING.md` and `CHANGELOG.md`.
- [ ] A compatibility note naming the Discourse version this is tested against, and `tests/loadcheck.rb` as the thing to run after an upgrade.
- [ ] A draft announcement for meta.discourse.org, in prose rather than bullets.

### 3. Voice messages

- [ ] Detect that `authorized_extensions` has no audio format and say exactly what to add. Do not edit a forum wide upload policy without being asked. See decision 0011.
- [ ] Record with `MediaRecorder`, handling that Chrome produces WebM Opus and Safari produces MP4 AAC.
- [ ] Upload through the bridge as the user, attach to a chat message with `upload_ids`.
- [ ] Play back inline in the widget, and check how the message looks to a normal forum user in the forum's own chat.

### 4. One to one calls

Off by default, with a global setting and a per site toggle. Group calls are out of scope, see decision 0009.

- [ ] Signalling endpoints, polled fast but only while a call is being set up. See decision 0010 for why the normal three second transport is too slow here.
- [ ] Peer to peer WebRTC with public STUN. Optional TURN, configured by the admin.
- [ ] Ringing, accept, decline, hang up, and a microphone permission prompt that explains itself.
- [ ] Fail clearly when a direct connection cannot be established, rather than spinning. Some networks genuinely cannot connect without a relay, and the widget should say so.
- [ ] Post a short "call started" and "call ended" line into the conversation, so there is a record in the forum.

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
