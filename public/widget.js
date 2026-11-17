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
 * - The interface follows the visitor's browser language. English is inlined,
 *   every other language is a JSON file fetched only by the visitors who need it.
 * - This file stays plain ASCII. It is loaded by pages we do not control, some of
 *   which declare an unusual charset, so anything outside ASCII is written as a
 *   \u escape rather than trusted to survive the trip.
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

  // The English table. It is the source of truth for which keys exist, and the
  // fallback for any key a translation is missing.
  var EN = {
    bubble_label: "Open chat",
    panel_title: "Community chat",
    close: "Close",
    back: "Back",
    sign_in: "Sign in to chat",
    sign_in_hint: "Use your forum account. A window will open.",
    signing_in: "Signing in",
    signing_in_hint: "Finish signing in using the window that opened. This panel updates by itself.",
    sign_out: "Sign out",
    popup_blocked: "Your browser blocked the sign in window. Allow popups for this site, then try again.",
    loading: "Loading",
    no_channels: "You are not following any channels yet. Join one on the forum and it will appear here.",
    no_messages: "No messages yet. Say something.",
    composer_placeholder: "Write a message",
    send: "Send",
    sending: "Sending",
    load_older: "Load older messages",
    new_message: "New message",
    search_people: "Search people",
    search_placeholder: "Type a name",
    searching: "Searching",
    no_people: "No one found by that name.",
    dm_start: "Message",
    record: "Record a voice message",
    recording: "Recording",
    stop_send: "Stop and send",
    cancel: "Cancel",
    settings: "Settings",
    sound: "Notification sound",
    appearance: "Appearance",
    appearance_system: "Follow my system",
    appearance_light: "Always light",
    appearance_dark: "Always dark",
    language: "Language",
    language_auto: "Follow my browser",
    mute_channel: "Mute this conversation",
    muted: "Muted",
    done: "Done",
    mic_denied: "Microphone access was refused. Allow it in your browser settings to send voice messages.",
    mic_unavailable: "This browser cannot record audio.",
    uploading: "Sending voice message",
    voice_too_long: "That recording reached the maximum length and was sent.",
    error_dm_not_available: "Direct messages are not available from this website.",
    error_dm_refused: "That conversation could not be started. The person may not accept messages.",
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

  // What is on screen right now: English, overlaid with the active language,
  // overlaid with the integrator's own table if they supplied one.
  var STRINGS = EN;

  function t(key) {
    return STRINGS[key] || EN[key] || key;
  }

  /* -------------------------------------------------------------- language
   *
   * The languages this widget ships, each named in its own language so a
   * visitor can find theirs in the list whatever the interface is currently
   * showing. Every code except "en" has a file next to this script,
   * widget.strings.<code>.json, with the same keys as the EN table above.
   *
   * To add a language: add its file, add it here, and add it to
   * ChatBridge::Site::LOCALE_NAMES on the server. tests/loadcheck.rb fails if
   * the three disagree, or if a file is missing a key.
   */
  var LOCALES = ["en", "zh-CN", "zh-TW", "ru", "it", "es", "fr", "ja", "ko"];

  var LOCALE_NAMES = {
    "en": "English",
    "zh-CN": "\u7b80\u4f53\u4e2d\u6587",
    "zh-TW": "\u7e41\u9ad4\u4e2d\u6587",
    "ru": "\u0420\u0443\u0441\u0441\u043a\u0438\u0439",
    "it": "Italiano",
    "es": "Espa\u00f1ol",
    "fr": "Fran\u00e7ais",
    "ja": "\u65e5\u672c\u8a9e",
    "ko": "\ud55c\uad6d\uc5b4"
  };

  var activeLocale = "en";
  var wantedLocale = "en";
  var localeTables = {};
  var customTable = null;

  // Maps whatever a browser, a script tag or an administrator supplies onto one
  // of the languages above, or null when there is no reasonable match.
  //
  // Chinese needs more than a prefix match. The script matters more than the
  // region, so zh-Hant anywhere is Traditional, and Taiwan, Hong Kong and Macau
  // read Traditional even when the tag does not say so. Everything else that
  // starts with zh, including a bare "zh", is Simplified.
  function matchLocale(tag) {
    if (!tag) return null;
    var lower = String(tag).toLowerCase().replace(/_/g, "-");
    var i;

    for (i = 0; i < LOCALES.length; i++) {
      if (LOCALES[i].toLowerCase() === lower) return LOCALES[i];
    }

    var parts = lower.split("-");
    if (parts[0] === "zh") {
      if (parts.indexOf("hant") !== -1) return "zh-TW";
      if (parts.indexOf("hans") !== -1) return "zh-CN";
      if (parts.indexOf("tw") !== -1 || parts.indexOf("hk") !== -1 || parts.indexOf("mo") !== -1) {
        return "zh-TW";
      }
      return "zh-CN";
    }

    for (i = 0; i < LOCALES.length; i++) {
      if (LOCALES[i].toLowerCase() === parts[0]) return LOCALES[i];
    }
    return null;
  }

  // navigator.languages is the visitor's list in order of preference, so a
  // browser set to German then French gets French here rather than English.
  function browserLocale() {
    var wanted = [];
    try {
      if (navigator.languages && navigator.languages.length) {
        wanted = Array.prototype.slice.call(navigator.languages);
      } else if (navigator.language || navigator.userLanguage) {
        wanted = [navigator.language || navigator.userLanguage];
      }
    } catch (e) {
      wanted = [];
    }

    for (var i = 0; i < wanted.length; i++) {
      var match = matchLocale(wanted[i]);
      if (match) return match;
    }
    return "en";
  }

  // Most specific wish first:
  //
  //   1. what this visitor picked in the widget's own settings
  //   2. data-lang on the script tag, for a page that knows its own language,
  //      for example a /fr/ section of a multilingual site
  //   3. a language the administrator fixed for this website
  //   4. the visitor's browser
  //
  // "auto" at any level means "no opinion, ask the next one".
  function resolveLocale() {
    var picked = state.prefs && state.prefs.language;
    if (picked && picked !== "auto" && matchLocale(picked)) return matchLocale(picked);

    var attr = SCRIPT.getAttribute("data-lang");
    if (attr && attr !== "auto" && matchLocale(attr)) return matchLocale(attr);

    var fixed = state.site && state.site.theme && state.site.theme.locale;
    if (fixed && fixed !== "auto" && matchLocale(fixed)) return matchLocale(fixed);

    return browserLocale();
  }

  // Only string values are taken from a fetched table. It is JSON from a URL,
  // and although every string is escaped before it reaches the page, a table
  // carrying objects or numbers is malformed and is better ignored than trusted.
  function fetchTable(url) {
    return fetch(url, { credentials: "omit" })
      .then(function (res) {
        return res.ok ? res.json() : null;
      })
      .then(function (table) {
        if (!table || typeof table !== "object") return null;
        var clean = {};
        Object.keys(table).forEach(function (key) {
          if (typeof table[key] === "string" && table[key]) clean[key] = table[key];
        });
        return clean;
      })
      .catch(function () {
        /* a missing or malformed table leaves the current language in place */
        return null;
      });
  }

  function activateLocale(code) {
    activeLocale = code;

    var next = {};
    var layers = [EN, localeTables[code], customTable];
    layers.forEach(function (layer) {
      if (!layer) return;
      Object.keys(layer).forEach(function (key) {
        next[key] = layer[key];
      });
    });
    STRINGS = next;

    render();
  }

  // Works out which language should be showing and switches to it, fetching its
  // table the first time. Safe to call as often as something changes: a visitor
  // setting, the site configuration arriving, a sign in.
  //
  // wantedLocale guards against a slow response for a language the visitor has
  // already moved away from arriving late and overwriting their newer choice.
  function refreshLocale() {
    var code = resolveLocale();
    wantedLocale = code;

    if (code === "en" || localeTables[code]) {
      if (code !== activeLocale) activateLocale(code);
      return Promise.resolve();
    }

    return fetchTable(BRIDGE + "/chat-bridge/widget.strings." + encodeURIComponent(code) + ".json").then(
      function (table) {
        if (!table) return;
        localeTables[code] = table;
        if (wantedLocale === code) activateLocale(code);
      }
    );
  }

  // An integrator can still supply a table of their own, for a language this
  // widget does not ship or to reword something for their site:
  //
  //   <script src="...widget.js" data-site-key="..." data-strings-url="/nl.json">
  //
  // It is laid over whichever language is active, so it wins key by key, and
  // anything it leaves out falls back rather than breaking the interface.
  function loadCustomStrings() {
    var url = SCRIPT.getAttribute("data-strings-url");
    if (!url) return Promise.resolve();

    return fetchTable(new URL(url, window.location.href).href).then(function (table) {
      if (!table) return;
      customTable = table;
      activateLocale(activeLocale);
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
    view: "channels",
    searchTerm: "",
    searchResults: [],
    searching: false,
    recording: false,
    recordSeconds: 0,
    uploading: false,
    ready: false,
    prefs: { sound: true, appearance: "system", language: "auto" }
  };

  try {
    state.token = window.sessionStorage.getItem(STORAGE_KEY);
  } catch (e) {
    // Private browsing or blocked storage. The widget still works, the visitor
    // just signs in again on the next page load.
    state.token = null;
  }

  // Per viewer conveniences, kept in the visitor's own browser. Deliberately not
  // on the server: they are preferences about this device, not about the
  // account, and an account level setting would follow someone onto a shared
  // computer. Every access is wrapped, because storage throws outright in
  // private browsing and a blocked preference must not break the widget.
  var PREFS_KEY = "dcb.prefs." + SITE_KEY;

  function loadPrefs() {
    var defaults = { sound: true, appearance: "system", language: "auto" };
    try {
      var raw = window.localStorage.getItem(PREFS_KEY);
      if (!raw) return defaults;
      var parsed = JSON.parse(raw);
      return {
        sound: parsed.sound !== false,
        appearance: ["system", "light", "dark"].indexOf(parsed.appearance) !== -1
          ? parsed.appearance
          : "system",
        language: LOCALES.indexOf(parsed.language) !== -1 ? parsed.language : "auto"
      };
    } catch (e) {
      return defaults;
    }
  }

  function savePrefs() {
    try {
      window.localStorage.setItem(PREFS_KEY, JSON.stringify(state.prefs));
    } catch (e) {
      /* a preference that cannot be remembered is not worth an error */
    }
  }

  // Loaded here, after PREFS_KEY exists. Calling loadPrefs before that line ran
  // read localStorage under the key `undefined`, which returns null, so every
  // saved preference was silently discarded on load while saving appeared to
  // work perfectly.
  state.prefs = loadPrefs();

  // The site's appearance, remembered from the last visit. Without it the bubble
  // could only be drawn after a round trip to the forum, so a returning visitor
  // would watch an empty corner on every page of the host site. With it the
  // bubble is drawn at once in the right colours and the right corner, and the
  // copy is refreshed in the background. It holds nothing private: the same
  // values are handed to any visitor of the site.
  var SITE_CACHE_KEY = "dcb.site." + SITE_KEY;

  function loadCachedSite() {
    try {
      var raw = window.localStorage.getItem(SITE_CACHE_KEY);
      if (!raw) return null;
      var parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object" || typeof parsed.theme !== "object") return null;
      return parsed;
    } catch (e) {
      return null;
    }
  }

  function saveCachedSite(site) {
    try {
      window.localStorage.setItem(SITE_CACHE_KEY, JSON.stringify(site));
    } catch (e) {
      /* nothing depends on this being remembered */
    }
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
    if (code === "dm_not_available") return t("error_dm_not_available");
    if (code === "dm_refused" || code === "no_recipients") return t("error_dm_refused");
    if (code === "upload_type") return t("mic_unavailable");
    if (code === "upload_too_large" || code === "voice_too_long") return t("voice_too_long");
    return t("error_generic");
  }

  /* ----------------------------------------------------------------- auth */

  var authWindow = null;
  var authPoll = null;

  // Signing in does not rely on the popup being able to talk back.
  //
  // Discourse's own /login page carries Cross-Origin-Opener-Policy:
  // same-origin-allow-popups, which severs window.opener when the opener is a
  // different origin, permanently. Any visitor not already signed in to the
  // forum passes through that page, so postMessage fails for the common case and
  // the popup would sit there claiming success while nothing happened.
  //
  // Instead the widget starts a handshake, keeps a secret that never enters a
  // URL, opens the popup with only an id, and then asks the bridge for the
  // result. postMessage is kept purely as a shortcut to poll immediately rather
  // than waiting for the next tick.
  function signIn() {
    if (state.signingIn) return;

    state.signingIn = true;
    state.error = null;
    render();

    var nonce = String(Math.random()).slice(2) + String(Date.now());

    // The language goes along so the few words the popup itself shows match the
    // panel, including when the visitor chose a language their browser is not
    // set to.
    api("/auth/begin", { state: nonce, lang: activeLocale })
      .then(function (data) {
        var w = 460;
        var h = 640;
        var left = window.screenX + (window.outerWidth - w) / 2;
        var top = window.screenY + (window.outerHeight - h) / 2;

        authWindow = window.open(
          data.auth_url,
          "discourse-chat-bridge-login",
          "width=" + w + ",height=" + h + ",left=" + left + ",top=" + top
        );

        if (!authWindow) {
          state.signingIn = false;
          state.error = t("popup_blocked");
          render();
          return;
        }

        var onMessage = function (event) {
          if (event.origin !== BRIDGE) return;
          var d = event.data;
          if (!d || d.type !== "chat-bridge-auth" || d.state !== nonce) return;
          window.removeEventListener("message", onMessage);
          pollClaim(data, 0, true);
        };
        window.addEventListener("message", onMessage);

        pollClaim(data, 0, false);
      })
      .catch(function (err) {
        state.signingIn = false;
        state.error = errorMessage(err.code);
        render();
      });
  }

  function pollClaim(handshake, attempt, immediate) {
    clearTimeout(authPoll);

    var limit = Math.ceil((handshake.expires_in || 300) / 1.5);
    if (attempt > limit) {
      state.signingIn = false;
      state.error = t("error_generic");
      render();
      return;
    }

    var run = function () {
      api("/auth/claim", {
        handshake_id: handshake.handshake_id,
        claim_secret: handshake.claim_secret
      })
        .then(function (data) {
          if (data.status === "pending") {
            pollClaim(handshake, attempt + 1, false);
            return;
          }

          state.signingIn = false;
          saveToken(data.token);
          state.user = data.user;
          state.error = null;
          try {
            if (authWindow && !authWindow.closed) authWindow.close();
          } catch (e) {
            /* the popup may be in another context group, which is the whole
               reason this polling exists. Nothing to do. */
          }
          loadSession();
        })
        .catch(function (err) {
          // A rejected claim is terminal: the handshake expired, or was already
          // used. Anything else is transient and worth another try.
          if (err.code === "invalid_token" || err.code === "origin_mismatch") {
            state.signingIn = false;
            state.error = errorMessage(err.code);
            render();
            return;
          }
          pollClaim(handshake, attempt + 1, false);
        });
    };

    if (immediate) run();
    else authPoll = setTimeout(run, 1500);
  }

  function signOut() {
    var done = function () {
      clearTimeout(authPoll);
      state.signingIn = false;
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
        state.loading = false;
        setSite(data.site);
        if (!data.user.can_chat) {
          render();
          return;
        }
        transport.start(null);
        return loadChannels(true);
      })
      .catch(function (err) {
        state.loading = false;
        state.error = errorMessage(err.code);
        render();
      });
  }

  // The site's appearance and switches, asked for before anyone has signed in.
  //
  // It used to arrive only with /session/me, which meant an administrator's
  // colours and corner applied to signed in visitors alone: everyone else, which
  // on a public website is nearly everyone, saw the default blue bubble in the
  // default corner. The endpoint needs no token, because what it returns is what
  // the page shows to any visitor anyway.
  function loadSiteConfig() {
    return api("/site/config")
      .then(function (data) {
        if (data && data.site) setSite(data.site);
      })
      .catch(function () {
        /* an older forum has no such endpoint, and a forum having a bad moment
           may not answer. Either way the defaults, or the remembered copy, are
           a better outcome than no bubble. */
      });
  }

  function setSite(site) {
    if (!site || typeof site !== "object") return;
    state.site = { theme: site.theme || {}, features: site.features || {} };
    saveCachedSite(state.site);
    applyTheme();
    refreshLocale();
  }

  // autoOpen is only true on first load, where dropping the visitor straight
  // into a conversation is helpful. After an explicit Back it must be false, or
  // the list re-opens the first channel and the visitor can never reach it.
  function loadChannels(autoOpen) {
    return api("/channels/list")
      .then(function (data) {
        state.channels = data.channels || [];
        state.unread = state.channels.reduce(function (sum, c) {
          return sum + (c.unread_count || 0);
        }, 0);

        if (autoOpen && !state.activeChannelId && state.channels.length) {
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

  /* -------------------------------------------------------- people and dms */

  var searchTimer = null;

  // Debounced, because this runs on every keystroke and each call reaches the
  // forum's search service. 250ms is long enough to collapse typing into one
  // request and short enough that the list still feels live.
  function searchPeople(term) {
    state.searchTerm = term;
    clearTimeout(searchTimer);

    if (!term.trim()) {
      state.searchResults = [];
      state.searching = false;
      render();
      return;
    }

    state.searching = true;
    render();

    searchTimer = setTimeout(function () {
      var asked = term;
      api("/users/search", { term: term })
        .then(function (data) {
          // A slower earlier request must not overwrite a newer one's results.
          if (state.searchTerm !== asked) return;
          state.searching = false;
          state.searchResults = data.users || [];
          render();
        })
        .catch(function (err) {
          if (state.searchTerm !== asked) return;
          state.searching = false;
          state.searchResults = [];
          state.error = errorMessage(err.code);
          render();
        });
    }, 250);
  }

  function openDirectMessage(username) {
    state.searching = true;
    state.error = null;
    render();

    api("/dm/open", { usernames: [username] })
      .then(function (data) {
        state.searching = false;
        state.searchTerm = "";
        state.searchResults = [];

        // The new conversation will not be in the cached channel list yet, so
        // add it rather than waiting for the next refresh.
        var known = false;
        for (var i = 0; i < state.channels.length; i++) {
          if (state.channels[i].id === data.channel.id) known = true;
        }
        if (!known) state.channels = [data.channel].concat(state.channels);

        openChannel(data.channel.id);
      })
      .catch(function (err) {
        state.searching = false;
        state.error = errorMessage(err.code);
        render();
      });
  }

  /* ---------------------------------------------------------------- voice */

  var recorder = null;
  var recordStream = null;
  var recordChunks = [];
  var recordTimer = null;
  var recordCancelled = false;

  var MAX_RECORD_SECONDS = 300;

  // Format preference matters more than it looks. Discourse renders m4a and ogg
  // as an audio player for ordinary forum users; webm it treats as a plain
  // attachment, because webm is absent from its supported audio list. So webm is
  // a last resort rather than the obvious first choice it appears to be.
  function pickMimeType() {
    if (!window.MediaRecorder) return null;
    var preferred = [
      "audio/mp4",
      "audio/ogg;codecs=opus",
      "audio/ogg",
      "audio/webm;codecs=opus",
      "audio/webm"
    ];
    for (var i = 0; i < preferred.length; i++) {
      try {
        if (MediaRecorder.isTypeSupported(preferred[i])) return preferred[i];
      } catch (e) {
        /* isTypeSupported can throw on some older browsers */
      }
    }
    return null;
  }

  function startRecording() {
    if (state.recording || state.uploading) return;

    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || !window.MediaRecorder) {
      state.error = t("mic_unavailable");
      render();
      return;
    }

    var mime = pickMimeType();
    if (!mime) {
      state.error = t("mic_unavailable");
      render();
      return;
    }

    // Asked for at the moment of use rather than on load, so the browser's
    // permission prompt arrives with an obvious cause.
    navigator.mediaDevices
      .getUserMedia({ audio: true })
      .then(function (stream) {
        recordStream = stream;
        recordChunks = [];
        recordCancelled = false;

        recorder = new MediaRecorder(stream, { mimeType: mime });
        recorder.ondataavailable = function (event) {
          if (event.data && event.data.size > 0) recordChunks.push(event.data);
        };
        recorder.onstop = function () {
          releaseMicrophone();
          if (recordCancelled) {
            recordChunks = [];
            return;
          }
          var blob = new Blob(recordChunks, { type: mime });
          recordChunks = [];
          if (blob.size > 0) uploadVoice(blob, mime);
        };

        recorder.start();
        state.recording = true;
        state.recordSeconds = 0;
        state.error = null;
        render();

        recordTimer = setInterval(function () {
          state.recordSeconds = state.recordSeconds + 1;
          if (state.recordSeconds >= MAX_RECORD_SECONDS) {
            state.error = t("voice_too_long");
            stopRecording(false);
            return;
          }
          render();
        }, 1000);
      })
      .catch(function () {
        state.error = t("mic_denied");
        render();
      });
  }

  function stopRecording(cancel) {
    if (!state.recording) return;
    recordCancelled = !!cancel;
    clearInterval(recordTimer);
    recordTimer = null;
    state.recording = false;
    state.recordSeconds = 0;
    render();

    try {
      if (recorder && recorder.state !== "inactive") recorder.stop();
      else releaseMicrophone();
    } catch (e) {
      releaseMicrophone();
    }
  }

  // The browser keeps showing a recording indicator until every track is
  // stopped, so leaving them running would tell the visitor they are still being
  // listened to when they are not.
  function releaseMicrophone() {
    if (!recordStream) return;
    try {
      recordStream.getTracks().forEach(function (track) {
        track.stop();
      });
    } catch (e) {
      /* nothing useful to do */
    }
    recordStream = null;
    recorder = null;
  }

  function extensionFor(mime) {
    if (mime.indexOf("mp4") !== -1) return "m4a";
    if (mime.indexOf("ogg") !== -1) return "ogg";
    if (mime.indexOf("mpeg") !== -1) return "mp3";
    return "webm";
  }

  function uploadVoice(blob, mime) {
    state.uploading = true;
    render();

    var form = new FormData();
    form.append("file", blob, "voice-message." + extensionFor(mime));

    var headers = {};
    if (state.token) headers["Authorization"] = "Bearer " + state.token;

    // Deliberately not using api(), which sends JSON. The body here is
    // multipart, and Content-Type must be left unset so the browser can add the
    // boundary itself.
    fetch(API + "/uploads/create", {
      method: "POST",
      mode: "cors",
      credentials: "omit",
      headers: headers,
      body: form
    })
      .then(function (res) {
        return res.json().catch(function () {
          return { ok: false, error: { code: "error_generic" } };
        });
      })
      .then(function (json) {
        if (!json || !json.ok) {
          var code = (json && json.error && json.error.code) || "error_generic";
          throw Object.assign(new Error(code), { code: code });
        }
        return api("/messages/send", {
          channel_id: state.activeChannelId,
          upload_ids: [json.data.upload.id],
          client_nonce: String(Date.now()) + String(Math.random()).slice(2)
        });
      })
      .then(function (data) {
        state.uploading = false;
        mergeMessages([data.message]);
        render();
        scrollToBottom();
      })
      .catch(function (err) {
        state.uploading = false;
        state.error = errorMessage(err.code);
        render();
      });
  }

  /* ---------------------------------------------------------------- sound */

  var audioContext = null;

  // Synthesised rather than shipped as a file. A short two tone chime costs no
  // request, no asset to cache and nothing to go stale, and it cannot be blocked
  // as a third party resource on the host page.
  function playNotification() {
    if (!state.prefs.sound) return;

    try {
      var Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return;
      if (!audioContext) audioContext = new Ctx();
      if (audioContext.state === "suspended") audioContext.resume();

      var now = audioContext.currentTime;
      [[880, 0], [1320, 0.09]].forEach(function (pair) {
        var osc = audioContext.createOscillator();
        var gain = audioContext.createGain();
        osc.type = "sine";
        osc.frequency.value = pair[0];
        gain.gain.setValueAtTime(0.0001, now + pair[1]);
        gain.gain.exponentialRampToValueAtTime(0.12, now + pair[1] + 0.015);
        gain.gain.exponentialRampToValueAtTime(0.0001, now + pair[1] + 0.18);
        osc.connect(gain);
        gain.connect(audioContext.destination);
        osc.start(now + pair[1]);
        osc.stop(now + pair[1] + 0.2);
      });
    } catch (e) {
      /* audio is a nicety, never a reason to fail */
    }
  }

  function muteChannel(channelId, muted) {
    return api("/channels/mute", { channel_id: channelId, muted: muted })
      .then(function (data) {
        for (var i = 0; i < state.channels.length; i++) {
          if (state.channels[i].id === data.channel_id) state.channels[i].muted = data.muted;
        }
        render();
      })
      .catch(function (err) {
        state.error = errorMessage(err.code);
        render();
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
    var fromSomeoneElse = messages.some(function (m) {
      return !state.user || !m.user || m.user.id !== state.user.id;
    });

    mergeMessages(messages);
    if (fromSomeoneElse) playNotification();
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
    ".wrap{--p-bg:#fff;--p-fg:#1b1b1b;--p-line:#e6e6e6;--p-input:#fff;--p-input-line:#d6d6d6;",
    "--p-hover:#f1f5f9;--p-muted:#555;--p-soft:#f4f4f4;--p-sub:#777;",
    "position:fixed;bottom:16px;right:16px;display:flex;flex-direction:column;align-items:flex-end;gap:10px}",
    ".wrap.left{right:auto;left:16px;align-items:flex-start}",
    ".bubble{width:56px;height:56px;border-radius:50%;border:none;cursor:pointer;background:var(--cb-launcher-bg,var(--cb-accent,#0b6ecf));color:var(--cb-launcher-fg,#fff);box-shadow:0 6px 20px rgba(0,0,0,.25);display:flex;align-items:center;justify-content:center;position:relative}",
    ".bubble:hover{filter:brightness(.92)}",
    ".bubble svg{width:26px;height:26px;fill:currentColor}",
    ".badge{position:absolute;top:-2px;right:-2px;min-width:20px;height:20px;border-radius:10px;background:#d4351c;color:#fff;font-size:11px;font-weight:700;display:flex;align-items:center;justify-content:center;padding:0 5px}",
    ".panel{width:370px;max-width:calc(100vw - 32px);height:540px;max-height:calc(100vh - 110px);background:var(--p-bg);color:var(--p-fg);border-radius:12px;box-shadow:0 12px 40px rgba(0,0,0,.28);display:flex;flex-direction:column;overflow:hidden}",
    ".hd{display:flex;align-items:center;gap:8px;padding:12px 14px;background:var(--cb-accent,#0b6ecf);color:var(--cb-on-accent,#fff);flex:0 0 auto}",
    ".hd h2{margin:0;font-size:15px;font-weight:600;flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}",
    // nowrap and no shrinking, because Back and Sign out are words, and words
    // are longer in most languages than they are in English. The title is the
    // part that gives way, with an ellipsis.
    ".hd button{background:transparent;border:none;color:inherit;cursor:pointer;font-size:13px;padding:4px 6px;border-radius:5px;white-space:nowrap;flex:0 0 auto}",
    ".hd button:hover{background:var(--cb-on-accent-hover,rgba(255,255,255,.18))}",
    ".body{flex:1 1 auto;overflow-y:auto;padding:12px}",
    ".ft{flex:0 0 auto;border-top:1px solid var(--p-line);padding:8px;display:flex;gap:8px}",
    ".ft textarea{flex:1;resize:none;border:1px solid var(--p-input-line);border-radius:8px;padding:8px 10px;font-size:14px;min-height:38px;max-height:120px;line-height:1.35;color:inherit;background:var(--p-input)}",
    ".ft textarea:focus{outline:2px solid var(--cb-accent,#0b6ecf);outline-offset:-1px}",
    ".ft button{border:none;background:var(--cb-accent,#0b6ecf);color:var(--cb-on-accent,#fff);border-radius:8px;padding:0 14px;cursor:pointer;font-size:14px;font-weight:600;white-space:nowrap;flex:0 0 auto;min-height:38px}",
    // Faded rather than a fixed pale blue, which only looked right against the
    // default accent.
    ".ft button:disabled{opacity:.55;cursor:default}",
    ".ft button.mic{background:transparent;color:var(--cb-accent,#0b6ecf);padding:0 8px;display:flex;align-items:center}",
    ".ft button.mic:hover{filter:brightness(.92)}",
    ".ft button.mic svg{width:22px;height:22px;fill:currentColor}",
    ".ft button.ghost{background:transparent;color:var(--p-muted);font-weight:500}",
    ".ft.recording{align-items:center}",
    ".ft .rec{flex:1;min-width:0;display:flex;align-items:center;gap:8px;font-size:14px;color:var(--p-muted);padding-left:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}",
    ".ft .rec .dot{flex:0 0 auto}",
    ".ft .rec .dot{width:10px;height:10px;border-radius:50%;background:#d4351c;animation:cbpulse 1.2s ease-in-out infinite}",
    "@keyframes cbpulse{0%,100%{opacity:1}50%{opacity:.25}}",
    ".msg .txt audio{width:100%;max-width:260px;margin-top:4px;display:block}",
    ".msg .txt img.att{max-width:100%;border-radius:8px;margin-top:4px;display:block}",
    ".msg .txt a.file{display:inline-block;margin-top:4px;padding:6px 10px;border:1px solid var(--p-input-line);border-radius:8px;text-decoration:none;font-size:13px}",
    ".msg .txt a.file span{color:#777}",
    ".ch{display:block;width:100%;text-align:left;border:none;background:transparent;padding:10px;border-radius:8px;cursor:pointer;font-size:14px;display:flex;align-items:center;gap:8px}",
    ".ch:hover{background:var(--p-hover)}",
    ".ch .n{flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}",
    ".ch .u{background:#d4351c;color:#fff;border-radius:9px;min-width:18px;height:18px;font-size:11px;display:flex;align-items:center;justify-content:center;padding:0 5px}",
    ".msg{display:flex;gap:8px;padding:6px 0}",
    ".msg img.av{width:32px;height:32px;border-radius:50%;flex:0 0 auto}",
    ".msg .c{flex:1;min-width:0}",
    ".msg .meta{font-size:12px;color:#666;margin-bottom:2px}",
    ".msg .meta b{color:var(--p-fg);font-weight:600}",
    ".msg .txt{font-size:14px;line-height:1.45;word-wrap:break-word;overflow-wrap:anywhere}",
    ".msg .txt p{margin:0 0 6px}",
    ".msg .txt p:last-child{margin:0}",
    ".msg .txt img.emoji{width:18px;height:18px;vertical-align:-3px}",
    ".msg .txt pre{background:var(--p-soft);padding:8px;border-radius:6px;overflow-x:auto}",
    ".msg .txt code{background:var(--p-soft);padding:1px 4px;border-radius:4px;font-family:ui-monospace,monospace;font-size:13px}",
    ".msg .txt blockquote{margin:0;padding-left:10px;border-left:3px solid #ddd;color:#555}",
    ".msg .txt a{color:var(--cb-accent,#0b6ecf)}",
    ".search{padding:0 0 8px}",
    ".search input{width:100%;border:1px solid var(--p-input-line);border-radius:8px;padding:9px 11px;font-size:14px;background:var(--p-input);color:inherit}",
    ".search input:focus{outline:2px solid var(--cb-accent,#0b6ecf);outline-offset:-1px}",
    ".ch .sub{display:block;font-size:12px;color:var(--p-sub);font-weight:400}",
    ".ch .dm{color:#888;font-weight:700;flex:0 0 auto}",
    ".ch img.av{width:28px;height:28px;border-radius:50%;flex:0 0 auto}",
    ".settings{padding:4px 2px}",
    ".settings .opt{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:11px 8px;border-bottom:1px solid var(--p-line);font-size:14px}",
    ".settings .opt:last-child{border-bottom:none}",
    ".settings label.opt{cursor:pointer;justify-content:flex-start;gap:10px}",
    ".settings select{font:inherit;padding:5px 7px;border:1px solid var(--p-input-line);border-radius:7px;background:var(--p-input);color:inherit;max-width:60%}",
    ".note{padding:16px;text-align:center;color:var(--p-muted);font-size:14px;line-height:1.5}",
    ".note h3{margin:0 0 6px;font-size:15px;color:var(--p-fg)}",
    ".err{background:#fdecea;color:#8b1a10;padding:8px 12px;font-size:13px}",
    ".btn{border:none;background:var(--cb-accent,#0b6ecf);color:var(--cb-on-accent,#fff);border-radius:8px;padding:9px 14px;cursor:pointer;font-size:14px;font-weight:600}",
    ".more{width:100%;border:1px solid var(--p-input-line);background:var(--p-input);border-radius:8px;padding:6px;cursor:pointer;font-size:13px;color:var(--p-muted);margin-bottom:8px}",
    // On a phone a 358px card wastes most of the screen and leaves the composer
    // cramped, so the panel takes the whole viewport instead and the bubble gets
    // out of the way. dvh rather than vh, because vh on mobile browsers measures
    // the viewport as if the address bar were hidden, which pushes the composer
    // under it.
    "@media (max-width: 480px){",
    ".wrap.open{inset:0;bottom:0;right:0;left:0;gap:0}",
    ".wrap.open .panel{width:100%;max-width:100%;height:100vh;height:100dvh;max-height:none;border-radius:0}",
    ".wrap.open .bubble{display:none}",
    ".wrap.open .hd{padding:14px;padding-top:max(14px,env(safe-area-inset-top))}",
    ".wrap.open .ft{padding-bottom:max(8px,env(safe-area-inset-bottom))}",
    ".wrap.open .hd button[data-act=close]{font-size:22px;padding:4px 10px}",
    "}",
    // The palette is defined twice on purpose. Once for visitors following
    // their system, skipped when they have explicitly chosen light, and once
    // for an explicit dark choice. A media query cannot be overridden by a
    // class, so a single definition would make the setting a one way door.
    "@media (prefers-color-scheme: dark){",
    ".wrap:not(.appearance-light){" + "--p-bg:#1f2124;--p-fg:#e8e8e8;--p-line:#33363a;--p-input:#2a2d31;--p-input-line:#3a3d42;"+
    "--p-hover:#2a2d31;--p-muted:#b4b4b4;--p-soft:#2a2d31;--p-sub:#9a9a9a;" + "}",
    "}",
    ".wrap.appearance-dark{" + "--p-bg:#1f2124;--p-fg:#e8e8e8;--p-line:#33363a;--p-input:#2a2d31;--p-input-line:#3a3d42;"+
    "--p-hover:#2a2d31;--p-muted:#b4b4b4;--p-soft:#2a2d31;--p-sub:#9a9a9a;" + "}",
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

  // Applied as custom properties rather than concatenated into the stylesheet,
  // so a value can never close a rule and start another.
  //
  // Each colour is also checked here, although the server already validates it
  // as an exact hex value. A custom property accepts almost any text, and one
  // that is not a colour does not fall back to the default: it makes the
  // declaration that uses it invalid, which for a background means transparent.
  // A bubble nobody can see is a worse failure than a bubble in the wrong blue,
  // so anything that is not a hex colour is treated as not set.
  function applyTheme() {
    var raw = (state.site && state.site.theme) || {};
    var theme = {
      accent: hexOrNull(raw.accent),
      launcher_bg: hexOrNull(raw.launcher_bg),
      launcher_icon: hexOrNull(raw.launcher_icon)
    };

    setThemeVar("--cb-accent", theme.accent);

    // Text drawn on the accent: the panel title, Send, Sign in. White suits the
    // default blue and most brand colours, and is unreadable on a pale one, so
    // it is worked out from the colour rather than assumed.
    var onAccent = theme.accent ? readableOn(theme.accent) : null;
    setThemeVar("--cb-on-accent", onAccent);
    setThemeVar("--cb-on-accent-hover", onAccent === DARK_TEXT ? "rgba(0,0,0,.1)" : null);

    // The launcher button can be coloured apart from the rest. Left unset, its
    // background follows the accent, and its icon takes whichever of light or
    // dark reads better against that background.
    setThemeVar("--cb-launcher-bg", theme.launcher_bg);
    var launcherBg = theme.launcher_bg || theme.accent;
    setThemeVar("--cb-launcher-fg", theme.launcher_icon || (launcherBg ? readableOn(launcherBg) : null));

    render();
  }

  function setThemeVar(name, value) {
    if (value) host.style.setProperty(name, value);
    else host.style.removeProperty(name);
  }

  var DARK_TEXT = "#1b1b1b";
  var HEX_COLOUR = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i;

  function hexOrNull(value) {
    return typeof value === "string" && HEX_COLOUR.test(value) ? value : null;
  }

  // Light or dark text for a given background, by relative luminance as WCAG
  // defines it. The threshold leans towards white on purpose: white on a mid
  // tone brand colour is what people expect to see, so dark text is used only
  // where white would be hard to read. Returns null for anything that is not a
  // hex colour, which leaves the stylesheet's own default in place.
  function readableOn(hex) {
    var m = HEX_COLOUR.exec(String(hex || ""));
    if (!m) return null;

    var h = m[1];
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];

    var weights = [0.2126, 0.7152, 0.0722];
    var luminance = 0;
    for (var i = 0; i < 3; i++) {
      var c = parseInt(h.substr(i * 2, 2), 16) / 255;
      c = c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
      luminance += c * weights[i];
    }
    return luminance > 0.45 ? DARK_TEXT : "#fff";
  }

  function themeValue(key, fallback) {
    var theme = (state.site && state.site.theme) || {};
    return theme[key] || fallback;
  }

  function siteAllows(feature) {
    var features = (state.site && state.site.features) || {};
    return features[feature] !== false;
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

  function humanSize(bytes) {
    if (!bytes) return "";
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return Math.round(bytes / 1024) + " KB";
    return (bytes / (1024 * 1024)).toFixed(1) + " MB";
  }

  // Attachments arrive as data rather than markup, because Discourse chat does
  // not put them in the message's HTML at all: a voice message has empty cooked
  // HTML and its file on the side. Building the player here also means a future
  // change to Discourse's own markup cannot silently break playback.
  function renderUploads(uploads) {
    if (!uploads || !uploads.length) return "";

    return uploads
      .map(function (u) {
        if (u.kind === "audio") {
          return (
            '<audio controls preload="metadata" src="' + esc(u.url) + '"></audio>'
          );
        }
        if (u.kind === "image") {
          return (
            '<a href="' + esc(u.url) + '" target="_blank" rel="noopener noreferrer nofollow">' +
            '<img class="att" src="' + esc(u.url) + '" alt="' + esc(u.filename) + '"></a>'
          );
        }
        return (
          '<a class="file" href="' + esc(u.url) + '" target="_blank" rel="noopener noreferrer nofollow">' +
          esc(u.filename) + " <span>" + esc(humanSize(u.filesize)) + "</span></a>"
        );
      })
      .join("");
  }

  function renderBody() {
    if (!state.token) {
      if (state.signingIn) {
        return (
          '<div class="note"><h3>' + esc(t("signing_in")) + "</h3><p>" +
          esc(t("signing_in_hint")) + "</p></div>"
        );
      }
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
    if (state.view === "settings") {
      var ch = activeChannel();
      var opts = [
        ["system", t("appearance_system")],
        ["light", t("appearance_light")],
        ["dark", t("appearance_dark")]
      ].map(function (pair) {
        return '<option value="' + pair[0] + '"' +
               (state.prefs.appearance === pair[0] ? " selected" : "") + ">" + esc(pair[1]) + "</option>";
      }).join("");

      // Each language is listed under its own name, not translated into the
      // current one, so someone who landed in a language they cannot read can
      // still recognise theirs.
      var langs = ['<option value="auto"' + (state.prefs.language === "auto" ? " selected" : "") +
                   ">" + esc(t("language_auto")) + "</option>"]
        .concat(LOCALES.map(function (code) {
          return '<option value="' + esc(code) + '" lang="' + esc(code) + '"' +
                 (state.prefs.language === code ? " selected" : "") + ">" +
                 esc(LOCALE_NAMES[code]) + "</option>";
        }))
        .join("");

      return (
        '<div class="settings">' +
        '<label class="opt"><input type="checkbox" data-pref="sound"' +
        (state.prefs.sound ? " checked" : "") + "> " + esc(t("sound")) + "</label>" +
        '<div class="opt"><span>' + esc(t("appearance")) + "</span>" +
        '<select data-pref="appearance">' + opts + "</select></div>" +
        '<div class="opt"><span>' + esc(t("language")) + "</span>" +
        '<select data-pref="language">' + langs + "</select></div>" +
        (ch
          ? '<label class="opt"><input type="checkbox" data-pref="muted"' +
            (ch.muted ? " checked" : "") + "> " + esc(t("mute_channel")) + "</label>"
          : "") +
        "</div>"
      );
    }

    if (state.view === "search") {
      var results = "";
      if (state.searching) {
        results = '<div class="note">' + esc(t("searching")) + "</div>";
      } else if (state.searchTerm.trim() && !state.searchResults.length) {
        results = '<div class="note">' + esc(t("no_people")) + "</div>";
      } else {
        results = state.searchResults
          .map(function (u) {
            var av = u.avatar_url ? '<img class="av" src="' + esc(u.avatar_url) + '" alt="">' : "";
            var sub = u.name ? '<span class="sub">' + esc(u.name) + "</span>" : "";
            return (
              '<button class="ch" data-username="' + esc(u.username) + '">' + av +
              '<span class="n">' + esc(u.username) + sub + "</span></button>"
            );
          })
          .join("");
      }
      return (
        '<div class="search"><input type="search" class="find" ' +
        'placeholder="' + esc(t("search_placeholder")) + '" ' +
        'aria-label="' + esc(t("search_people")) + '" ' +
        'value="' + esc(state.searchTerm) + '"></div>' + results
      );
    }

    if (state.view === "channels" || !state.activeChannelId) {
      var newBtn = siteAllows("direct_messages")
        ? '<button class="more" data-act="newdm">' + esc(t("new_message")) + "</button>"
        : "";
      if (!state.channels.length) {
        return newBtn + '<div class="note">' + esc(t("no_channels")) + "</div>";
      }
      return (
        newBtn +
        state.channels
          .map(function (c) {
            var u = c.unread_count > 0 ? '<span class="u">' + c.unread_count + "</span>" : "";
            var icon = c.kind === "dm" ? '<span class="dm">@</span>' : "";
            return (
              '<button class="ch" data-channel="' + c.id + '">' + icon +
              '<span class="n">' + esc(c.title) + "</span>" + u + "</button>"
            );
          })
          .join("")
      );
    }
    if (!state.messages.length) return '<div class="note">' + esc(t("no_messages")) + "</div>";

    var more = state.messages.length >= 30 ? '<button class="more" data-act="older">' + esc(t("load_older")) + "</button>" : "";

    return (
      more +
      state.messages
        .map(function (m) {
          if (m.deleted) return '<div class="msg"><div class="c"><div class="txt"><em>' + esc(t("deleted")) + "</em></div></div></div>";
          var av = m.user && m.user.avatar_url ? '<img class="av" src="' + esc(m.user.avatar_url) + '" alt="">' : "";
          var when = m.created_at ? clockTime(m.created_at) : "";
          var ed = m.edited ? " (" + esc(t("edited")) + ")" : "";
          // m.html has already been sanitized server side by ChatBridge::Sanitizer
          // against a strict allow list, with all URLs made absolute. It is the
          // only place in this file where markup is inserted unescaped.
          return (
            '<div class="msg">' + av + '<div class="c">' +
            '<div class="meta"><b>' + esc(m.user && m.user.username) + "</b> " + esc(when) + ed + "</div>" +
            '<div class="txt">' + m.html + renderUploads(m.uploads) + "</div></div></div>"
          );
        })
        .join("")
    );
  }

  // In the language the panel is showing, so a visitor who picked French does
  // not get an English "PM" beside every message. A browser that does not know
  // the locale falls back to its own default rather than failing.
  function clockTime(iso) {
    var date = new Date(iso);
    var format = { hour: "2-digit", minute: "2-digit" };
    try {
      return date.toLocaleTimeString(activeLocale, format);
    } catch (e) {
      return date.toLocaleTimeString([], format);
    }
  }

  function mmss(total) {
    var m = Math.floor(total / 60);
    var sec = total % 60;
    return m + ":" + (sec < 10 ? "0" : "") + sec;
  }

  function renderComposer() {
    if (state.recording) {
      return (
        '<div class="ft recording">' +
        '<span class="rec"><span class="dot"></span>' + esc(t("recording")) + " " +
        esc(mmss(state.recordSeconds)) + "</span>" +
        '<button class="ghost" data-act="reccancel">' + esc(t("cancel")) + "</button>" +
        '<button data-act="recstop">' + esc(t("stop_send")) + "</button></div>"
      );
    }

    if (state.uploading) {
      return '<div class="ft"><span class="rec">' + esc(t("uploading")) + "</span></div>";
    }

    return (
      '<div class="ft">' +
      '<textarea rows="1" placeholder="' + esc(t("composer_placeholder")) + '"></textarea>' +
      (siteAllows("voice_messages")
        ? '<button class="mic" data-act="record" aria-label="' + esc(t("record")) + '" title="' +
          esc(t("record")) + '">' +
          '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 15a3 3 0 0 0 3-3V6a3 3 0 0 0-6 0v6a3 3 0 0 0 3 3z"/>' +
          '<path d="M19 12a7 7 0 0 1-14 0H3a9 9 0 0 0 8 8.94V23h2v-2.06A9 9 0 0 0 21 12z"/></svg></button>'
        : "") +
      '<button data-act="send"' + (state.sending ? " disabled" : "") + ">" +
      esc(state.sending ? t("sending") : t("send")) + "</button></div>"
    );
  }

  function renderPanel() {
    var ch = activeChannel();
    // Always offer a way back out of a conversation. Hiding it when there is
    // only one channel seems tidy and is a trap: the channel list is also where
    // New message lives, so a visitor following a single channel could never
    // start a direct message.
    var showBack =
      state.view === "search" || state.view === "settings" || state.view === "messages";
    var title =
      state.view === "settings"
        ? t("settings")
        : state.view === "search"
        ? t("search_people")
        : state.view === "messages" && ch
          ? ch.title
          : themeValue("launcher_label", t("panel_title"));
    var canCompose =
      state.token && state.user && state.user.can_chat && state.view === "messages" &&
      state.activeChannelId;

    return (
      '<div class="panel" role="dialog" aria-label="' + esc(t("panel_title")) + '">' +
      '<div class="hd">' +
      (showBack ? '<button data-act="back">' + esc(t("back")) + "</button>" : "") +
      "<h2>" + esc(title) + "</h2>" +
      (state.token
        ? '<button data-act="settings" aria-label="' + esc(t("settings")) + '" title="' +
          esc(t("settings")) + '">' +
          '<svg viewBox="0 0 24 24" aria-hidden="true" width="16" height="16"><path fill="currentColor" ' +
          'd="M19.4 13a7.7 7.7 0 0 0 0-2l2-1.6-2-3.4-2.4 1a7.6 7.6 0 0 0-1.7-1L15 3.2h-4l-.3 2.7a7.6 7.6 0 0 0-1.7 1l-2.4-1-2 3.4L4.6 11a7.7 7.7 0 0 0 0 2l-2 1.6 2 3.4 2.4-1a7.6 7.6 0 0 0 1.7 1l.3 2.7h4l.3-2.7a7.6 7.6 0 0 0 1.7-1l2.4 1 2-3.4zM12 15a3 3 0 1 1 0-6 3 3 0 0 1 0 6z"/></svg>' +
          "</button>" +
          '<button data-act="signout">' + esc(t("sign_out")) + "</button>"
        : "") +
      '<button data-act="close" aria-label="' + esc(t("close")) + '">&times;</button>' +
      "</div>" +
      (state.error ? '<div class="err">' + esc(state.error) + "</div>" : "") +
      '<div class="body">' + renderBody() + "</div>" +
      (canCompose ? renderComposer() : "") +
      "</div>"
    );
  }

  function render() {
    // Nothing is drawn until boot has the site's appearance, or has given up
    // waiting for it. Drawing sooner would show the default bubble and then
    // recolour it, or worse, move it to the other corner.
    if (!state.ready) return;

    var scroll = null;
    var oldBody = root.querySelector(".body");
    if (oldBody) scroll = oldBody.scrollTop;

    var draft = "";
    var oldTa = root.querySelector(".ft textarea");
    if (oldTa) draft = oldTa.value;

    // The search box is rebuilt on every keystroke because rendering replaces
    // the panel's markup. Without restoring focus and caret the field would drop
    // focus mid-word and typing would be impossible.
    var findFocused = false;
    var findCaret = 0;
    var oldFind = root.querySelector(".search .find");
    if (oldFind) {
      findFocused = root.activeElement === oldFind;
      findCaret = oldFind.selectionStart;
    }

    var left = themeValue("position", "bottom-right") === "bottom-left";
    wrap.className =
      (state.open ? "wrap open" : "wrap") +
      (left ? " left" : "") +
      (state.prefs.appearance === "light" ? " appearance-light" : "") +
      (state.prefs.appearance === "dark" ? " appearance-dark" : "");
    // Declared so the browser picks the right glyphs. Chinese and Japanese
    // share code points for characters that are drawn differently, and without
    // a language the browser guesses from the host page.
    wrap.setAttribute("lang", activeLocale);
    wrap.innerHTML = (state.open ? renderPanel() : "") + renderBubble();

    var newBody = root.querySelector(".body");
    if (newBody && scroll !== null) newBody.scrollTop = scroll;

    var ta = root.querySelector(".ft textarea");
    if (ta && draft) ta.value = draft;

    var find = root.querySelector(".search .find");
    if (find && findFocused) {
      find.focus();
      try {
        find.setSelectionRange(findCaret, findCaret);
      } catch (e) {
        /* setSelectionRange is not allowed on every input type in every browser */
      }
    }
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
      var username = chBtn.getAttribute("data-username");
      if (username) {
        openDirectMessage(username);
      } else {
        openChannel(parseInt(chBtn.getAttribute("data-channel"), 10));
      }
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
      // Settings is reached from a conversation, so Back returns there rather
      // than dumping the visitor at the channel list they did not come from.
      if (state.view === "settings" && state.activeChannelId) {
        state.view = "messages";
        render();
        return;
      }
      state.view = "channels";
      state.activeChannelId = null;
      state.searchTerm = "";
      state.searchResults = [];
      transport.start(null);
      loadChannels(false);
    } else if (act === "settings") {
      state.view = "settings";
      state.error = null;
      render();
    } else if (act === "newdm") {
      state.view = "search";
      state.searchTerm = "";
      state.searchResults = [];
      state.error = null;
      render();
      var find = root.querySelector(".search .find");
      if (find) find.focus();
    } else if (act === "older") {
      loadOlder();
    } else if (act === "record") {
      startRecording();
    } else if (act === "recstop") {
      stopRecording(false);
    } else if (act === "reccancel") {
      stopRecording(true);
    } else if (act === "send") {
      var ta = root.querySelector(".ft textarea");
      if (ta) {
        var text = ta.value;
        ta.value = "";
        sendMessage(text);
      }
    }
  });

  wrap.addEventListener("input", function (event) {
    if (event.target.matches(".search .find")) {
      searchPeople(event.target.value);
      return;
    }

    var pref = event.target.getAttribute && event.target.getAttribute("data-pref");
    if (!pref) return;

    if (pref === "sound") {
      state.prefs.sound = event.target.checked;
      savePrefs();
      // Play it once on enabling, so the choice is audible rather than a claim.
      if (state.prefs.sound) playNotification();
      render();
    } else if (pref === "appearance") {
      state.prefs.appearance = event.target.value;
      savePrefs();
      render();
    } else if (pref === "language") {
      state.prefs.language = LOCALES.indexOf(event.target.value) !== -1 ? event.target.value : "auto";
      savePrefs();
      refreshLocale();
    } else if (pref === "muted") {
      var ch = activeChannel();
      if (ch) muteChannel(ch.id, event.target.checked);
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

  // How long a first time visitor waits for the site's appearance before the
  // bubble is drawn with the defaults. Long enough for an ordinary round trip,
  // short enough that a forum having a bad moment does not hide the chat.
  var FIRST_PAINT_WAIT_MS = 2500;

  function boot() {
    document.body.appendChild(host);

    var cached = loadCachedSite();
    if (cached) state.site = { theme: cached.theme || {}, features: cached.features || {} };

    // Started straight away and not waited for. The bubble carries no visible
    // text, so it does not need its language to be drawn, and the panel is
    // redrawn the moment the table arrives.
    refreshLocale();
    loadCustomStrings();

    var config = loadSiteConfig();
    var firstPaint = cached
      ? Promise.resolve()
      : Promise.race([
          config,
          new Promise(function (resolve) {
            setTimeout(resolve, FIRST_PAINT_WAIT_MS);
          })
        ]);

    firstPaint.then(function () {
      state.ready = true;
      applyTheme();
      if (state.token) loadSession();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
