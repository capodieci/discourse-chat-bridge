# Draft announcement for meta.discourse.org

Not published. Rob's to edit, or discard.

---

## Chat Bridge: put your Discourse chat on your other websites

I run a small forum and three other websites, and I kept noticing the same thing. People were happy to talk in chat once they were on the forum, but nobody goes to a forum to ask a quick question. They ask it wherever they already are, or they do not ask it at all.

So I have built a plugin that puts the forum's chat on those other sites. One script tag, and a corner bubble appears. Visitors sign in with the forum account they already have, through the forum's own login screen, and talk to the same channels they would see on the forum. Messages they send arrive in the forum's chat like any other message, because they are.

It is a plugin rather than a separate service, and that turned out to matter more than I expected. I started by designing an external bridge that would talk to Discourse over the API, and then I read the source. The chat API exposes exactly one granular scope, so anything beyond posting a message needs a global key for every user. The rate limits are tens of requests a minute, which a chat client burns through without trying. And chat webhooks carry four message events and nothing else, so reactions, presence and read state simply are not there to forward. Every one of those problems disappears when the code runs inside Discourse and can ask Guardian a question directly.

What works today: channels, history, sending, direct messages with people search, and voice messages recorded in the browser. Each website gets its own accent colour, corner and panel title, so three sites can look like three different products rather than three copies of the same widget. Visitors get a notification sound they can turn off, a light or dark override, and the ability to mute a conversation, which writes to their real Discourse membership so it follows them back to the forum. Everything renders inside a Shadow DOM, because this runs on pages I do not control and neither side's CSS should be able to break the other.

What does not work, and I would rather say so here than have you find out: there are no voice or video calls, and delivery is not instant. Messages arrive in about three seconds while the panel is open. That second one deserves an explanation, because Discourse does publish chat events to MessageBus and it looks like it should just work. A browser on another domain cannot authenticate to the MessageBus endpoint: its CORS policy permits four request headers and none of them carries a bearer token. The one header that does work resolves to a user auth token and therefore authenticates any request that carries it, not only MessageBus ones, which would mean handing every embedding page a credential equivalent to a forum session. A cross site scripting hole on a marketing site would become full account takeover. Three seconds is the better trade, and there is a safer route to real time written up in the repository if someone wants to take it on.

There is one thing anybody considering this needs to understand before installing it. Registering a website grants that website cross origin access to your forum carrying your members' credentials. That is not a side effect, it is the mechanism. If a site you have registered is compromised, an attacker who can run JavaScript there can act as any member who visits it. Only register sites you control. The plugin says this on the admin page beside the field where you type the origin, rather than in a document nobody opens, and the security notes in the repository go through what the plugin does to limit the blast radius and what it deliberately does not do.

It is MIT licensed and the repository includes the discovery notes, the decision records with the reasoning behind the awkward choices, and two read only scripts for checking an install. One of those is worth running after every Discourse upgrade: the plugin leans on chat service objects that are not public API, and it will tell you in seconds if one has moved rather than leaving you to find out at the first request.

I would particularly like to hear from anyone who tries it on a forum that is not mine, and from anyone who knows a better answer to the MessageBus problem than the one I settled on.

Repository: https://github.com/capodieci/discourse-chat-bridge
