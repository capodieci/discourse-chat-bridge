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

## 0007: Widget caching, and which Cloudflare zone governs it

- Date: 2026-09-19
- Status: accepted, with one setting left deliberately unchanged
- Context: `widget.js` was originally served from the plugin's `public` directory, which Discourse serves with `Cache-Control: public, max-age=31536000, immutable`. That is correct for fingerprinted asset filenames and wrong for a file whose URL has to stay stable in other people's HTML. It was observed live: Cloudflare returned `cf-cache-status: HIT` for a widget that had been fixed, and the embedding site kept running the broken one.
- Decision: serve the widget from a controller route, `/chat-bridge/widget.js`, with `max-age=300`, `must-revalidate` and an ETag. Do not use the `public` directory for anything whose URL is part of the integration contract.
- Consequences: integrators keep one unchanging script tag, caches still work, and a fix reaches browsers in minutes rather than never.

### Which zone matters

Only the forum's. The widget is served from the forum's hostname, so the forum's CDN zone decides how it is cached. The embedding sites' own CDN settings never see that request, because for them it is a third party script on another host.

### The setting left alone

Cloudflare's Browser Cache TTL on the forum zone rewrites the origin's `max-age=300` to `14400`, four hours. Left as it is on purpose. The catastrophic case, a year with `immutable`, is gone. What remains only means a browser that already holds the widget keeps it for an afternoon before checking again, which breaks nothing. It is worth changing to "Respect Existing Headers", ideally through a cache rule scoped to `/chat-bridge/*` rather than zone wide, on the day a bad release needs recalling quickly. That day is not now.

## 0008: zoobc.net becomes its own origin later

- Date: 2026-09-19
- Status: noted, no action yet
- Context: `zoobc.net` currently redirects to `zoobc.com`, so a visitor ends up on the `zoobc.com` origin and is already covered by that site's registration. Rob expects it to become its own server in a couple of months, at which point the redirect goes away.
- Decision: register nothing now. A registration for an origin that never sends a request is one more entry widening the CORS allow list for no benefit.
- Consequences: when it becomes its own server it needs one command, `rake chat_bridge:site:add[Net,https://zoobc.net]`, which prints the script tag and adds the origin to `cors_origins` in the same step. No downtime, no rebuild. Worth re-reading the security note in record 0005 at that point, since every added origin is another site whose compromise reaches forum accounts.

## 0009: Group calls are out of scope

- Date: 2026-09-19
- Status: accepted, decided by Rob
- Context: the original brief ended with self hosted LiveKit plus TURN for group voice rooms. That means every adopting forum runs a second service, which is a large step away from this project's promise of one script tag.
- Decision: no group calls. Rob has that need on a different project and will solve it there.
- Consequences: no SFU, no LiveKit, no new long lived process, and no new firewall ports for media forwarding. One to one calls remain in scope because they can be peer to peer and need no server side media at all.

## 0010: One to one calls, and what they honestly cost

- Date: 2026-09-19
- Status: planned
- Context: Rob wants one to one voice calls provided they install simply and can be switched off by the forum admin.
- Decision: peer to peer WebRTC with public STUN for discovery. No SFU. Optional TURN, configured by the admin, for the networks that refuse direct connections. Off by default, with a global site setting and a per site toggle.
- Consequences, stated plainly rather than discovered later:
  - **Some calls will fail without TURN.** A minority of networks, symmetric NAT and some corporate firewalls, cannot establish a direct peer connection. Without a relay those calls do not connect. That is not a bug to be fixed in the widget, it is the price of not running a relay. The admin page should say so where TURN is configured, and the widget should fail with a clear explanation rather than a spinner.
  - **Signalling needs to be faster than the chat transport.** Exchanging an offer and an answer over a three second poll makes a call take ten seconds to start, which reads as broken. Call setup therefore polls its own endpoint at a much shorter interval, and only while a call is being set up, so the cost is bounded to the seconds around a call rather than being a permanent load.
  - This is the first feature where the polling transport is genuinely a constraint rather than an inconvenience, so record 0006's capability scoped MessageBus channel becomes worth revisiting if call setup feels slow.

## 0011: Voice messages need a site setting the admin must change

- Date: 2026-09-19
- Status: planned
- Context: the forum's `authorized_extensions` currently contains no audio format at all. Chrome records WebM Opus and Safari records MP4 AAC, so on this forum today a voice message would fail on Chrome and succeed on Safari by accident.
- Decision: the plugin does not silently edit `authorized_extensions`. It detects the gap, and the admin page states exactly which extensions are missing and what to add.
- Consequences: one extra step at install time, and an obvious diagnosis instead of a feature that half works depending on the browser. Editing a forum wide upload policy without being asked is not a plugin's decision to make.
