# Changelog

## Unreleased

First working version. Not yet tagged.

### Added

- Corner widget embedded with one script tag, rendered inside a Shadow DOM, fullscreen on phones.
- Sign in through the forum's own login, using a handshake the widget claims rather than `postMessage`, so it works for visitors who are not already signed in.
- Channel list with unread counts, message history, sending, and read receipts.
- Direct messages: people search through Discourse's own chat search, and conversations opened idempotently.
- Voice messages: recorded in the browser, uploaded as the visitor, played back inline, and rendered as a proper audio player in the forum's own chat.
- Administration page at `/chat-bridge/admin`: register websites, get their script tag, set accent colour, corner and panel title per site, toggle direct and voice messages, and pin a site to a single channel.
- Visitor settings: notification sound, light or dark, and muting a conversation.
- `tests/checks.rb`, 57 self checks, and `tests/loadcheck.rb`, a pre-flight for after a Discourse upgrade.

- Nine interface languages, chosen from the visitor's browser: English, Simplified and Traditional Chinese, Russian, Italian, Spanish, French, Japanese and Korean. A visitor can override it in the widget's settings, a page can with `data-lang` on the script tag, and an administrator can fix one per website. The sign in window follows the same language.
- The launcher button's background and icon colours can be set per website, apart from the accent. The admin page has colour pickers and a live preview.
- Text on the accent colour turns dark by itself when the accent is pale, so a light brand colour no longer means an unreadable header.
- The admin page adds websites through a form rather than two browser prompts, collapses each website to one line, and gains a filter once the list is long.

### Changed

- A website's appearance now reaches visitors before they sign in, through a new unauthenticated endpoint, `/chat-bridge/api/site/config`. Until now it arrived with the session, so the colours and corner an administrator chose were only ever seen by signed in visitors.
- The bubble is drawn once the appearance is known rather than immediately, so it never appears in the default colour and corner and then jumps. A returning visitor's browser remembers the appearance, so for them it is still immediate. A first time visitor waits one round trip, capped at two and a half seconds.
- `widget.strings.en.json` is now one of a family, `widget.strings.<code>.json`. The old URL still works.

### Notes for anyone reading the history

Several decisions in `docs/decisions.md` record things that were tried and rejected, with the reasoning. They are worth reading before assuming something was an oversight:

- Real time via MessageBus is not used, because a browser on another domain cannot authenticate to it without being handed a session equivalent credential.
- Voice and video calls are out of scope.
- The admin page is server rendered rather than an Ember page under Admin, Plugins.
- `widget.js` is served from a route rather than the plugin's public directory, because that directory is served with a one year immutable cache policy and a fix would never reach anyone.
