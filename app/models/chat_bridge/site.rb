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

    # Every colour an administrator can set. `accent` paints the panel header,
    # the buttons and the links. The two launcher colours paint the round button
    # in the corner and the icon inside it, for a site whose button should stand
    # apart from the panel, or simply match a brand the accent does not.
    COLOUR_KEYS = %w[accent launcher_bg launcher_icon].freeze

    # The languages the widget ships, each named in its own language. The keys
    # are also the names of the files in public/, widget.strings.<code>.json,
    # and must match the LOCALES list in public/widget.js. tests/loadcheck.rb
    # fails when they drift apart.
    LOCALE_NAMES = {
      "en" => "English",
      "zh-CN" => "简体中文",
      "zh-TW" => "繁體中文",
      "ru" => "Русский",
      "it" => "Italiano",
      "es" => "Español",
      "fr" => "Français",
      "ja" => "日本語",
      "ko" => "한국어",
    }.freeze
    LOCALES = LOCALE_NAMES.keys.freeze

    # What a site may store in `theme`. Anything else an admin request carries is
    # dropped rather than saved, so the column cannot become a place to park
    # arbitrary JSON that the widget is later handed.
    THEME_KEYS = (COLOUR_KEYS + %w[position launcher_label locale]).freeze

    validate :theme_must_be_safe

    # Appearance, with defaults filled in, ready to hand to the widget.
    #
    # Every value is validated on the way in rather than trusted on the way out,
    # because `accent` is interpolated into a stylesheet inside the widget's
    # Shadow DOM. Anything looser than an exact hex colour there is a CSS
    # injection, and CSS can read attribute values and make network requests.
    #
    # The same holds for the two launcher colours, and for the same reason.
    #
    # `locale` is nil when the site follows each visitor's browser, which is the
    # default, and a language code when an administrator has fixed one.
    def theme_settings
      raw = theme.is_a?(Hash) ? theme : {}

      colours =
        COLOUR_KEYS.index_with do |key|
          value = raw[key].to_s
          value.match?(HEX_COLOUR) ? value : nil
        end

      position = raw["position"].to_s
      position = nil if !POSITIONS.include?(position)

      label = raw["launcher_label"].to_s.strip
      label = nil if label.empty?

      locale = raw["locale"].to_s
      locale = nil if !LOCALES.include?(locale)

      colours.merge(
        "position" => position || "bottom-right",
        "launcher_label" => label&.first(60),
        "locale" => locale,
      )
    end

    # Turns what an admin form sends into what is stored: known keys only,
    # whitespace trimmed, and blanks removed so that "not set" has one
    # representation rather than a mixture of nil, "" and a missing key.
    # "auto" is how the form says "follow the visitor's browser", which is the
    # absence of a fixed language, so it is stored as nothing at all.
    #
    # It does not judge the values. That is the validation's job, so a bad colour
    # still reaches `theme_must_be_safe` and comes back as a readable error
    # instead of being silently discarded here.
    def self.clean_theme(raw)
      raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      return {} if !raw.is_a?(Hash)

      raw
        .transform_keys(&:to_s)
        .slice(*THEME_KEYS)
        .transform_values { |value| value.to_s.strip }
        .reject { |key, value| value.empty? || (key == "locale" && value == "auto") }
    end

    # The Rails name for one of our language codes, or nil when it is not one of
    # ours. Discourse names its locales zh_CN where browsers say zh-CN. Checked
    # against the list first, so a value from a query string can never reach
    # I18n as an arbitrary symbol.
    def self.i18n_locale(code)
      code = code.to_s
      LOCALES.include?(code) ? code.tr("-", "_").to_sym : nil
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

      colour_names = {
        "accent" => "accent",
        "launcher_bg" => "button background",
        "launcher_icon" => "button icon",
      }
      COLOUR_KEYS.each do |key|
        value = raw[key]
        if value.present? && !value.to_s.match?(HEX_COLOUR)
          errors.add(:theme, "#{colour_names[key]} must be a hex colour such as #0b6ecf")
        end
      end

      position = raw["position"]
      if position.present? && !POSITIONS.include?(position.to_s)
        errors.add(:theme, "position must be one of #{POSITIONS.join(", ")}")
      end

      label = raw["launcher_label"]
      if label.present? && label.to_s.length > 60
        errors.add(:theme, "launcher label must be 60 characters or fewer")
      end

      locale = raw["locale"]
      if locale.present? && !LOCALES.include?(locale.to_s)
        errors.add(:theme, "language must be one of #{LOCALES.join(", ")}")
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
