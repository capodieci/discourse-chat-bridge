# frozen_string_literal: true

module ChatBridge
  # Unauthenticated liveness check. Reports whether the plugin is installed and
  # whether its prerequisites are met, without revealing anything about the
  # forum, its users, or its configured sites.
  class HealthController < ::ApplicationController
    requires_plugin ChatBridge::PLUGIN_NAME

    skip_before_action :check_xhr, raise: false
    skip_before_action :preload_json, raise: false
    skip_before_action :redirect_to_login_if_required, raise: false
    skip_before_action :redirect_to_profile_if_required, raise: false

    def show
      render json: {
               ok: true,
               data: {
                 plugin: ChatBridge::PLUGIN_NAME,
                 version: "0.1.0",
                 bridge_enabled: SiteSetting.chat_bridge_enabled,
                 chat_enabled: SiteSetting.chat_enabled,
               },
             }
    end
  end
end
