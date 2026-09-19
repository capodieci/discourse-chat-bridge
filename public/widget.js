/*
 * Discourse Chat Bridge widget.
 *
 * Embedded with one script tag:
 *   <script src="https://forum.example.com/plugins/discourse-chat-bridge/widget.js"
 *           data-site-key="..." defer></script>
 *
 * Design constraints, all deliberate:
 *
 * - Everything renders inside a Shadow DOM. The host page's CSS cannot reach in
 *   and break the widget, and the widget's CSS cannot leak out and break the
 *   host page. That matters because this runs on sites we do not control.
 * - No cookies are used anywhere. The session is a bearer token held in memory
 *   and sessionStorage, so third party cookie blocking is irrelevant and CSRF
 *   does not apply.
 * - The widget only ever talks to the bridge, never to Discourse directly, and
 *   never sees an API key.
 * - All user visible text comes from the STRINGS table so translation is a matter
 *   of adding a table, not editing code.
 */
(function () {
  "use strict";

  if (window.__discourseChatBridgeLoaded) return;
  window.__discourseChatBridgeLoaded = true;

  var SCRIPT = document.currentScript;
  if (!SCRIPT) return;

  var SITE_KEY = SCRIPT.getAttribute("data-site-key") || "";
  if (!SITE_KEY) {
    console.error("[chat-bridge] missing data-site-key on the script tag");
    return;
  }

  // The bridge is wherever this script was served from. Deriving it rather than
  // asking for it means one less thing for an integrator to get wrong.
  var BRIDGE = new URL(SCRIPT.src, window.location.href).origin;
  var API = BRIDGE + "/chat-bridge/api";
  var STORAGE_KEY = "dcb.token." + SITE_KEY;

  var STRINGS = {
    bubble_label: "Open chat",
    panel_title: "Community chat",
    close: "Close",
    back: "Back",
    sign_in: "Sign in to chat",
    sign_in_hint: "Use your forum account. A window will open.",
    signing_in: "Signing in",
    sign_out: "Sign out",
    popup_blocked: "Your browser blocked the sign in window. Allow popups for this site, then try again.",
    loading: "Loading",
    no_channels: "You are not following any channels yet. Join one on the forum and it will appear here.",
    no_messages: "No messages yet. Say something.",
    composer_placeholder: "Write a message",
    send: "Send",
    sending: "Sending",
    load_older: "Load older messages",
    edited: "edited",
    deleted: "This message was deleted.",
    reconnecting: "Reconnecting",
    offline: "You are offline. Messages will send when the connection returns.",
    error_generic: "Something went wrong. Please try again.",
    error_rate_limited: "You are sending messages too quickly. Wait a moment.",
    error_not_allowed_title: "Chat is not available for your account yet",
    error_not_allowed_body: "This forum only allows chat for members who have reached trust level 1. Spend a little time reading on the forum and it will unlock.",
    error_session_expired: "Your session expired. Please sign in again.",
    error_chat_disabled: "Chat is currently disabled on the forum."
  };

  function t(key) {
    return STRINGS[key] || key;
  }

  // English is inlined above so the widget is useful with one script tag and no
  // extra round trip. Another language is a JSON file with the same keys, named
  // on the script tag:
  //
  //   <script src="...widget.js" data-site-key="..." data-strings-url="/nl.json">
  //
  // Anything missing from that file falls back to the English string, so a
  // partial translation degrades key by key rather than breaking the interface.
  function loadStrings() {
    var url = SCRIPT.getAttribute("data-strings-url");
    if (!url) return Promise.resolve();

    return fetch(new URL(url, window.location.href).href, { credentials: "omit" })
      .then(function (res) {
        return res.ok ? res.json() : null;
      })
      .then(function (table) {
        if (!table) return;
        Object.keys(table).forEach(function (key) {
          if (typeof table[key] === "string") STRINGS[key] = table[key];
        });
      })
      .catch(function () {
        /* a missing or malformed table leaves English in place */
      });
  }

  /* ---------------------------------------------------------------- state */

  var state = {
    token: null,
    user: null,
    site: null,
    channels: [],
    activeChannelId: null,
    messages: [],
    open: false,
    loading: false,
    sending: false,
    error: null,
    unread: 0,
    view: "channels"
  };

  try {
    state.token = window.sessionStorage.getItem(STORAGE_KEY);
  } catch (e) {
    // Private browsing or blocked storage. The widget still works, the visitor
    // just signs in again on the next page load.
    state.token = null;
  }

  function saveToken(token) {
    state.token = token;
    try {
      if (token) window.sessionStorage.setItem(STORAGE_KEY, token);
      else window.sessionStorage.removeItem(STORAGE_KEY);
    } catch (e) {
      /* ignore, see above */
    }
  }

  /* ------------------------------------------------------------------ api */

  function api(path, body) {
    var headers = { "Content-Type": "application/json" };
    if (state.token) headers["Authorization"] = "Bearer " + state.token;

    return fetch(API + path, {
      method: "POST",
      mode: "cors",
      credentials: "omit",
      headers: headers,
      body: JSON.stringify(body || {})
    })
      .then(function (res) {
        return res.json().catch(function () {
          return { ok: false, error: { code: "bad_response" } };
        });
      })
      .then(function (json) {
        if (json && json.ok) return json.data;

        var code = (json && json.error && json.error.code) || "error_generic";
        if (code === "invalid_token" || code === "origin_mismatch") {
          saveToken(null);
          state.user = null;
        }
        var err = new Error(code);
        err.code = code;
        throw err;
      });
  }

  function errorMessage(code) {
    if (code === "rate_limited") return t("error_rate_limited");
    if (code === "invalid_token" || code === "origin_mismatch") return t("error_session_expired");
    if (code === "chat_disabled") return t("error_chat_disabled");
    return t("error_generic");
  }

  /* ----------------------------------------------------------------- auth */

  var authWindow = null;

  function signIn() {
    var nonce = String(Math.random()).slice(2) + String(Date.now());
    var url =
      BRIDGE +
      "/chat-bridge/auth/start?site_key=" +
      encodeURIComponent(SITE_KEY) +
      "&state=" +
      encodeURIComponent(nonce);

    var w = 460;
    var h = 640;
    var left = window.screenX + (window.outerWidth - w) / 2;
    var top = window.screenY + (window.outerHeight - h) / 2;

    authWindow = window.open(
      url,
      "discourse-chat-bridge-login",
      "width=" + w + ",height=" + h + ",left=" + left + ",top=" + top
    );

    if (!authWindow) {
      state.error = t("popup_blocked");
      render();
      return;
    }

    // The handshake page posts the token back. The listener checks the origin
    // because postMessage delivers to anyone who listens.
    var onMessage = function (event) {
      if (event.origin !== BRIDGE) return;
      var data = event.data;
      if (!data || data.type !== "chat-bridge-auth") return;
      if (data.state !== nonce) return;

      window.removeEventListener("message", onMessage);
      saveToken(data.token);
      state.user = data.user;
      state.error = null;
      loadSession();
    };

    window.addEventListener("message", onMessage);
  }

  function signOut() {
    var done = function () {
      saveToken(null);
      state.user = null;
      state.channels = [];
      state.messages = [];
      state.activeChannelId = null;
      transport.stop();
      render();
    };
    api("/session/logout").then(done, done);
  }

  /* ------------------------------------------------------------- loading */

  function loadSession() {
    if (!state.token) {
      render();
      return Promise.resolve();
    }
    state.loading = true;
    render();

    return api("/session/me")
      .then(function (data) {
        state.user = data.user;
        state.site = data.site;
        state.loading = false;
        if (!data.user.can_chat) {
          render();
          return;
        }
        transport.start(null);
        return loadChannels();
      })
      .catch(function (err) {
        state.loading = false;
        state.error = errorMessage(err.code);
        render();
      });
  }

  function loadChannels() {
    return api("/channels/list")
      .then(function (data) {
        state.channels = data.channels || [];
        state.unread = state.channels.reduce(function (sum, c) {
          return sum + (c.unread_count || 0);
        }, 0);

        if (!state.activeChannelId && state.channels.length) {
          return openChannel(state.channels[0].id);
        }
        render();
      })
      .catch(function (err) {
        state.error = errorMessage(err.code);
        render();
      });
  }

  function openChannel(channelId) {
    state.activeChannelId = channelId;
    state.view = "messages";
    state.messages = [];
    state.loading = true;
    render();

    return api("/messages/history", { channel_id: channelId, limit: 30 })
      .then(function (data) {
        state.loading = false;
        state.messages = data.messages || [];
        render();
        scrollToBottom();
        markRead();
        transport.start(channelId);
      })
      .catch(function (err) {
        state.loading = false;
        state.error = errorMessage(err.code);
        render();
      });
  }

  function loadOlder() {
    if (!state.messages.length) return;
    var oldest = state.messages[0].id;
    return api("/messages/history", {
      channel_id: state.activeChannelId,
      before_id: oldest,
      limit: 30
    }).then(function (data) {
      var older = (data.messages || []).filter(function (m) {
        return m.id < oldest;
      });
      state.messages = older.concat(state.messages);
      render();
    });
  }

  function markRead() {
    if (!state.activeChannelId) return;
    api("/channels/mark_read", { channel_id: state.activeChannelId }).catch(function () {
      /* a failed read receipt is not worth showing the visitor */
    });
  }

  function sendMessage(text) {
    if (!text.trim() || state.sending) return;
    state.sending = true;
    render();

    return api("/messages/send", {
      channel_id: state.activeChannelId,
      text: text,
      client_nonce: String(Date.now()) + String(Math.random()).slice(2)
    })
      .then(function (data) {
        state.sending = false;
        mergeMessages([data.message]);
        render();
        scrollToBottom();
      })
      .catch(function (err) {
        state.sending = false;
        state.error = errorMessage(err.code);
        render();
      });
  }

  // Messages can arrive from a send and from the transport at the same time, so
  // merging is by id rather than by appending.
  function mergeMessages(incoming) {
    var byId = {};
    state.messages.concat(incoming || []).forEach(function (m) {
      byId[m.id] = m;
    });
    state.messages = Object.keys(byId)
      .map(function (k) {
        return byId[k];
      })
      .sort(function (a, b) {
        return a.id - b.id;
      });
  }

  /* ------------------------------------------------------------ transport
   *
   * An object with start, stop, onEvents and onUnread, and nothing else, so the
   * mechanism underneath can be replaced without touching the rest of the file.
   *
   * It polls, and that is a considered choice rather than a shortcut. Discourse
   * publishes chat events to MessageBus, but a browser on another domain cannot
   * authenticate to /message-bus: its CORS policy allows only four request
   * headers, none of which carry a bearer token, and the query parameter route
   * into Discourse's auth is restricted to RSS and calendar endpoints. The one
   * mechanism that does work, X-Shared-Session-Key, hands the embedding page a
   * credential equivalent to a forum session, which is a worse trade than
   * polling. See docs/decisions.md record 0006.
   *
   * So this polls something deliberately tiny: two integers per channel, and it
   * only asks for messages when one of them moves.
   */

  var transport = (function () {
    var timer = null;
    var channelId = null;
    var handler = null;
    var unreadHandler = null;
    var lastSeenMessageId = null;
    var failures = 0;

    function interval() {
      // Backing off on repeated failures matters: if the forum is having a bad
      // time, a widget on several sites hammering it every three seconds makes
      // that worse rather than better.
      if (failures > 0) return Math.min(3000 * Math.pow(2, failures), 60000);
      if (document.hidden) return 30000;
      return state.open ? 3000 : 12000;
    }

    // Asks only whether anything changed. The answer is two integers per
    // channel, so this stays cheap enough to run on a short interval. Messages
    // are only fetched when one of those integers actually moved.
    function tick() {
      if (!state.token) return schedule();

      api("/channels/updates")
        .then(function (data) {
          failures = 0;
          var channels = data.channels || [];
          var unreadElsewhere = false;
          var activeMoved = false;

          channels.forEach(function (c) {
            var hasUnread = c.last_message_id && c.last_message_id > (c.last_read_message_id || 0);

            if (c.id === channelId) {
              if (c.last_message_id && c.last_message_id !== lastSeenMessageId) {
                activeMoved = true;
                lastSeenMessageId = c.last_message_id;
              }
            } else if (hasUnread) {
              unreadElsewhere = true;
            }
          });

          if (unreadHandler) unreadHandler(unreadElsewhere);
          if (!activeMoved || !channelId) return;

          return api("/messages/history", { channel_id: channelId, limit: 30 }).then(function (res) {
            var known = {};
            state.messages.forEach(function (m) {
              known[m.id] = true;
            });
            var fresh = (res.messages || []).filter(function (m) {
              return !known[m.id];
            });
            if (fresh.length && handler) handler(fresh);
          });
        })
        .catch(function () {
          failures = failures + 1;
        })
        .then(function () {
          schedule();
        });
    }

    function schedule() {
      clearTimeout(timer);
      timer = setTimeout(tick, interval());
    }

    return {
      start: function (id) {
        channelId = id || null;
        lastSeenMessageId = null;
        failures = 0;
        schedule();
      },
      stop: function () {
        clearTimeout(timer);
        timer = null;
        channelId = null;
      },
      onEvents: function (fn) {
        handler = fn;
      },
      onUnread: function (fn) {
        unreadHandler = fn;
      }
    };
  })();

  transport.onUnread(function (hasUnread) {
    // While the panel is shut the badge is a dot rather than a number, because
    // an exact count would cost a query per channel on every tick. The real
    // count arrives from /channels/list the moment the panel is opened.
    var next = hasUnread ? Math.max(state.unread, 1) : 0;
    if (next !== state.unread && !state.open) {
      state.unread = next;
      render();
    }
  });

  transport.onEvents(function (messages) {
    var atBottom = isAtBottom();
    mergeMessages(messages);
    if (!state.open) {
      state.unread += messages.length;
    }
    render();
    if (atBottom) scrollToBottom();
    if (state.open) markRead();
  });

  /* ------------------------------------------------------------------ ui */

  var host = document.createElement("div");
  host.setAttribute("data-discourse-chat-bridge", "");
  // A high z-index and fixed positioning on the host, so the widget sits above
  // the page without the page's stacking context being able to bury it.
  host.style.cssText = "position:fixed;z-index:2147483000;bottom:0;right:0;";
  var root = host.attachShadow({ mode: "open" });

  var style = document.createElement("style");
  style.textContent = [
    ":host{all:initial}",
    "*{box-sizing:border-box;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif}",
    ".wrap{position:fixed;bottom:16px;right:16px;display:flex;flex-direction:column;align-items:flex-end;gap:10px}",
    ".bubble{width:56px;height:56px;border-radius:50%;border:none;cursor:pointer;background:#0b6ecf;color:#fff;box-shadow:0 6px 20px rgba(0,0,0,.25);display:flex;align-items:center;justify-content:center;position:relative}",
    ".bubble:hover{background:#0a5fb3}",
    ".bubble svg{width:26px;height:26px;fill:currentColor}",
    ".badge{position:absolute;top:-2px;right:-2px;min-width:20px;height:20px;border-radius:10px;background:#d4351c;color:#fff;font-size:11px;font-weight:700;display:flex;align-items:center;justify-content:center;padding:0 5px}",
    ".panel{width:370px;max-width:calc(100vw - 32px);height:540px;max-height:calc(100vh - 110px);background:#fff;color:#1b1b1b;border-radius:12px;box-shadow:0 12px 40px rgba(0,0,0,.28);display:flex;flex-direction:column;overflow:hidden}",
    ".hd{display:flex;align-items:center;gap:8px;padding:12px 14px;background:#0b6ecf;color:#fff;flex:0 0 auto}",
    ".hd h2{margin:0;font-size:15px;font-weight:600;flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}",
    ".hd button{background:transparent;border:none;color:#fff;cursor:pointer;font-size:13px;padding:4px 6px;border-radius:5px}",
    ".hd button:hover{background:rgba(255,255,255,.18)}",
    ".body{flex:1 1 auto;overflow-y:auto;padding:12px}",
    ".ft{flex:0 0 auto;border-top:1px solid #e6e6e6;padding:8px;display:flex;gap:8px}",
    ".ft textarea{flex:1;resize:none;border:1px solid #d6d6d6;border-radius:8px;padding:8px 10px;font-size:14px;min-height:38px;max-height:120px;line-height:1.35;color:inherit;background:#fff}",
    ".ft textarea:focus{outline:2px solid #0b6ecf;outline-offset:-1px}",
    ".ft button{border:none;background:#0b6ecf;color:#fff;border-radius:8px;padding:0 14px;cursor:pointer;font-size:14px;font-weight:600}",
    ".ft button:disabled{background:#9bb9d8;cursor:default}",
    ".ch{display:block;width:100%;text-align:left;border:none;background:transparent;padding:10px;border-radius:8px;cursor:pointer;font-size:14px;display:flex;align-items:center;gap:8px}",
    ".ch:hover{background:#f1f5f9}",
    ".ch .n{flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}",
    ".ch .u{background:#d4351c;color:#fff;border-radius:9px;min-width:18px;height:18px;font-size:11px;display:flex;align-items:center;justify-content:center;padding:0 5px}",
    ".msg{display:flex;gap:8px;padding:6px 0}",
    ".msg img.av{width:32px;height:32px;border-radius:50%;flex:0 0 auto}",
    ".msg .c{flex:1;min-width:0}",
    ".msg .meta{font-size:12px;color:#666;margin-bottom:2px}",
    ".msg .meta b{color:#1b1b1b;font-weight:600}",
    ".msg .txt{font-size:14px;line-height:1.45;word-wrap:break-word;overflow-wrap:anywhere}",
    ".msg .txt p{margin:0 0 6px}",
    ".msg .txt p:last-child{margin:0}",
    ".msg .txt img.emoji{width:18px;height:18px;vertical-align:-3px}",
    ".msg .txt pre{background:#f4f4f4;padding:8px;border-radius:6px;overflow-x:auto}",
    ".msg .txt code{background:#f4f4f4;padding:1px 4px;border-radius:4px;font-family:ui-monospace,monospace;font-size:13px}",
    ".msg .txt blockquote{margin:0;padding-left:10px;border-left:3px solid #ddd;color:#555}",
    ".msg .txt a{color:#0b6ecf}",
    ".note{padding:16px;text-align:center;color:#555;font-size:14px;line-height:1.5}",
    ".note h3{margin:0 0 6px;font-size:15px;color:#1b1b1b}",
    ".err{background:#fdecea;color:#8b1a10;padding:8px 12px;font-size:13px}",
    ".btn{border:none;background:#0b6ecf;color:#fff;border-radius:8px;padding:9px 14px;cursor:pointer;font-size:14px;font-weight:600}",
    ".more{width:100%;border:1px solid #ddd;background:#fff;border-radius:8px;padding:6px;cursor:pointer;font-size:13px;color:#444;margin-bottom:8px}",
    // On a phone a 358px card wastes most of the screen and leaves the composer
    // cramped, so the panel takes the whole viewport instead and the bubble gets
    // out of the way. dvh rather than vh, because vh on mobile browsers measures
    // the viewport as if the address bar were hidden, which pushes the composer
    // under it.
    "@media (max-width: 480px){",
    ".wrap.open{inset:0;bottom:0;right:0;gap:0}",
    ".wrap.open .panel{width:100%;max-width:100%;height:100vh;height:100dvh;max-height:none;border-radius:0}",
    ".wrap.open .bubble{display:none}",
    ".wrap.open .hd{padding:14px;padding-top:max(14px,env(safe-area-inset-top))}",
    ".wrap.open .ft{padding-bottom:max(8px,env(safe-area-inset-bottom))}",
    ".wrap.open .hd button[data-act=close]{font-size:22px;padding:4px 10px}",
    "}",
    "@media (prefers-color-scheme: dark){",
    ".panel{background:#1f2124;color:#e8e8e8}",
    ".ft{border-top-color:#33363a}",
    ".ft textarea{background:#2a2d31;border-color:#3a3d42;color:#e8e8e8}",
    ".ch:hover{background:#2a2d31}",
    ".msg .meta b{color:#e8e8e8}",
    ".msg .txt pre,.msg .txt code{background:#2a2d31}",
    ".note{color:#b4b4b4}.note h3{color:#e8e8e8}",
    ".more{background:#2a2d31;border-color:#3a3d42;color:#ccc}",
    "}"
  ].join("");
  root.appendChild(style);

  var wrap = document.createElement("div");
  wrap.className = "wrap";
  root.appendChild(wrap);

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function isAtBottom() {
    var b = root.querySelector(".body");
    if (!b) return true;
    return b.scrollHeight - b.scrollTop - b.clientHeight < 40;
  }

  function scrollToBottom() {
    var b = root.querySelector(".body");
    if (b) b.scrollTop = b.scrollHeight;
  }

  function activeChannel() {
    for (var i = 0; i < state.channels.length; i++) {
      if (state.channels[i].id === state.activeChannelId) return state.channels[i];
    }
    return null;
  }

  function renderBubble() {
    var badge = state.unread > 0 ? '<span class="badge">' + (state.unread > 99 ? "99+" : state.unread) + "</span>" : "";
    return (
      '<button class="bubble" part="bubble" aria-label="' + esc(t("bubble_label")) + '">' +
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 2H4a2 2 0 0 0-2 2v18l4-4h14a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2z"/></svg>' +
      badge +
      "</button>"
    );
  }

  function renderBody() {
    if (!state.token) {
      return (
        '<div class="note"><h3>' + esc(t("sign_in")) + "</h3><p>" + esc(t("sign_in_hint")) + "</p>" +
        '<p><button class="btn" data-act="signin">' + esc(t("sign_in")) + "</button></p></div>"
      );
    }
    if (state.loading) {
      return '<div class="note">' + esc(t("loading")) + "</div>";
    }
    if (state.user && !state.user.can_chat) {
      return (
        '<div class="note"><h3>' + esc(t("error_not_allowed_title")) + "</h3><p>" +
        esc(t("error_not_allowed_body")) + "</p></div>"
      );
    }
    if (state.view === "channels" || !state.activeChannelId) {
      if (!state.channels.length) return '<div class="note">' + esc(t("no_channels")) + "</div>";
      return state.channels
        .map(function (c) {
          var u = c.unread_count > 0 ? '<span class="u">' + c.unread_count + "</span>" : "";
          return (
            '<button class="ch" data-channel="' + c.id + '">' +
            '<span class="n">' + esc(c.title) + "</span>" + u + "</button>"
          );
        })
        .join("");
    }
    if (!state.messages.length) return '<div class="note">' + esc(t("no_messages")) + "</div>";

    var more = state.messages.length >= 30 ? '<button class="more" data-act="older">' + esc(t("load_older")) + "</button>" : "";

    return (
      more +
      state.messages
        .map(function (m) {
          if (m.deleted) return '<div class="msg"><div class="c"><div class="txt"><em>' + esc(t("deleted")) + "</em></div></div></div>";
          var av = m.user && m.user.avatar_url ? '<img class="av" src="' + esc(m.user.avatar_url) + '" alt="">' : "";
          var when = m.created_at ? new Date(m.created_at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) : "";
          var ed = m.edited ? " (" + esc(t("edited")) + ")" : "";
          // m.html has already been sanitized server side by ChatBridge::Sanitizer
          // against a strict allow list, with all URLs made absolute. It is the
          // only place in this file where markup is inserted unescaped.
          return (
            '<div class="msg">' + av + '<div class="c">' +
            '<div class="meta"><b>' + esc(m.user && m.user.username) + "</b> " + esc(when) + ed + "</div>" +
            '<div class="txt">' + m.html + "</div></div></div>"
          );
        })
        .join("")
    );
  }

  function renderPanel() {
    var ch = activeChannel();
    var showBack = state.view === "messages" && state.channels.length > 1;
    var title = state.view === "messages" && ch ? ch.title : t("panel_title");
    var canCompose = state.token && state.user && state.user.can_chat && state.view === "messages" && state.activeChannelId;

    return (
      '<div class="panel" role="dialog" aria-label="' + esc(t("panel_title")) + '">' +
      '<div class="hd">' +
      (showBack ? '<button data-act="back">' + esc(t("back")) + "</button>" : "") +
      "<h2>" + esc(title) + "</h2>" +
      (state.token ? '<button data-act="signout">' + esc(t("sign_out")) + "</button>" : "") +
      '<button data-act="close" aria-label="' + esc(t("close")) + '">&times;</button>' +
      "</div>" +
      (state.error ? '<div class="err">' + esc(state.error) + "</div>" : "") +
      '<div class="body">' + renderBody() + "</div>" +
      (canCompose
        ? '<div class="ft"><textarea rows="1" placeholder="' + esc(t("composer_placeholder")) + '"></textarea>' +
          '<button data-act="send"' + (state.sending ? " disabled" : "") + ">" +
          esc(state.sending ? t("sending") : t("send")) + "</button></div>"
        : "") +
      "</div>"
    );
  }

  function render() {
    var scroll = null;
    var oldBody = root.querySelector(".body");
    if (oldBody) scroll = oldBody.scrollTop;

    var draft = "";
    var oldTa = root.querySelector(".ft textarea");
    if (oldTa) draft = oldTa.value;

    wrap.className = state.open ? "wrap open" : "wrap";
    wrap.innerHTML = (state.open ? renderPanel() : "") + renderBubble();

    var newBody = root.querySelector(".body");
    if (newBody && scroll !== null) newBody.scrollTop = scroll;

    var ta = root.querySelector(".ft textarea");
    if (ta && draft) ta.value = draft;
  }

  /* -------------------------------------------------------------- events */

  wrap.addEventListener("click", function (event) {
    var bubble = event.target.closest(".bubble");
    if (bubble) {
      state.open = !state.open;
      state.error = null;
      if (state.open) {
        state.unread = 0;
        if (state.token && !state.user) loadSession();
        else render();
        if (state.activeChannelId) markRead();
      } else {
        render();
      }
      return;
    }

    var chBtn = event.target.closest(".ch");
    if (chBtn) {
      openChannel(parseInt(chBtn.getAttribute("data-channel"), 10));
      return;
    }

    var actEl = event.target.closest("[data-act]");
    if (!actEl) return;
    var act = actEl.getAttribute("data-act");

    if (act === "close") {
      state.open = false;
      render();
    } else if (act === "signin") {
      signIn();
    } else if (act === "signout") {
      signOut();
    } else if (act === "back") {
      state.view = "channels";
      state.activeChannelId = null;
      transport.stop();
      render();
    } else if (act === "older") {
      loadOlder();
    } else if (act === "send") {
      var ta = root.querySelector(".ft textarea");
      if (ta) {
        var text = ta.value;
        ta.value = "";
        sendMessage(text);
      }
    }
  });

  // Enter sends, Shift+Enter makes a new line, which is what every chat client
  // does and therefore what people expect without being told.
  wrap.addEventListener("keydown", function (event) {
    if (!event.target.matches(".ft textarea")) return;
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      var text = event.target.value;
      event.target.value = "";
      sendMessage(text);
    }
  });

  document.addEventListener("visibilitychange", function () {
    if (!document.hidden && state.open && state.activeChannelId) markRead();
  });

  /* ---------------------------------------------------------------- boot */

  function boot() {
    document.body.appendChild(host);
    loadStrings().then(function () {
      render();
      if (state.token) loadSession();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
