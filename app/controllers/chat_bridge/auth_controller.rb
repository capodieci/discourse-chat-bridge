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

    def start
      return render_auth_failure("chat_disabled") if !SiteSetting.chat_bridge_enabled

      site = ChatBridge::Site.find_enabled_by_key(params[:site_key])
      return render_auth_failure("unknown_site") if site.nil?

      # Remember which site and state this attempt belongs to, so the value
      # survives the round trip through the login screen.
      if current_user.nil?
        session[:chat_bridge_site_key] = site.site_key
        session[:chat_bridge_state] = params[:state].to_s.first(128)
        return redirect_to_login
      end

      state = params[:state].presence || session.delete(:chat_bridge_state)
      session.delete(:chat_bridge_site_key)

      nonce = ChatBridge::AuthNonce.issue!(site: site, state: state)
      consumed = ChatBridge::AuthNonce.consume!(nonce.nonce)
      return render_auth_failure("invalid_token") if consumed.nil?

      plain, _record = ChatBridge::Token.issue!(user: current_user, site: site)

      @site = site
      @state = consumed.state
      @token = plain
      @expires_in = SiteSetting.chat_bridge_token_ttl_hours.to_i * 3600
      @can_chat = ::Guardian.new(current_user).can_chat?
      @user_payload = {
        id: current_user.id,
        username: current_user.username,
        name: current_user.name,
        avatar_template: current_user.avatar_template,
        can_chat: @can_chat,
      }

      render_handshake_page
    end

    private

    # Returns a page whose only job is to hand the token to the window that
    # opened it and then close. The postMessage target is the site's registered
    # origin, never "*", so the token cannot be read by any other page even if
    # something unexpected opened this window.
    def render_handshake_page
      payload = {
        type: "chat-bridge-auth",
        state: @state,
        token: @token,
        expires_in: @expires_in,
        user: @user_payload,
      }

      render html: handshake_html(payload, @site.origin).html_safe, content_type: "text/html"
    end

    def render_auth_failure(code)
      message = I18n.t("chat_bridge.errors.#{code}", default: code.to_s.humanize)
      html = <<~HTML
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><title>Chat sign in</title></head>
        <body style="font:14px system-ui,sans-serif;padding:2rem;color:#333">
        <p>#{ERB::Util.html_escape(message)}</p>
        <p><button onclick="window.close()">Close</button></p>
        </body></html>
      HTML
      render html: html.html_safe, content_type: "text/html", status: :forbidden
    end

    def handshake_html(payload, target_origin)
      <<~HTML
        <!doctype html>
        <html lang="en">
        <head><meta charset="utf-8"><title>Signing in</title></head>
        <body style="font:14px system-ui,sans-serif;padding:2rem;color:#333">
        <p>Signed in. You can close this window.</p>
        <script>
        (function () {
          var payload = #{payload.to_json};
          var target = #{target_origin.to_json};
          try {
            if (window.opener) {
              window.opener.postMessage(payload, target);
              window.close();
            } else {
              document.body.innerHTML =
                '<p>Signed in. Please return to the previous tab.</p>';
            }
          } catch (e) {
            document.body.innerHTML = '<p>Signed in, but this window could not talk to the page that opened it. Please close it and try again.</p>';
          }
        })();
        </script>
        </body>
        </html>
      HTML
    end
  end
end
