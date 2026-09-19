# frozen_string_literal: true

module ChatBridge
  class SessionController < ChatBridge::BaseController
    def me
      render_bridge_ok(
        user: ChatBridge::Presenter.user(bridge_user).merge(can_chat: bridge_guardian.can_chat?),
        site: {
          name: bridge_site.name,
          theme: bridge_site.theme_settings,
          features: bridge_site.feature_settings,
        },
        expires_at: bridge_token.expires_at.iso8601,
      )
    end

    def logout
      bridge_token.revoke!
      render_bridge_ok(revoked: true)
    end
  end
end
