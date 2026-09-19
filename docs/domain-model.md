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

## Security notes

- Enabling CORS sets `Access-Control-Allow-Credentials: true` for listed origins. A cross site scripting hole on any listed site therefore becomes a path to that visitor's forum account. Keep the origin list short, and only list sites under our control.
- Message HTML arrives from Discourse as `cooked`. It is rendered inside a Shadow DOM so host page CSS cannot reach it and it cannot reach the host page. Outgoing text is sent as raw text, never HTML.
- Tokens are short lived and bound to one origin.
