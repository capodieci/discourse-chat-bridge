# frozen_string_literal: true

module ChatBridge
  # Base for every JSON endpoint the widget calls.
  #
  # These requests arrive from another website, carry no cookies, and identify
  # themselves with a bearer token. That shapes everything below: we opt out of
  # the forum's cookie and CSRF machinery because there is no cookie to protect,
  # and we do our own origin checking because the browser's own protection does
  # not apply to a request that carries no credentials.
  class BaseController < ::ApplicationController
    requires_plugin ChatBridge::PLUGIN_NAME

    skip_before_action :check_xhr, raise: false
    skip_before_action :preload_json, raise: false
    skip_before_action :verify_authenticity_token, raise: false
    skip_before_action :redirect_to_login_if_required, raise: false
    skip_before_action :redirect_to_profile_if_required, raise: false

    before_action :apply_cors_headers
    before_action :answer_preflight
    before_action :ensure_plugin_and_chat_enabled
    before_action :authenticate_bridge_token

    attr_reader :bridge_site, :bridge_user, :bridge_token

    private

    # The site this request claims to come from, resolved from the Origin header
    # alone. We never take the site key from the body for this purpose, because
    # the body is attacker controlled and the Origin header is not.
    def origin_site
      return @origin_site if defined?(@origin_site)
      origin = request.headers["Origin"]
      @origin_site = origin.present? ? ChatBridge::Site.enabled.find_by(origin: origin) : nil
    end

    # Reflect the origin only when it exactly matches a registered, enabled site.
    # Vary: Origin is required, otherwise a cache can serve one site's headers to
    # another. Credentials are never allowed: the widget authenticates with a
    # bearer token, so permitting cookies would add risk and buy nothing.
    def apply_cors_headers
      response.headers["Vary"] = [response.headers["Vary"], "Origin"].compact.join(", ")

      return if origin_site.nil?

      response.headers["Access-Control-Allow-Origin"] = origin_site.origin
      response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
      response.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
      response.headers["Access-Control-Max-Age"] = "7200"
    end

    def answer_preflight
      return unless request.request_method == "OPTIONS"
      head(origin_site.nil? ? 403 : 200)
    end

    def ensure_plugin_and_chat_enabled
      return render_bridge_error("chat_disabled", 503) if !SiteSetting.chat_bridge_enabled
      return render_bridge_error("chat_disabled", 503) if !SiteSetting.chat_enabled
    end

    def authenticate_bridge_token
      header = request.headers["Authorization"].to_s
      plain = header.start_with?("Bearer ") ? header.delete_prefix("Bearer ") : nil

      token = ChatBridge::Token.authenticate(plain)
      return render_bridge_error("invalid_token", 401) if token.nil?

      # A token is bound to the site it was issued for. Presenting a valid token
      # from a different registered site is rejected, so one embedding site
      # cannot borrow another's sessions.
      if origin_site.nil? || token.site_id != origin_site.id
        return render_bridge_error("origin_mismatch", 403)
      end

      user = token.user
      return render_bridge_error("invalid_token", 401) if user.nil? || !user.active? || user.suspended?

      @bridge_token = token
      @bridge_site = origin_site
      @bridge_user = user
      token.touch_last_seen!
    end

    def bridge_guardian
      @bridge_guardian ||= ::Guardian.new(bridge_user)
    end

    # Discourse decides whether this user may use chat at all. On a default
    # install that means trust level 1 and above, so a brand new account will be
    # told no here. That is the forum's policy, not ours, and we surface it
    # plainly rather than failing in a way the widget cannot explain.
    def ensure_can_chat
      return if bridge_guardian.can_chat?
      render_bridge_error("not_allowed", 403)
    end

    # Resolves a channel id from the client and refuses it unless Discourse says
    # this user may see it AND the embedding site is allowed to show it. Channel
    # ids arriving from a browser are never trusted, so both checks run on every
    # request rather than being cached per session.
    #
    # Renders the error and returns nil on refusal, so callers guard with
    # `return if channel.nil?`. The same "not found" answer is used for a channel
    # that does not exist and one the user may not see, so the endpoint cannot be
    # used to discover which private channels exist.
    def authorized_channel(channel_id)
      if channel_id.to_i <= 0
        render_bridge_error("unknown_channel", 404)
        return nil
      end

      channel = ::Chat::Channel.find_by(id: channel_id.to_i)

      if channel.nil? || !bridge_guardian.can_preview_chat_channel?(channel)
        render_bridge_error("unknown_channel", 404)
        return nil
      end

      if !bridge_site.permits_channel?(channel.id)
        render_bridge_error("unknown_channel", 404)
        return nil
      end

      channel
    end

    # For endpoints that run before anyone is authenticated, so there is no user
    # to attribute the limit to. Keyed by address instead.
    def rate_limit_anonymous!(key, max, period)
      RateLimiter.new(nil, "chat_bridge_#{key}_#{request.ip}", max, period).performed!
    rescue RateLimiter::LimitExceeded
      render_bridge_error("rate_limited", 429)
    end

    def rate_limit_bridge!(key, max, period)
      RateLimiter.new(bridge_user, "chat_bridge_#{key}", max, period).performed!
    rescue RateLimiter::LimitExceeded
      render_bridge_error("rate_limited", 429)
    end

    def render_bridge_ok(data = {})
      render json: { ok: true, data: data }
    end

    def render_bridge_error(code, status, detail: nil)
      error = {
        code: code,
        message: I18n.t("chat_bridge.errors.#{code}", default: code.to_s.humanize),
      }
      # Discourse's own rejection reason, when there is one, is more useful than
      # our generic sentence. Passed through rather than swallowed.
      error[:detail] = detail if detail.present?

      render json: { ok: false, error: error }, status: status
    end
  end
end
