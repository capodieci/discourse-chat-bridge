# Phase 0: Discovery Report

Date: 2026-09-19
Method: read-only inspection of the host and of the Discourse source inside the running container. No installs, no edits, no restarts. No Rails processes were started, to avoid memory pressure on a live forum.

---

## 1. Host and Discourse install

Details of the specific server this research was carried out on are kept out of this repository, in `docs/local/server-inventory.md`, because an inventory of a live forum is more useful to an attacker than to a reader. What matters for anyone reading this report:

- A standard Discourse Docker install, single container, the container owning ports 80 and 443
- TLS terminated inside the container, with a CDN in front
- Discourse version `2026.8.0-latest.1`
- Chat enabled, a small number of category channels, fewer than ten users
- No outgoing webhooks and no web server or PHP on the host before this project

Everything below was read from the Discourse source inside that container, so it is accurate for `2026.8.0` and should be re-checked against any other version.


## 2. Chat API surface

Confirmed by reading `plugins/chat/config/routes.rb` in the installed version. The chat API is mounted at `/chat/api`. Routes relevant to this project:

- `GET /chat/api/me/channels` : the current user's channel list
- `GET /chat/api/channels/:channel_id` : channel detail
- `GET /chat/api/channels/:channel_id/messages` : message history
- `POST /chat/:chat_channel_id` : create a message (maps to `api/channel_messages#create`)
- `PUT /chat/api/channels/:channel_id/messages/:message_id` : edit
- `DELETE /chat/api/channels/:channel_id/messages/:message_id` : delete
- `PUT /chat/:chat_channel_id/react/:message_id` : toggle a reaction
- `PUT /chat/api/channels/:channel_id/read` : mark read
- `POST /chat/api/direct-message-channels` : open a DM
- `GET /chat/api/chatables` : user and channel search, for mentions and DMs
- Threads: index, create, show, and messages under `/chat/api/channels/:channel_id/threads`

Note that reactions and message creation sit on the older non-`api` paths, while most other operations sit under `/chat/api`. Any client must handle both prefixes.

## 3. Webhook coverage, and the gap

From `app/models/web_hook_event_type.rb`, the only chat event types that exist are:

- `chat_message_created` (1801)
- `chat_message_edited` (1802)
- `chat_message_trashed` (1803)
- `chat_message_restored` (1804)

There are no webhook events for reactions, typing, presence, read state, channel membership changes, channel creation, or thread creation. A webhook-driven design gets message text and nothing else.

Two further facts, both confirmed in source:

- Direct messages do fire webhooks. `Chat::OutgoingWebHookExtension` passes `category_id: nil` for DM channels, and `EmitWebHookEvent#category_webhook_invalid?` only rejects an event when the webhook has an explicit category filter set. With no category filter, DM events are delivered. This is better than expected, but it means a single webhook endpoint receives every private message between every pair of users on the forum, and the receiving service becomes responsible for not leaking them.
- The payload is serialized through `Guardian.new(user)` where `user` is the message author, not the recipient. The permission context in the payload is the sender's, so it cannot be forwarded to anyone else without re-checking.

## 4. API key scopes, and why granular scopes do not work

From `plugins/chat/plugin.rb`, the chat plugin registers exactly one granular API scope:

- `chat -> create_message`, limited to the action `chat/api/channel_messages#create` with a `chat_channel_id` parameter

There is no granular scope for reading channels, reading history, reacting, editing, deleting, or opening DMs. A per-user key that needs to do more than post a message must therefore be a **global scope** key. A global scope single-user key can do anything that user can do on the forum, including reading all their private messages and changing their account. Storing eight of those, encrypted or not, is a meaningful liability, and storing thousands for a public deployment is worse.

## 5. Rate limits

From `config/discourse_defaults.conf`:

- `max_admin_api_reqs_per_minute = 60`
- `max_user_api_reqs_per_minute = 20`
- `max_user_api_reqs_per_day = 2880`
- `max_reqs_per_ip_per_minute = 200`
- `max_reqs_per_ip_per_10_seconds = 50`
- `max_reqs_per_ip_mode = block`
- `skip_per_ip_rate_limit_trust_level = 1`

Assessment: this is the finding that kills the external bridge design. A chat client is chatty by nature: channel lists, history pages, read receipts, sends. An API-key-mediated bridge funnels all of that through buckets measured in tens of requests per minute. Every request the bridge makes to Discourse also arrives from a single source IP, so the per-IP limits apply on top. The limits are raisable, but raising them to the level a chat client needs means substantially weakening the forum's own abuse protection.

## 6. DiscourseConnect provider

- `enable_discourse_connect_provider` default: false, not overridden, so currently off
- `discourse_connect_provider_secrets` default: empty
- Both are site settings, changeable in the admin UI at runtime. Neither requires a rebuild.

## 7. CORS

- `enable_cors = false` and `cors_origin = ''` in `discourse_defaults.conf`, set at container level via env
- A `cors_origins` site setting also exists (site_settings.yml line 3146) and is runtime editable

This means the enable flag needs one app.yml change and one rebuild, after which the list of permitted origins is editable from the admin UI with no further downtime.

## 8. Hosting an external bridge over HTTPS

Recorded because it applies to anyone attempting the external bridge approach, even though this project went another way.

The obvious plan is an outer web server on the host owning ports 80 and 443, with Discourse moved behind it on a socket. That is the documented approach for running other sites beside Discourse, and it requires a container rebuild. On a busy or memory constrained host with many plugins, that rebuild is the single riskiest operation involved, for the smallest gain.

A better option exists whenever a CDN such as Cloudflare already fronts the domain. Cloudflare proxies HTTPS on 443, 2053, 2083, 2087, 2096 and 8443, so the bridge can listen on a non-standard origin port while visitors still connect to standard 443 at the edge. The usual objection to a separate port, that corporate networks block non-standard ports, does not apply, because the odd port exists only between the CDN and the origin. A CDN origin certificate also removes the need for an HTTP-01 challenge on port 80, and therefore removes the renewal machinery entirely. Discourse is not touched at all: no container change, no rebuild, no downtime.


## 9. Corrections to the original brief

The installed source contradicts the brief in four places. Source wins.

1. The brief treats DM webhook coverage as an open question. It is settled: DMs do fire, provided no category filter is set. The real issue is not coverage but that one endpoint receives every DM on the forum.
2. The brief hopes granular API scopes may cover the chat routes. They do not. Only `create_message` exists. Anything beyond posting requires a global scope key.
3. The brief estimates admin API limits "on the order of 60 per minute" and asks whether single-user keys fall in the admin or user bucket. Both buckets are confirmed low, 60 and 20 respectively. Either is far below what a chat client needs.
4. The brief assumes a rebuild is needed to expose the bridge. Under Cloudflare it is not, as described in section 10.

## 10. The trust level gate

`chat_allowed_groups` defaults to `1|2|11`, meaning admins, moderators and trust level 1. `direct_message_enabled_groups` defaults to `11`, trust level 1 only.

New users register at trust level 0, and reach TL1 by reading topics and spending time on the forum. So on a default install a brand new account cannot use chat at all, and therefore cannot use anything built on top of chat.

Any project that promises "chat works the moment someone signs up" has to confront this. The options are to lower the gate to include trust level 0, which weakens a deliberate anti-spam measure, or to accept the gate and make the client explain the situation rather than fail. There is no third option, because the setting is what Discourse itself consults.

## 11. Recommendation

The external PHP bridge described in the brief is buildable, but the source says it would be fighting the platform at every layer: a global-scope key per user because granular scopes do not exist, a 60 per minute ceiling on a chat workload, a webhook feed that carries messages and nothing else, and a duplicate permission model that has to re-derive what Discourse already knows.

A Discourse plugin removes all four problems at once, because it runs inside Discourse: no API keys, no rate limit bucket, direct access to Guardian for permissions, and direct access to MessageBus for real time. It is also the distribution mechanism Rob originally wanted, a GitHub URL in app.yml.

Details, trade-offs and the cost of each are in the decision section of the message accompanying this report. The choice is Rob's and no code will be written until he makes it.

## 12. State of the machine after Phase 0

Unchanged. Nothing was installed, edited, restarted, or configured. No secrets are reproduced in this document.
