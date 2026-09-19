# Domain model

Architecture: a Discourse plugin. Decided 2026-09-19, see `docs/decisions.md` record 0002.

## What the plugin decision deletes

The brief modeled twelve tables for an external bridge. Running inside Discourse removes most of them, because Discourse already owns that data and we can read it directly:

- `user_keys` and `key_requests`: gone. No API keys are minted at all. The plugin acts as the current user through `Guardian`, the same object the forum itself uses.
- `messages`, `channels`, `reactions`, `memberships_cache`: gone. These are `Chat::Message`, `Chat::Channel`, `Chat::MessageReaction` and `Chat::UserChatChannelMembership` already. Caching them again would only create a second source of truth that can disagree with the first.
- `events`, `webhook_log`: gone. Real time comes from MessageBus, which the chat plugin already publishes to. No webhook receiver, no event log, no polling loop.
- `rate_limits`: gone. Discourse has `RateLimiter`, and the plugin's endpoints sit behind the same protections as the rest of the forum.

Three tables remain, because they describe something Discourse genuinely does not know about: which external websites are allowed to embed the chat, and who is currently holding a widget session.

## Tables

### `chat_bridge_sites`

One row per website permitted to embed the widget.

- `id`: integer, primary key
- `site_key`: string, unique, the public identifier that appears in the script tag
- `origin`: string, unique, exact origin including scheme, for example `https://zoobc.com`. Never a wildcard.
- `name`: string, for the admin UI
- `allowed_channel_ids`: integer array, nullable. Null means every channel the user can already see. A value restricts the widget to a subset.
- `theme`: JSON, per site appearance
- `enabled`: boolean, default true
- `created_at`, `updated_at`

### `chat_bridge_tokens`

One row per active widget session. This is the bearer token, not a Discourse session.

- `id`: integer, primary key
- `token_hash`: string, unique, SHA256 of a 32 byte random token. The plain token is returned once and never stored.
- `site_id`: integer, foreign key to `chat_bridge_sites`
- `user_id`: integer, foreign key to `users`
- `expires_at`: datetime
- `last_seen_at`: datetime
- `revoked_at`: datetime, nullable
- `created_at`

A token is valid only for the site it was issued to. A token presented from a different origin is rejected even if it is otherwise valid.

### `chat_bridge_auth_nonces`

Single use values protecting the login popup handshake.

- `nonce`: string, primary key
- `site_id`: integer, foreign key
- `state`: string, echoed back to the widget to bind the popup to the request that opened it
- `created_at`: datetime
- `used_at`: datetime, nullable

Expire after five minutes. Deleted on use.

## Login flow

Because the widget is served from the forum and the popup opens on the forum, the popup is a first party context and can read the user's existing forum session directly. DiscourseConnect provider is therefore not needed, and neither is a provider secret.

1. Widget on `zoobc.com` opens a popup to `https://zoobc.pro/chat-bridge/auth/start`, carrying the site key and a random state value.
2. The plugin looks up the site by key, checks the request origin matches the registered origin, and stores a nonce.
3. If `current_user` is present, go to step 5. If not, redirect to the normal forum login with a return path back to this endpoint. The user sees the ordinary forum login, including any social logins already configured.
4. After login the user returns to step 3 with a session.
5. The plugin mints a token, stores its hash, and returns a minimal HTML page that calls `window.opener.postMessage` targeting the exact registered origin, never `*`, then closes the popup.
6. The widget holds the token in memory and `sessionStorage` and sends it as `Authorization: Bearer` on every request.

No cookies cross domains, so third party cookie blocking is irrelevant and CSRF does not apply to the widget's own calls.

Fallback when popups are blocked: full page redirect, with the return URL validated against the registered origin.

## Real time

The chat plugin already publishes message events to MessageBus. The widget subscribes to the same channels the forum's own chat client uses, through `/message-bus`, which is long polling and therefore delivers in near real time without a polling interval.

This requires `DISCOURSE_ENABLE_CORS` to be true at container level, because `config/initializers/004-message_bus.rb` only honours external origins when that flag is set. The origin list itself is the `cors_origins` site setting, editable at runtime.

The widget talks to a `Transport` object with `start`, `stop`, and `onEvents`, so MessageBus can be swapped for something else later without touching the rest of the widget.

## Permissions

Discourse remains the only authority. Every plugin endpoint runs `Guardian.new(current_user_from_token)` and asks the same questions the forum asks itself. The plugin never decides independently that a user may see something, and never caches a permission answer. Channel ids arriving from the client are always checked, never trusted.

## Direct messages

Starting a conversation with a named person needs two things Discourse already
provides, so nothing new is stored.

- Finding people: `Chat::SearchChatable`, the same service the forum's own chat
  composer uses. It is called with the visitor's guardian, so the results are
  the people that visitor is allowed to see and no one else. The bridge never
  queries the user table directly.
- Opening the conversation: `Chat::CreateDirectMessageChannel`, called with
  `target_usernames` and `upsert: true`, so asking twice returns the existing
  conversation rather than creating a second one.

Two constraints inherited from the forum, not invented here:

- `direct_message_enabled_groups` defaults to trust level 1, the same gate as
  chat itself. Someone who cannot chat cannot start a DM either, and the widget
  reports that in plain words rather than failing.
- `chat_max_direct_message_users` caps how many people one conversation can
  hold, currently 20. The service enforces it; the bridge surfaces the refusal.

A site's `allowed_channel_ids`, when set, restricts which channels the widget
shows. A DM channel is created on demand and cannot be known in advance, so a
site with a restricted channel list does not get direct messages. That is the
safe reading of a deliberately narrowed configuration: a site pinned to one
support channel should not become a way to message the whole membership.

## Appearance

Per site, stored in the `theme` JSON column that already exists on
`chat_bridge_sites` and is already delivered to the widget by
`/api/session/me`. Three fields, deliberately few:

- `accent`: a hex colour, used for the bubble, the panel header and the send
  button. Validated as `#rgb` or `#rrggbb` and nothing else, because this value
  is interpolated into a stylesheet inside the Shadow DOM and anything less
  strict is a CSS injection.
- `position`: `bottom-right` or `bottom-left`. An enum, not free text.
- `launcher_label`: the heading shown on the panel. Plain text, escaped like
  every other string the widget renders.

Anything not set falls back to the widget's defaults, so a site with no theme
row behaves exactly as today.

Editing happens in a staff only admin page under Admin, Plugins. That page talks
to endpoints that are separate from the widget API and guarded by Discourse's
own staff check, never by a bridge token. The widget API is for visitors on
other websites; administration is a forum concern and stays inside the forum.

## Security notes

- Enabling CORS sets `Access-Control-Allow-Credentials: true` for listed origins. A cross site scripting hole on any listed site therefore becomes a path to that visitor's forum account. Keep the origin list short, and only list sites under our control.
- Message HTML arrives from Discourse as `cooked`. It is rendered inside a Shadow DOM so host page CSS cannot reach it and it cannot reach the host page. Outgoing text is sent as raw text, never HTML.
- Tokens are short lived and bound to one origin.
