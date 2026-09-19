# frozen_string_literal: true

module ChatBridge
  # Starting and collecting a login, without depending on window.opener.
  #
  # These two endpoints are unauthenticated by definition: they are how a visitor
  # who has no token yet gets one. So they inherit the CORS and origin checks
  # from the base controller but skip the bearer token requirement.
  class HandshakeController < ChatBridge::BaseController
    skip_before_action :authenticate_bridge_token

    # Step one. The widget asks to begin, and keeps the returned secret in
    # memory. Only the id goes into the popup URL.
    def begin_handshake
      site = origin_site
      return render_bridge_error("unknown_site", 403) if site.nil?
      return render_bridge_error("site_disabled", 403) if !site.enabled

      rate_limit_anonymous!("handshake_begin", 20, 1.minute)
      return if performed?

      record, secret = ChatBridge::AuthNonce.begin!(site: site, state: params[:state])

      render_bridge_ok(
        handshake_id: record.nonce,
        claim_secret: secret,
        expires_in: SiteSetting.chat_bridge_nonce_ttl_seconds.to_i,
        auth_url:
          "#{::Discourse.base_url}/chat-bridge/auth/start?handshake=#{CGI.escape(record.nonce)}",
      )
    end

    # Step two, polled. Answers "not yet" until the popup has authorised the
    # handshake, then mints the token once and never again.
    def claim
      site = origin_site
      return render_bridge_error("unknown_site", 403) if site.nil?

      rate_limit_anonymous!("handshake_claim", 120, 1.minute)
      return if performed?

      result = ChatBridge::AuthNonce.claim!(params[:handshake_id], params[:claim_secret])

      return render_bridge_ok(status: "pending") if result == :pending
      return render_bridge_error("invalid_token", 403) if result.nil?
      return render_bridge_error("origin_mismatch", 403) if result.site_id != site.id

      user = ::User.find_by(id: result.user_id)
      return render_bridge_error("invalid_token", 403) if user.nil? || !user.active? || user.suspended?

      plain, token = ChatBridge::Token.issue!(user: user, site: site)

      render_bridge_ok(
        status: "ready",
        token: plain,
        expires_at: token.expires_at.iso8601,
        user: ChatBridge::Presenter.user(user).merge(can_chat: ::Guardian.new(user).can_chat?),
      )
    end
  end
end
