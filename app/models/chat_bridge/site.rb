# frozen_string_literal: true

module ChatBridge
  class Site < ::ActiveRecord::Base
    self.table_name = "chat_bridge_sites"

    has_many :tokens, class_name: "ChatBridge::Token", foreign_key: :site_id, dependent: :destroy

    validates :site_key, presence: true, uniqueness: true
    validates :origin, presence: true, uniqueness: true
    validates :name, presence: true
    validate :origin_must_be_a_bare_https_origin

    scope :enabled, -> { where(enabled: true) }

    POSITIONS = %w[bottom-right bottom-left].freeze
    HEX_COLOUR = /\A#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\z/
    FEATURE_KEYS = %w[direct_messages voice_messages].freeze

    validate :theme_must_be_safe

    # Appearance, with defaults filled in, ready to hand to the widget.
    #
    # Every value is validated on the way in rather than trusted on the way out,
    # because `accent` is interpolated into a stylesheet inside the widget's
    # Shadow DOM. Anything looser than an exact hex colour there is a CSS
    # injection, and CSS can read attribute values and make network requests.
    def theme_settings
      raw = theme.is_a?(Hash) ? theme : {}

      accent = raw["accent"].to_s
      accent = nil if !accent.match?(HEX_COLOUR)

      position = raw["position"].to_s
      position = nil if !POSITIONS.include?(position)

      label = raw["launcher_label"].to_s.strip
      label = nil if label.empty?

      {
        "accent" => accent,
        "position" => position || "bottom-right",
        "launcher_label" => label&.first(60),
      }
    end

    # Behaviour. Both default to on, so a site created before these existed keeps
    # working exactly as it did.
    def feature_settings
      raw = features.is_a?(Hash) ? features : {}
      FEATURE_KEYS.index_with { |key| raw.key?(key) ? !!raw[key] : true }
    end

    def feature?(key)
      feature_settings[key.to_s] == true
    end

    private

    def theme_must_be_safe
      raw = theme
      return if raw.blank?
      return errors.add(:theme, "must be an object") if !raw.is_a?(Hash)

      accent = raw["accent"]
      if accent.present? && !accent.to_s.match?(HEX_COLOUR)
        errors.add(:theme, "accent must be a hex colour such as #0b6ecf")
      end

      position = raw["position"]
      if position.present? && !POSITIONS.include?(position.to_s)
        errors.add(:theme, "position must be one of #{POSITIONS.join(", ")}")
      end

      label = raw["launcher_label"]
      if label.present? && label.to_s.length > 60
        errors.add(:theme, "launcher label must be 60 characters or fewer")
      end
    end

    public

    # Generates a site key that is safe to publish in a script tag. It is an
    # identifier, not a secret: it says which configuration to load, and grants
    # nothing on its own. Permission always comes from the visitor's own login.
    def self.generate_site_key
      SecureRandom.urlsafe_base64(18)
    end

    def self.find_enabled_by_key(site_key)
      return nil if site_key.blank?
      enabled.find_by(site_key: site_key)
    end

    # True when this site is allowed to show the given channel. A null
    # allowed_channel_ids means "anything the visitor can already see", which is
    # the common case. A populated list narrows it further.
    def permits_channel?(channel_id)
      return true if allowed_channel_ids.blank?
      allowed_channel_ids.include?(channel_id.to_i)
    end

    private

    # An origin is scheme plus host plus optional port, and nothing else. A
    # trailing path or a wildcard would make the postMessage target and the CORS
    # comparison unsafe, because both require an exact match.
    def origin_must_be_a_bare_https_origin
      return if origin.blank?

      begin
        uri = URI.parse(origin)
      rescue URI::InvalidURIError
        errors.add(:origin, "is not a valid URL")
        return
      end

      if uri.scheme != "https" && !localhost_origin?(uri)
        errors.add(:origin, "must use https, except for localhost during development")
      end

      errors.add(:origin, "must not contain a path") if uri.path.present? && uri.path != "/"
      errors.add(:origin, "must not contain a query string") if uri.query.present?
      errors.add(:origin, "must not contain a wildcard") if origin.include?("*")
      errors.add(:origin, "must include a host") if uri.host.blank?

      if origin.end_with?("/")
        errors.add(:origin, "must not end with a slash, browsers never send one")
      end
    end

    def localhost_origin?(uri)
      uri.scheme == "http" && %w[localhost 127.0.0.1].include?(uri.host)
    end
  end
end
