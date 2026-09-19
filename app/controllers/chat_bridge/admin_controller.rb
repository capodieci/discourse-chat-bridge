# frozen_string_literal: true

module ChatBridge
  # Administration of embedding sites.
  #
  # Inherits Discourse's own admin controller, so login and admin status are
  # enforced by the forum rather than by anything in this plugin. A bridge token
  # is never accepted here: those belong to visitors on other websites, and
  # administration is a forum concern.
  class AdminController < ::Admin::AdminController
    requires_plugin ChatBridge::PLUGIN_NAME

    def index
      render_json_dump(
        sites: ChatBridge::Site.order(:id).map { |site| serialize_site(site) },
        positions: ChatBridge::Site::POSITIONS,
        features: ChatBridge::Site::FEATURE_KEYS,
        widget_url: "#{::Discourse.base_url}/chat-bridge/widget.js",
        cors_origins: SiteSetting.cors_origins.to_s.split("|").map(&:strip).reject(&:empty?),
        bridge_enabled: SiteSetting.chat_bridge_enabled,
        chat_enabled: SiteSetting.chat_enabled,
        channels: available_channels,
        missing_audio_extensions: missing_audio_extensions,
      )
    end

    def create
      site =
        ChatBridge::Site.new(
          name: params[:name].to_s.strip,
          origin: normalised_origin,
          site_key: ChatBridge::Site.generate_site_key,
          enabled: true,
        )
      apply_settings(site)

      return render_site_errors(site) if !site.save

      sync_cors_origin(site.origin, add: true)
      render_json_dump(site: serialize_site(site))
    end

    def update
      site = ChatBridge::Site.find_by(id: params[:id])
      return render_json_error(I18n.t("chat_bridge.errors.unknown_site"), status: 404) if site.nil?

      previous_origin = site.origin
      site.name = params[:name].to_s.strip if params.key?(:name)
      site.origin = normalised_origin if params.key?(:origin)
      site.enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled]) if params.key?(:enabled)
      apply_settings(site)

      return render_site_errors(site) if !site.save

      # An origin that changed, or a site that was switched off, must not be left
      # in the forum's CORS allow list. Leaving it there would keep granting a
      # site access after an administrator believed they had removed it.
      if previous_origin != site.origin
        sync_cors_origin(previous_origin, add: false)
      end
      sync_cors_origin(site.origin, add: site.enabled)

      if !site.enabled
        ChatBridge::Token.where(site_id: site.id, revoked_at: nil).update_all(
          revoked_at: Time.zone.now,
        )
      end

      render_json_dump(site: serialize_site(site))
    end

    def destroy
      site = ChatBridge::Site.find_by(id: params[:id])
      return render_json_error(I18n.t("chat_bridge.errors.unknown_site"), status: 404) if site.nil?

      origin = site.origin
      site.destroy!
      sync_cors_origin(origin, add: false)

      render json: success_json
    end

    private

    def normalised_origin
      # Browsers send an origin with no trailing slash and no path, so that is
      # what is stored. Accepting a pasted URL and tidying it here saves an
      # administrator from a validation error that would look arbitrary.
      raw = params[:origin].to_s.strip
      return raw if raw.empty?

      begin
        uri = URI.parse(raw)
        return raw if uri.scheme.blank? || uri.host.blank?
        port = uri.port && uri.port != uri.default_port ? ":#{uri.port}" : ""
        "#{uri.scheme}://#{uri.host}#{port}"
      rescue URI::InvalidURIError
        raw
      end
    end

    def apply_settings(site)
      if params.key?(:theme)
        theme = params[:theme].respond_to?(:to_unsafe_h) ? params[:theme].to_unsafe_h : params[:theme]
        site.theme = (theme || {}).slice("accent", "position", "launcher_label")
      end

      if params.key?(:features)
        raw =
          params[:features].respond_to?(:to_unsafe_h) ? params[:features].to_unsafe_h : params[:features]
        raw ||= {}
        site.features =
          ChatBridge::Site::FEATURE_KEYS.index_with do |key|
            ActiveModel::Type::Boolean.new.cast(raw[key]) ? true : false
          end
      end

      if params.key?(:allowed_channel_ids)
        ids = Array(params[:allowed_channel_ids]).map(&:to_i).reject(&:zero?)
        site.allowed_channel_ids = ids.presence
      end
    end

    def serialize_site(site)
      {
        id: site.id,
        name: site.name,
        origin: site.origin,
        site_key: site.site_key,
        enabled: site.enabled,
        theme: site.theme_settings,
        features: site.feature_settings,
        allowed_channel_ids: site.allowed_channel_ids,
        active_sessions: ChatBridge::Token.where(site_id: site.id).active.count,
        in_cors_origins: cors_list.include?(site.origin),
        script_tag:
          %(<script src="#{::Discourse.base_url}/chat-bridge/widget.js" ) +
            %(data-site-key="#{site.site_key}" defer></script>),
      }
    end

    # Offered so an administrator can pin a site to one channel without having to
    # look up its id. Only open category channels, because a direct message
    # channel cannot be chosen in advance and a closed one would strand the site.
    def available_channels
      ::Chat::Channel
        .where(chatable_type: "Category", status: "open")
        .order(:id)
        .map { |c| { id: c.id, name: ChatBridge::Presenter.channel_title(c) } }
    rescue StandardError
      []
    end

    # Voice messages upload a recording, and Discourse refuses any extension not
    # in authorized_extensions. Browsers record in different containers, so a
    # forum missing one of these has voice messages that work in some browsers
    # and fail in others, which is a miserable thing to diagnose.
    #
    # Reported rather than fixed. Editing a forum wide upload policy is not a
    # plugin's decision to make on someone else's forum.
    RECORDING_EXTENSIONS = %w[m4a webm ogg].freeze

    def missing_audio_extensions
      allowed =
        SiteSetting.authorized_extensions.to_s.split("|").map { |e| e.strip.downcase }.reject(&:empty?)
      RECORDING_EXTENSIONS.reject { |e| allowed.include?(e) }
    end

    def cors_list
      SiteSetting.cors_origins.to_s.split("|").map(&:strip).reject(&:empty?)
    end

    # Registering a site is meaningless unless its origin is in cors_origins:
    # the browser refuses the connection before the plugin is ever reached.
    # Keeping the two in step here removes a manual step that fails silently.
    def sync_cors_origin(origin, add:)
      return if origin.blank?
      current = cors_list

      if add
        return if current.include?(origin)
        SiteSetting.cors_origins = (current + [origin]).join("|")
      else
        # Another enabled site may share the origin, in which case it stays.
        return if ChatBridge::Site.enabled.where(origin: origin).exists?
        return if !current.include?(origin)
        SiteSetting.cors_origins = (current - [origin]).join("|")
      end
    end

    def render_site_errors(site)
      render_json_error(site.errors.full_messages, status: 422)
    end
  end
end
