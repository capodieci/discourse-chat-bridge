# Contributing

## Two rules that earned their place

**Verify against the installed Discourse source, not memory or documentation.** This plugin depends on chat internals that are not public API. During development the source contradicted a reasonable assumption four separate times, and each time reading it settled the question in minutes. The container has the code:

```sh
docker exec app cat /var/www/discourse/plugins/chat/config/routes.rb
docker exec app grep -rn 'def can_chat?' /var/www/discourse/plugins/chat/lib/
```

**Drive anything user facing in a real browser before calling it done.** Every feature in this project shipped with at least one bug that only a browser found, including several where the code read correctly and the tests passed. A few examples, all real:

- Preferences saved perfectly and were never read back, because a key was `undefined` at load time.
- A voice message uploaded, sent, and rendered as an empty bubble, because chat keeps attachments outside the message HTML entirely.
- The Back button was hidden when a visitor followed only one channel, which made starting a direct message impossible.
- The sign in popup reported success in static HTML while its script never ran, blocked by a Content Security Policy.

None of those were visible from reading the code.

## Checking your work

```sh
# Pre-flight: constants resolve, routes point at real actions, error codes have translations.
docker exec app rails runner \
  /var/www/discourse/plugins/discourse-chat-bridge/tests/loadcheck.rb

# Self checks: sanitizer, origin validation, tokens, handshakes, appearance.
docker exec app rails runner \
  /var/www/discourse/plugins/discourse-chat-bridge/tests/checks.rb
```

Both are read only and safe against a production install. `checks.rb` writes inside a transaction that always rolls back, and one of its checks verifies the rollback happened.

Add a check when you fix a bug. The integration checks exist because 39 passing unit style checks did not notice that `/channels/list` returned a 500: they tested pure functions and had never handed the presenter a real Discourse object.

## Conventions

- Vanilla JavaScript in the widget. No build step, no bundler, no framework.
- The admin page is server rendered for the same reason: plugin JavaScript compiles into the application bundle at container build time, so an Ember page would need a full rebuild to appear and another for every change to it.
- Prepared statements only. Never build SQL by string concatenation.
- JSON in by POST, JSON out, except for the two endpoints that cannot be: the login popup is a browser navigation, and an upload has to arrive as multipart.
- Do not use the em dash character in documentation. Use commas, colons or periods.
- Explain why in comments, not what. A comment saying what the line does is noise; a comment saying why it is that way survives the next person wondering if they can simplify it.

## Testing against a real forum

Create throwaway accounts rather than using your own, delete them afterwards, and undo any change to a real site's configuration. If you register `http://localhost:8000` for testing, disable it and remove it from `cors_origins` when you are done. A test origin left in that list is a permanent grant.
