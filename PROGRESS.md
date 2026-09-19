# Progress

## Live and working

The plugin is deployed on `zoobc.pro`. The widget signs visitors in, lists channels, shows history, sends messages, and now finds people and starts direct messages. Rob and another member have held a real conversation through it.

## Direct messages, added 2026-09-19

There was previously no way to message a specific person: the widget only showed channels the visitor already followed.

- **Finding people** goes through `Chat::SearchChatable` with the visitor's guardian, so results are exactly the people that visitor may see. The bridge never queries the user table itself, so it cannot become a way to enumerate the membership.
- **Opening a conversation** uses `Chat::CreateDirectMessageChannel` with `upsert`, so asking twice returns the existing conversation instead of creating a duplicate.
- A site with `allowed_channel_ids` set does **not** get direct messages. A DM channel is created on demand and can never appear in an allow list written in advance, and silently permitting it would widen a configuration that was deliberately narrowed.
- Inherited limits, surfaced rather than hidden: `direct_message_enabled_groups` is trust level 1, the same gate as chat, and `chat_max_direct_message_users` caps a conversation at 20 people.

Verified in a browser end to end: New message, typing a name character by character, results with avatars, opening the conversation, sending, and the message rendering back.

### Three bugs the browser testing caught

1. **Back bounced straight into a conversation.** `loadChannels` auto-opened the first channel whenever none was active, which is right on first load and wrong after an explicit Back, so the channel list could never be reached.
2. **No Back button at all with one channel.** Hiding it looked tidy and was a trap, because the channel list is also where New message lives. A visitor following a single channel could never start a DM.
3. **Direct messages were titled with your own name in them**, so a conversation with one person read as "you, them". Notes to self still fall back correctly, since that is a real Discourse feature rather than an empty case.

## Next: the appearance admin page

Decided with Rob: a real admin page under Admin, Plugins, per site, covering accent colour, corner position and launcher label. The per site `theme` column already exists and is already delivered to the widget, so the storage and the transport are done. What remains is validation, the widget honouring it, staff only endpoints, and the Ember page itself.

Not started.

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
