# Announcement for meta.discourse.org

Ready to post. Category: **Customization, Plugin subcategory**. Titles there carry no prefix, so the plugin name alone is the convention.

Suggested tags: `chat`, `embed`, `cors`.

---

## Title

**Chat Bridge**

Alternatives, if a more descriptive title suits the category better:

- Chat Bridge: put your forum chat on your other websites
- Chat Bridge: embed Discourse chat anywhere

---

## Post body

I run a small forum and three other websites, and I kept noticing the same thing. People were happy to talk in chat once they were on the forum, but nobody goes to a forum to ask a quick question. They ask it wherever they already are, or they do not ask it at all.

So I have built a plugin that puts the forum's chat on those other sites. One script tag, and a corner bubble appears. Visitors sign in with the forum account they already have, through the forum's own login screen, and talk in the same channels they would see on the forum. Messages they send arrive in the forum's chat like any other message, because they are.

**Repository:** https://github.com/capodieci/discourse-chat-bridge (MIT)

```html
<script src="https://forum.example.com/chat-bridge/widget.js"
        data-site-key="your-site-key" defer></script>
```

### Why it is a plugin rather than a service

I started by designing an external bridge that would talk to Discourse over the API, and then I read the source. That changed the design completely, and the reasons may be useful to anyone considering something similar.

The chat plugin registers exactly one granular API scope, `create_message`. Anything beyond posting, so reading channels, fetching history, opening a direct message, needs a global scope key, and a global scope key for every user is a large pile of credentials to hold. The default rate limits are 60 requests a minute on the admin bucket and 20 on the user bucket, which a chat client burns through without trying. And chat webhooks carry four message events and nothing else, so reactions, presence and read state are simply not available to forward.

Every one of those problems disappears when the code runs inside Discourse and can ask `Guardian` a question directly. No keys, no rate limit ceiling, and one source of truth rather than a cache that can disagree with the forum.

### What works

Channels, message history, sending, direct messages with people search, and voice messages recorded in the browser. Voice messages appear as a normal audio player to members reading the forum's own chat, not as a download link, which took some care to get right.

Each website gets its own accent colour, corner and panel title, so three sites can look like three different products rather than three copies of the same widget. Visitors get a notification sound they can turn off, a light or dark override, and the ability to mute a conversation, which writes to their real Discourse membership so it follows them back to the forum.

Everything renders inside a Shadow DOM. This runs on pages I do not control, and neither side's CSS should be able to break the other.

### What does not work, and why

There are no voice or video calls. That is deliberate and out of scope.

Delivery is not instant. Messages arrive in about three seconds while the panel is open. This deserves an explanation, because Discourse does publish chat events to MessageBus and it looks like it should just work.

A browser on another domain cannot authenticate to the MessageBus endpoint. Its CORS policy permits four request headers and none of them carries a bearer token, and the query parameter route into Discourse's authentication is restricted to RSS and calendar endpoints. The one header that does work, `X-Shared-Session-Key`, resolves to a `UserAuthToken` and therefore authenticates any request carrying it, not only MessageBus ones. Handing that to an embedding page would turn a cross site scripting hole on a marketing site into full forum account takeover. Three seconds is the better trade.

There is a safer route to real time written up in the repository, using a MessageBus channel whose unguessable name is itself the capability, scoped to one widget session rather than to the user's account. I have not built it. If someone wants to, the reasoning is in `docs/decisions.md`.

### The thing to understand before installing

Registering a website grants that website cross origin access to your forum **carrying your members' credentials**. That is not a side effect, it is the mechanism.

If a site you have registered is compromised, an attacker who can run JavaScript there can act as any member who visits it. Not just in chat. Anything that member could do on the forum.

So only register sites you control. Registering a partner's or a client's site means accepting their security as your own. The plugin says this on the admin page beside the field where you type the origin, rather than in a document nobody opens, and `SECURITY.md` goes through what the plugin does to limit the blast radius and what it deliberately does not do.

### Installing

Add it to your container definition and rebuild once:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone --depth 1 https://github.com/capodieci/discourse-chat-bridge.git
env:
  DISCOURSE_ENABLE_CORS: true
```

Then turn on `chat_bridge_enabled` in Admin, Settings, and everything else lives on one page at `/chat-bridge/admin`, where you add a website and it hands you the script tag.

Two notes that will save somebody an afternoon. Voice messages need audio formats in `authorized_extensions`, which by default contains none at all, so the admin page tells you exactly which are missing. And `chat_allowed_groups` defaults to trust level 1, so brand new accounts cannot chat until they earn it, which the widget explains rather than failing silently.

### Compatibility

Tested against Discourse `2026.9.0` and `2026.8.0`, and in production use on one forum.

This leans on chat service objects that are not public API, so a Discourse release can move them. The repository includes a read only pre-flight script that asserts every one of them still exists and reports in seconds rather than at the first request. Worth running after an upgrade.

### What I would like

Someone to install it on a forum that is not mine and tell me what broke. Everything so far is verified against one Discourse, on one server, by one person, and that is the weakest thing about it.

I would also like to hear from anyone who knows a better answer to the MessageBus problem than the one I settled on.
