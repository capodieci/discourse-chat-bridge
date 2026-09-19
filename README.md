# Discourse Chat Bridge

Put your Discourse chat on any website. One script tag, and visitors sign in with their existing forum account and talk to the whole community in real time.

```html
<script src="https://forum.example.com/plugins/discourse-chat-bridge/widget.js"
        data-site-key="your-site-key" defer></script>
```

## Status

Early development. Phase 1 of 6: the plugin skeleton, data model, and login handshake are written. There is no widget yet, so nothing is user visible. See `PROGRESS.md`.

## How it works

This is a Discourse plugin, not a separate service. That choice came from reading the installed Discourse source rather than the documentation, and it matters:

- **No API keys.** The plugin runs inside Discourse and acts through `Guardian`, the same object the forum uses to answer its own permission questions. Nothing is minted, encrypted, stored or rotated.
- **No rate limit ceiling.** An external bridge would funnel every visitor through Discourse's API buckets, which default to 60 requests per minute. A plugin makes no HTTP calls to the forum at all.
- **One source of truth.** Channels, messages, reactions and memberships stay in Discourse. Nothing is cached and re-derived, so nothing can disagree.
- **Real time for free.** Chat already publishes to MessageBus, which is long polling. There is no polling interval to tune.

The full reasoning, including what the alternative would have cost, is in `docs/discovery-report.md`.

## What the visitor sees

The widget opens a popup on the forum. Because that popup is a first party window, it can see the visitor's ordinary forum session, so an already signed in user is recognised immediately and everyone else gets the normal forum login, including any social logins already configured. A short lived bearer token comes back by `postMessage`, targeted at the embedding site's exact registered origin. No cookies cross domains, so third party cookie blocking is irrelevant.

## Installing

Add the plugin to your container definition:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/capodieci/discourse-chat-bridge.git
```

Enable cross origin requests in the same file, which MessageBus requires in order to accept an external origin:

```yaml
env:
  DISCOURSE_ENABLE_CORS: true
```

Then rebuild, once:

```sh
cd /var/discourse && ./launcher rebuild app
```

After the rebuild, turn on `chat_bridge_enabled` in Admin, Settings.

Then register a website and get its script tag. This also adds the origin to the `cors_origins` site setting for you, because a registered site whose origin is missing from that list fails silently in the browser:

```sh
cd /var/discourse && ./launcher enter app
rake chat_bridge:site:add[Marketing,https://example.com]
```

## Administration

```sh
rake chat_bridge:site:list                  # every registered site and its active sessions
rake chat_bridge:site:add[Name,https://...] # register a site, prints the script tag
rake chat_bridge:site:disable[site_key]     # stop a site and revoke its sessions
rake chat_bridge:site:enable[site_key]      # turn it back on
rake chat_bridge:user:revoke[username]      # revoke one user's widget sessions
rake chat_bridge:prune                      # delete expired tokens and old nonces
```

## Security notes

- Origins are matched exactly. No wildcards, no trailing slashes, https only except for localhost.
- A session token is bound to the site it was issued for. Presenting it from a different registered site is rejected.
- Tokens are stored as SHA256 hashes. The plain value is returned once and never written down.
- `DISCOURSE_ENABLE_CORS` makes Discourse send `Access-Control-Allow-Credentials: true` to listed origins. A cross site scripting hole on a listed site therefore becomes a route into a visitor's forum account. Keep `cors_origins` short and list only sites you control.
- Discourse decides who may chat. On a default install that is trust level 1 and above, so brand new accounts are refused until they earn it. That is the forum's policy and the widget reports it plainly.

## Requirements

- Discourse with the bundled chat plugin enabled
- Tested against Discourse `2026.8.0`

## License

MIT. See `LICENSE`.

## Running the self checks

```sh
docker exec app rails runner \
  /var/www/discourse/plugins/discourse-chat-bridge/tests/checks.rb
```

39 checks covering the HTML sanitizer, origin validation, token hashing and revocation, and single use login nonces. Safe to run against a production install: everything that writes happens inside a transaction that is always rolled back, and one of the checks verifies that.

## Trying it from another origin

`demo/index.html` is a plain page that reports whether every cross origin mechanism works. Serve it from anywhere that is not the forum:

```sh
cd demo && python3 -m http.server 8000
rake chat_bridge:site:add[Local demo,http://localhost:8000]
```

Plain `http` is accepted for `localhost` only. Every other origin must be `https`.
