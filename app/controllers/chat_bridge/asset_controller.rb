# frozen_string_literal: true

module ChatBridge
  # Serves widget.js itself.
  #
  # Discourse serves a plugin's public directory with
  # `Cache-Control: public, max-age=31536000, immutable`, which is correct for
  # fingerprinted assets and badly wrong for a file whose URL must stay stable.
  # Behind a CDN it means a released fix never reaches a single browser: the
  # embedding sites keep running last week's widget for a year, and there is no
  # way to tell from the outside.
  #
  # So the widget is served from here instead, with a short freshness window and
  # an ETag. Integrators keep one unchanging script tag, caches still do their
  # job, and a fix is live everywhere within minutes.
  class AssetController < ::ApplicationController
    requires_plugin ChatBridge::PLUGIN_NAME

    skip_before_action :check_xhr, raise: false
    skip_before_action :preload_json, raise: false
    skip_before_action :verify_authenticity_token, raise: false
    skip_before_action :redirect_to_login_if_required, raise: false
    skip_before_action :redirect_to_profile_if_required, raise: false

    MAX_AGE = 300

    def widget
      serve(File.join(ChatBridge.plugin_root, "public", "widget.js"), "application/javascript")
    end

    def strings
      serve(
        File.join(ChatBridge.plugin_root, "public", "widget.strings.en.json"),
        "application/json",
      )
    end

    private

    def serve(path, content_type)
      return render(plain: "not found", status: :not_found) if !File.exist?(path)

      body = File.read(path)
      tag = %(W/"#{Digest::SHA256.hexdigest(body)[0, 32]}")

      response.headers["Cache-Control"] = "public, max-age=#{MAX_AGE}, must-revalidate"
      response.headers["ETag"] = tag
      # The widget is loaded by other sites by design, so it is readable across
      # origins. It contains no secrets: the site key lives in the host page.
      response.headers["Access-Control-Allow-Origin"] = "*"
      response.headers["X-Content-Type-Options"] = "nosniff"

      if request.headers["If-None-Match"].to_s.include?(tag)
        return head(:not_modified)
      end

      render plain: body, content_type: content_type
    end
  end
end
