# frozen_string_literal: true

module ChatBridge
  # The login popup lands here.
  #
  # This is the one place in the plugin that behaves like a normal forum page
  # rather than an API. The popup is a first party window on the forum, so it can
  # see the visitor's ordinary forum session. That is what makes this simple:
  # there is no identity protocol to run, no shared secret, and no second login.
  # If they are signed in, we know who they are. If they are not, we send them to
  # the forum's own login screen and they come back here afterwards.
  class AuthController < ::ApplicationController
    requires_plugin ChatBridge::PLUGIN_NAME

    skip_before_action :check_xhr, raise: false
    skip_before_action :preload_json, raise: false
    skip_before_action :redirect_to_login_if_required, raise: false
    skip_before_action :redirect_to_profile_if_required, raise: false

    layout false

    # Discourse sets this header in an after_action, gated on spa_boot_request?,
    # which is true for any plain GET. So setting it in a before_action is
    # pointless: theirs runs later and wins. Skip theirs, then set ours after the
    # response is built, which is the only point that actually sticks.
    skip_after_action :set_cross_origin_opener_policy_header, raise: false
    after_action :allow_opener_access

    # Discourse serves Cross-Origin-Opener-Policy: same-origin-allow-popups.
    # That name is misleading for this case: it preserves the opener for popups
    # this origin opens, but when the document IS a popup opened by a cross
    # origin page, the browsing context group is switched and window.opener
    # becomes null. The handshake then has nothing to post the token to.
    #
    # Discourse's own middleware only sets the header when a controller has not,
    # so setting it here wins. This endpoint's whole purpose is to talk back to
    # the page that opened it, and it still only ever posts to one exact
    # registered origin.
    def allow_opener_access
      response.headers["Cross-Origin-Opener-Policy"] = "unsafe-none"
    end

    def start
      return render_auth_failure("chat_disabled") if !SiteSetting.chat_bridge_enabled

      handshake = ChatBridge::AuthNonce.find_by(nonce: params[:handshake].to_s)
      return render_auth_failure("unknown_site") if handshake.nil? || !handshake.fresh?

      site = ChatBridge::Site.enabled.find_by(id: handshake.site_id)
      return render_auth_failure("unknown_site") if site.nil?

      # The visitor is not signed in to the forum, so send them to the forum's
      # own login and come back here afterwards. The handshake id is in the URL,
      # so nothing needs carrying in the session across that round trip.
      return redirect_to_login if current_user.nil?

      authorized = ChatBridge::AuthNonce.authorize!(handshake.nonce, current_user.id)
      return render_auth_failure("invalid_token") if authorized.nil?

      # The widget is already polling and will collect the token itself. This
      # postMessage is only a shortcut for the case where the opener survived,
      # which is when the visitor was signed in already and never passed through
      # the login page. It carries no token: only a nudge to poll immediately.
      @site = site
      @state = authorized.state
      render_handshake_page
    end

    private

    # Discourse serves a Content Security Policy with
    # `script-src 'nonce-...' 'strict-dynamic'`. Under strict-dynamic, 'self'
    # and host allow lists are ignored, so neither an inline script nor an
    # external file will run without the nonce. Asking for the placeholder also
    # registers the response header that makes the middleware add the nonce to
    # the policy, so this must be called while rendering, not earlier.
    #
    # Getting this wrong is silent: the page renders, the script never executes,
    # and the popup sits there saying it signed you in while the widget waits
    # forever. Which is exactly what happened.
    def csp_nonce
      ::ContentSecurityPolicy.nonce_placeholder(response.headers, request_env: request.env)
    end

    # Returns a page whose only job is to hand the token to the window that
    # opened it and then close. The postMessage target is the site's registered
    # origin, never "*", so the token cannot be read by any other page even if
    # something unexpected opened this window.
    def render_handshake_page
      payload = { type: "chat-bridge-auth", state: @state, authorized: true }

      render html: handshake_html(payload, @site.origin, csp_nonce).html_safe,
             content_type: "text/html"
    end

    def render_auth_failure(code)
      message = I18n.t("chat_bridge.errors.#{code}", default: code.to_s.humanize)
      nonce = ERB::Util.html_escape(csp_nonce)
      html = <<~HTML
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><title>Chat sign in</title></head>
        <body style="font:14px system-ui,sans-serif;padding:2rem;color:#333">
        <p>#{ERB::Util.html_escape(message)}</p>
        <p><button id="close">Close</button></p>
        <script nonce="#{nonce}">
        document.getElementById("close").addEventListener("click", function () { window.close(); });
        </script>
        </body></html>
      HTML
      render html: html.html_safe, content_type: "text/html", status: :forbidden
    end

    def handshake_html(payload, target_origin, nonce)
      safe_nonce = ERB::Util.html_escape(nonce)
      <<~HTML
        <!doctype html>
        <html lang="en">
        <head><meta charset="utf-8"><title>Signing in</title></head>
        <body style="font:14px system-ui,sans-serif;padding:2rem;color:#333">
        <p id="status">Signing you in...</p>
        <script nonce="#{safe_nonce}">
        (function () {
          var payload = #{payload.to_json};
          var target = #{target_origin.to_json};
          var status = document.getElementById("status");

          // The opener is often gone by now: Discourse's login page severs it
          // when the page that opened this one is on another origin. That is
          // expected and harmless, because the widget collects the result by
          // asking the bridge for it. This message is only a nudge to ask now
          // rather than on the next poll.
          try {
            if (window.opener) window.opener.postMessage(payload, target);
          } catch (e) {
            /* nothing to do, the widget is already polling */
          }

          status.textContent = "Signed in. You can close this window.";

          // Try to close regardless. A window opened by script may close itself,
          // though a browser can refuse after a cross origin navigation, which
          // is why the message above is written first.
          setTimeout(function () {
            try { window.close(); } catch (e) {}
            setTimeout(function () {
              status.textContent = "Signed in. You can close this window and return to the page you came from.";
            }, 600);
          }, 400);
        })();
        </script>
        </body>
        </html>
      HTML
    end
  end
end
