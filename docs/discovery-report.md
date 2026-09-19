# Phase 0: Discovery Report

Date: 2026-09-19
Method: read-only inspection of the host and of the Discourse source inside the running container. No installs, no edits, no restarts. No Rails processes were started, to avoid memory pressure on a live forum.

---

## 1. Host

- OS: Ubuntu 24.04.5 LTS (Noble Numbat)
- CPU: 2 vCPU
- RAM: 2014 MB total, 403 MB available at time of inspection
- Swap: 2 GB file, 834 MB already in use
- Disk: 58 G total, 40 G available, 31 percent used
- Firewall: ufw active. Default deny incoming, allow outgoing. Open: 22/tcp (rate limited), 80/tcp, 443
- No web server on the host: no nginx, no Apache, no OpenLiteSpeed, no Caddy
- No PHP on the host, in any version

Assessment: disk is comfortable. Memory is the binding constraint. The box is swapping under normal load, before we add anything.

## 2. Discourse install

- Method: standard Docker install, `/var/discourse`, single container named `app`
- Container definition: `/var/discourse/containers/app.yml`
- Templates: postgres, redis, web, web.ratelimited, web.ssl, cloudflare
- Ports: the container binds host 80 and 443 directly through docker-proxy
- TLS: terminated inside the container by the web.ssl template (Let's Encrypt)
- CDN: Cloudflare proxying is active (orange cloud), and the cloudflare template is in use
- Version: `2026.8.0-latest.1`
- Container memory use: 969 MB, about 49 percent of host RAM
- Plugins installed: 44, including discourse-ai, discourse-chat-integration, discourse-reactions, discourse-presence
- Env keys present in app.yml: hostname, developer emails, notification email, SMTP settings, UNICORN_WORKERS. Values not reproduced here.

Assessment: a rebuild on this box will be slow and memory hungry. 44 plugins means asset precompilation is well above a stock install. This raises the cost of any plan that requires a rebuild.

## 3. Chat state

- `chat_enabled` default: true, and not overridden in the database, so chat is on
- Channels: 2 category channels, `Staff` (0 messages) and `General` (1 message)
- Users: 8 (excluding system accounts)
- Existing outgoing webhooks: none
- Existing API keys: 1, an admin key described as "bug management"

Important default, `chat_allowed_groups` is `1|2|11`, meaning admins, moderators, and trust level 1. `direct_message_enabled_groups` is `11`, trust level 1 only.

## 4. Chat API surface

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

## 5. Webhook coverage, and the gap

From `app/models/web_hook_event_type.rb`, the only chat event types that exist are:

- `chat_message_created` (1801)
- `chat_message_edited` (1802)
- `chat_message_trashed` (1803)
- `chat_message_restored` (1804)

There are no webhook events for reactions, typing, presence, read state, channel membership changes, channel creation, or thread creation. A webhook-driven design gets message text and nothing else.

Two further facts, both confirmed in source:

- Direct messages do fire webhooks. `Chat::OutgoingWebHookExtension` passes `category_id: nil` for DM channels, and `EmitWebHookEvent#category_webhook_invalid?` only rejects an event when the webhook has an explicit category filter set. With no category filter, DM events are delivered. This is better than expected, but it means a single webhook endpoint receives every private message between every pair of users on the forum, and the receiving service becomes responsible for not leaking them.
- The payload is serialized through `Guardian.new(user)` where `user` is the message author, not the recipient. The permission context in the payload is the sender's, so it cannot be forwarded to anyone else without re-checking.

## 6. API key scopes, and why granular scopes do not work

From `plugins/chat/plugin.rb`, the chat plugin registers exactly one granular API scope:

- `chat -> create_message`, limited to the action `chat/api/channel_messages#create` with a `chat_channel_id` parameter

There is no granular scope for reading channels, reading history, reacting, editing, deleting, or opening DMs. A per-user key that needs to do more than post a message must therefore be a **global scope** key. A global scope single-user key can do anything that user can do on the forum, including reading all their private messages and changing their account. Storing eight of those, encrypted or not, is a meaningful liability, and storing thousands for a public deployment is worse.

## 7. Rate limits

From `config/discourse_defaults.conf`:

- `max_admin_api_reqs_per_minute = 60`
- `max_user_api_reqs_per_minute = 20`
- `max_user_api_reqs_per_day = 2880`
- `max_reqs_per_ip_per_minute = 200`
- `max_reqs_per_ip_per_10_seconds = 50`
- `max_reqs_per_ip_mode = block`
- `skip_per_ip_rate_limit_trust_level = 1`

Assessment: this is the finding that kills the external bridge design. A chat client is chatty by nature: channel lists, history pages, read receipts, sends. An API-key-mediated bridge funnels all of that through buckets measured in tens of requests per minute. Every request the bridge makes to Discourse also arrives from a single source IP, so the per-IP limits apply on top. The limits are raisable, but raising them to the level a chat client needs means substantially weakening the forum's own abuse protection.

## 8. DiscourseConnect provider

- `enable_discourse_connect_provider` default: false, not overridden, so currently off
- `discourse_connect_provider_secrets` default: empty
- Both are site settings, changeable in the admin UI at runtime. Neither requires a rebuild.

## 9. CORS

- `enable_cors = false` and `cors_origin = ''` in `discourse_defaults.conf`, set at container level via env
- A `cors_origins` site setting also exists (site_settings.yml line 3146) and is runtime editable

This means the enable flag needs one app.yml change and one rebuild, after which the list of permitted origins is editable from the admin UI with no further downtime.

## 10. Hosting the bridge over HTTPS

The brief offered plan A (outer web server, Discourse moved behind a socket, needs a rebuild) and plan B (separate port with its own certificate, non-standard ports blocked on some networks, certificate issuance cannot use port 80). There is a better option available here specifically because Cloudflare is already in front.

Recommended, call it plan B-plus:

- Cloudflare proxies HTTPS on 443, 2053, 2083, 2087, 2096 and 8443 to an origin port of our choosing. Visitors therefore always connect to standard 443 at the edge. The non-standard port exists only between Cloudflare and this host, where no corporate firewall is in the way. The brief's objection to plan B does not apply under Cloudflare.
- The origin certificate can be a Cloudflare Origin Certificate, free and valid for 15 years. No Let's Encrypt, no HTTP-01 challenge, therefore no need for port 80 and no renewal machinery.
- `chat.zoobc.pro` is covered by Cloudflare Universal SSL, which includes first-level subdomains. The existing wildcard DNS means the record already resolves.
- ufw would allow the origin port from Cloudflare IP ranges only.
- Discourse is not touched at all. No app.yml change, no rebuild, zero downtime.

Plan A is not recommended on this host. Moving Discourse behind an outer proxy requires a rebuild, and with 44 plugins, 2 GB of RAM and a live forum, that is the single riskiest operation available to us for the smallest gain.

## 11. Corrections to the brief

The installed source contradicts the brief in four places. Source wins.

1. The brief treats DM webhook coverage as an open question. It is settled: DMs do fire, provided no category filter is set. The real issue is not coverage but that one endpoint receives every DM on the forum.
2. The brief hopes granular API scopes may cover the chat routes. They do not. Only `create_message` exists. Anything beyond posting requires a global scope key.
3. The brief estimates admin API limits "on the order of 60 per minute" and asks whether single-user keys fall in the admin or user bucket. Both buckets are confirmed low, 60 and 20 respectively. Either is far below what a chat client needs.
4. The brief assumes a rebuild is needed to expose the bridge. Under Cloudflare it is not, as described in section 10.

## 12. Requirement conflict found

Rob's stated requirement is that chat works for a user the moment they sign up. The installed defaults prevent this:

- `chat_allowed_groups` is `1|2|11`. New users register at trust level 0. Trust level 1 is earned by reading topics and spending time on the forum.
- `direct_message_enabled_groups` is `11`, the same constraint for DMs.

A new signup therefore cannot use chat at all until they earn TL1. This is independent of which architecture we choose, and it must be resolved by changing those two site settings to include trust level 0, or `everyone`. Both are runtime site settings and need no downtime. The trade-off is spam exposure: TL1 gating is a deliberate anti-spam measure, and lowering it on a public forum invites abuse. This needs a decision.

## 13. Recommendation

The external PHP bridge described in the brief is buildable, but the source says it would be fighting the platform at every layer: a global-scope key per user because granular scopes do not exist, a 60 per minute ceiling on a chat workload, a webhook feed that carries messages and nothing else, and a duplicate permission model that has to re-derive what Discourse already knows.

A Discourse plugin removes all four problems at once, because it runs inside Discourse: no API keys, no rate limit bucket, direct access to Guardian for permissions, and direct access to MessageBus for real time. It is also the distribution mechanism Rob originally wanted, a GitHub URL in app.yml.

Details, trade-offs and the cost of each are in the decision section of the message accompanying this report. The choice is Rob's and no code will be written until he makes it.

## 14. State of the machine after Phase 0

Unchanged. Nothing was installed, edited, restarted, or configured. No secrets are reproduced in this document.
