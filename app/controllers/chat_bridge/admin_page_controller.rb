# frozen_string_literal: true

module ChatBridge
  # Serves the administration page.
  #
  # Server rendered rather than an Ember page under Admin, Plugins, for a
  # practical reason: plugin JavaScript is compiled into the application bundle
  # when the container is built, so an Ember page would need a full rebuild to
  # appear and another for every change to it. A page served from here deploys
  # with a restart like the rest of the plugin, and cannot break when Discourse
  # changes its admin conventions.
  #
  # It lives at /chat-bridge/admin rather than under /admin/plugins/ because
  # Discourse serves its own single page application for admin paths, and a
  # server rendered page there would be intercepted by it.
  class AdminPageController < ::Admin::AdminController
    requires_plugin ChatBridge::PLUGIN_NAME

    skip_before_action :check_xhr, raise: false
    skip_before_action :preload_json, raise: false

    layout false

    def show
      template = File.read(File.join(ChatBridge.plugin_root, "lib", "chat_bridge", "admin_page.html"))

      # The page's own scripts need the CSP nonce, for the same reason the login
      # handshake does: Discourse serves script-src with a nonce and
      # strict-dynamic, so an unnonced script simply never runs and the page
      # looks broken with nothing in the log to say why.
      nonce = ::ContentSecurityPolicy.nonce_placeholder(response.headers, request_env: request.env)

      html =
        template
          .gsub("__NONCE__", ERB::Util.html_escape(nonce).to_s)
          .gsub("__CSRF__", ERB::Util.html_escape(form_authenticity_token).to_s)
          .gsub("__BASE__", ERB::Util.html_escape(::Discourse.base_url).to_s)

      render html: html.html_safe, content_type: "text/html"
    end
  end
end
