# Decision records

Short records: context, decision, consequences.

## 0001: Hosting the bridge over HTTPS

- Date: 2026-09-19
- Status: withdrawn, superseded by record 0003
- Context: the Discourse container binds host ports 80 and 443 directly. There is no web server and no PHP on the host. Cloudflare proxying is already active on the domain. The brief offered plan A, an outer web server with Discourse moved behind a socket, requiring a rebuild, and plan B, a separate port, objecting that non-standard ports are blocked on some networks and that certificates cannot be issued over port 80.
- Decision: neither as written. Use Cloudflare to proxy `chat.zoobc.pro` on standard 443 at the edge to a non-standard origin port on this host, with a Cloudflare Origin Certificate on the origin.
- Consequences: visitors always use port 443, so the plan B objection does not apply. No Let's Encrypt and no renewal machinery, because an Origin Certificate lasts 15 years. Discourse is not touched: no app.yml change, no rebuild, no downtime. The origin port is firewalled to Cloudflare ranges only. The cost is a hard dependency on Cloudflare remaining in front of the domain.

## 0002: Plugin versus external bridge

- Date: 2026-09-19
- Status: accepted, approved by Rob
- Context: see sections 5, 6, 7 and 13 of `docs/discovery-report.md`. The installed source shows only one granular chat API scope, chat webhooks covering only four message events, and API rate limit buckets of 60 and 20 requests per minute.
- Decision: build a Discourse plugin in Ruby, installed from GitHub through `app.yml`. This supersedes the brief's rule 8, plugin-free, and its PHP 8.3 language rule, both with Rob's explicit approval.
- Consequences: no API keys are minted or stored, so the largest security liability in the original design disappears. No rate limit ceiling, because the plugin does not make HTTP calls to the forum. Permissions come from `Guardian` directly, so there is one source of truth instead of two. Real time comes from MessageBus instead of polling. The costs accepted: the plugin is coupled to Discourse internals and may break on forum upgrades, installation requires a rebuild here and for every adopter, and the code runs inside the forum process rather than isolated from it.

## 0003: No separate bridge hostname

- Date: 2026-09-19
- Status: accepted
- Context: `chat.zoobc.pro` was planned to host an external bridge. Rob pointed out that `zoobc.pro` already has chat natively, since it is the forum, so the widget is for the other properties.
- Decision: drop the separate hostname. The plugin serves `widget.js` and its API from `zoobc.pro` itself. Decision record 0001, the Cloudflare origin port plan, is withdrawn as unnecessary.
- Consequences: no new DNS record, no origin certificate, no new firewall port, no second web server, no PHP on the host. The widget loads from `https://zoobc.pro/chat-bridge/widget.js`. Target embedding origins are `https://zoobc.com`, `https://zoobc.foundation`, and later `https://zoobc.network` and `https://zoobc.net`.

## 0004: Trust level gate left as it is

- Date: 2026-09-19
- Status: accepted, decided by Rob
- Context: `chat_allowed_groups` defaults to trust level 1 and above, so a brand new signup cannot use chat. This conflicts with the brief's stated goal that chat works immediately on signup.
- Decision: keep trust level 1 for now. Do not weaken the forum's anti-spam posture to satisfy the requirement.
- Consequences: the "works the moment they sign up" requirement is consciously deferred, not met. New users must reach TL1 before the widget is useful to them. The widget must therefore handle the not-permitted case gracefully, with a clear explanation rather than an error. Revisit once there is something running to judge the spam trade-off against.

## 0005: CORS strategy

- Date: 2026-09-19
- Status: accepted
- Context: `config/initializers/008-rack-cors.rb` short circuits unless `GlobalSetting.enable_cors` is set, and `004-message_bus.rb` only honours external origins on the MessageBus endpoint when the same flag is set. A plugin can set its own response headers on its own routes, but it cannot make MessageBus accept an external origin.
- Decision: set `DISCOURSE_ENABLE_CORS: true` in `app.yml`, and manage the actual origin list through the `cors_origins` site setting, which is editable at runtime.
- Consequences: one rebuild is needed, and it is the same rebuild that installs the plugin, so the cost is paid once. After that, adding or removing an embedding site is an admin UI change with no downtime.
- Observed after enabling, on 2026-09-19. `Discourse::Cors` is middleware, so it intercepts `OPTIONS` preflights before they reach any controller. Two things follow. First, the plugin's own stricter headers, `Authorization, Content-Type` and no credentials, apply to real requests from a registered origin, which was verified. Second, a request from an unregistered origin still receives `Access-Control-Allow-Origin` set to the first entry of `cors_origins`, because that is the middleware's fallback. Browsers block it, since the value does not match the requesting origin, so this is not a hole. It does mean anyone probing can learn the first configured origin.
- The important consequence, now live: this setting is global, not scoped to the plugin. Every Discourse endpoint, not only the bridge, now accepts cross origin requests from the listed sites with `Access-Control-Allow-Credentials: true`. A cross site scripting hole on `zoobc.com` or `zoobc.foundation` is therefore a route into a visitor's forum account. Keep the list short and only list sites under our control.

## 0006: Polling instead of MessageBus, for now

- Date: 2026-09-19
- Status: accepted, with a recommended path out
- Context: decision 0002 chose a plugin partly because Discourse already publishes chat events to MessageBus, which would remove the need to poll. That turns out not to be reachable from a browser on another domain, and the reason is specific.

What the installed source and a live request both show:

- The MessageBus endpoint sets its own CORS headers in `config/initializers/004-message_bus.rb`, separate from the main `Discourse::Cors` middleware. A live `OPTIONS` to `/message-bus/…` from `https://zoobc.com` returns exactly `X-SILENCE-LOGGER, X-Shared-Session-Key, Dont-Chunk, Discourse-Present` as the allowed request headers. There is no `Authorization` and no `User-Api-Key`, so the browser will refuse to send either.
- Discourse can accept `user_api_key` as a query parameter rather than a header, which would sidestep that, but `api_parameter_allowed?` gates it behind `PARAMETER_API_PATTERNS`, and those cover only RSS feeds, an ICS bookmark feed and inbound admin email. `/message-bus` is not among them.
- `X-Shared-Session-Key` is allowed, and it does work. `Auth::DefaultCurrentUserProvider#current_user` looks the key up in Redis, resolves it to a `UserAuthToken`, and returns that user. Discourse issues such keys itself in `application_helper.rb`, but only when `long_polling_base_url` points at a different host, which is the same problem we have.

- Decision: poll a deliberately cheap endpoint, and do not use `X-Shared-Session-Key`.
- Reasoning: the shared session key is not scoped. It is checked inside `current_user`, so it authenticates any request that carries it, not merely MessageBus ones. Cross origin a browser can only send it to `/message-bus`, because no other endpoint allows the header, but CORS binds browsers and not attackers. Anyone who obtains that key can present it to any Discourse endpoint from a script or a terminal and act as that user. Today a cross site scripting hole on an embedding site yields a bridge token, which works only on `/chat-bridge/api` and only from its registered origin. Handing that same page a shared session key would upgrade the same hole into full forum account takeover. Real time delivery is not worth that.
- Consequences: messages arrive in about three seconds while the panel is open rather than instantly. The `/api/channels/updates` endpoint returns two integers per channel and nothing else, so a short interval stays cheap, and messages are fetched only when one of those integers moves. Failures back off exponentially to a minute. None of this touches Discourse's API rate limits, because the plugin reads the database directly.

### The way out, when it is wanted

Publish to a MessageBus channel whose name is itself the secret, for example `/chat-bridge/<32 random bytes>`, minted per widget session and delivered over the existing authenticated handshake. The widget subscribes anonymously, since an unguessable channel name needs no user identification, and the plugin republishes to it the chat events that session is allowed to see. That restores instant delivery, and the capability leaked by a compromised page is "read this one session's chat" rather than "be this user". It costs a `DiscourseEvent` hook and a fan out across active sessions, which is cheap at this scale. It is the right answer, it is simply more than a transport swap, and it should be a decision of its own rather than something slipped in here.
