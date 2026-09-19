# Security

This document is written to be read before you add a website, not after something goes wrong.

## Reporting a vulnerability

Open a private security advisory on the GitHub repository, or email the maintainer. Please do not open a public issue for anything exploitable.

## The trade you are making

Adding a website to this plugin grants that website cross origin access to your forum **carrying your members' credentials**. This is not a side effect, it is how the widget works, and it is the single most important thing on this page.

The consequence, stated plainly: **if a website you have registered is compromised, an attacker who can run JavaScript on it can act as any of your members who visit it.** Not just in chat. Anything that member could do on the forum.

So:

- Only register websites you control.
- Registering a partner's or a client's site means accepting their security as your own.
- Keep the list short. Every entry is another site whose compromise reaches your forum.
- Remove sites you no longer use. The admin page does this and takes the origin out of `cors_origins` at the same time.

If that trade is not acceptable for a particular site, do not add it. There is no configuration that makes it safe, because the access is the feature.

## What the plugin does to limit the damage

These reduce the blast radius. They do not remove the trade above.

- **Origins are matched exactly.** No wildcards, no trailing slashes, no paths. `https` only, except for `localhost` during development.
- **Session tokens are bound to one site.** Presenting a valid token from a different registered site is refused, so one embedding site cannot borrow another's sessions.
- **Tokens are stored as SHA256 hashes.** The plain value is returned once and never written down, so a database leak does not hand out working sessions.
- **The login handshake never puts a credential in a URL.** The widget receives an id and a secret, and only the id goes into the popup's address bar. The token is minted when the widget claims it, presenting the secret, compared in constant time. Nothing usable is stored in the handshake table at any point.
- **Discourse decides every permission.** Every request runs through `Guardian`, the same object the forum uses for itself. The plugin never caches a permission answer and never decides independently that a visitor may see something. Channel ids arriving from a browser are checked on every request, and a channel you may not see returns the same answer as one that does not exist, so the endpoint cannot be used to discover private channels.
- **Attachments are restricted to their uploader.** A client cannot attach an upload id it did not create, which would otherwise let someone render another member's private attachment into a channel.
- **Message HTML is sanitized again on the way out.** Discourse already sanitizes what it stores. This is a second pass against a strict allow list, because the output crosses a trust boundary into a page we do not control. Scripts are removed with their text, event handler attributes are stripped, and `javascript:`, `data:` and protocol relative URLs are refused. It is rendered inside a Shadow DOM.
- **No cookies are used by the widget.** The session is a bearer token, so third party cookie blocking is irrelevant and CSRF does not apply to it.
- **Appearance values cannot carry CSS.** The accent colour is validated as an exact hex value and applied as a custom property rather than concatenated into a stylesheet, because CSS can read attribute values and make network requests.

## Things that are deliberately not done

- **The plugin does not edit `authorized_extensions`.** Voice messages need audio formats allowed, and the admin page says which are missing, but changing a forum wide upload policy is not a plugin's decision to make.
- **`X-Shared-Session-Key` is not used**, although it would make real time delivery work. It authenticates any request that carries it, not only MessageBus ones, so handing it to an embedding page would upgrade a cross site scripting hole there into full account takeover. Three second latency is the better trade. See `docs/decisions.md` record 0006.

## Who can chat

`chat_allowed_groups` is Discourse's setting and defaults to trust level 1. The plugin does not change it. If you lower it so that new signups can chat immediately, you are removing an anti spam measure, and a chat widget on a public marketing site is a more attractive spam target than a forum.

## What an attacker with forum admin access can do

Everything, as usual. Specifically to this plugin: register a website they control, and thereby gain the access described at the top of this page. There is no separate permission for it, because an administrator can already read and write anything on the forum. Treat the admin page as equivalent to the rest of the admin area.
