# frozen_string_literal: true

module ChatBridge
  # Cleans the HTML Discourse produces for a chat message before it is sent to
  # another website.
  #
  # Discourse already sanitizes what it stores, so this is a second pass, not the
  # first line of defence. It exists because the output crosses a trust boundary:
  # it leaves the forum and is injected into a page we do not control. A second
  # strict pass costs almost nothing and means one bug in Discourse's own
  # pipeline, or one plugin that widens what is allowed, does not immediately
  # become script execution on someone else's site.
  module Sanitizer
    ALLOWED_TAGS = %w[
      p br span div
      strong b em i u s del ins mark small sub sup
      code pre
      blockquote
      ul ol li
      a img
      audio source
      h1 h2 h3 h4 h5 h6
      table thead tbody tr th td
      hr
    ].freeze

    ALLOWED_ATTRIBUTES = %w[
      href src alt title class width height colspan rowspan
      controls preload type
    ].freeze

    # Nodes whose text content must go with them. The safe list sanitizer strips
    # the tag but keeps what is inside, so "<script>alert(1)</script>" would
    # otherwise survive as the visible text "alert(1)".
    PRUNE_ENTIRELY = %w[script style iframe object embed form input button svg math template noscript].freeze

    ALLOWED_SCHEMES = %w[http https].freeze

    module_function

    # Returns HTML safe to insert into a page on another origin.
    #
    # base_url is the forum's absolute base, used to turn Discourse's relative
    # avatar, emoji and upload paths into absolute ones. Without that the host
    # page would resolve them against its own domain and every image would break.
    def clean(html, base_url:)
      return "" if html.blank?

      fragment = Loofah.html5_fragment(html.to_s)

      fragment.css(PRUNE_ENTIRELY.join(",")).each(&:remove)

      fragment.css("*").each do |node|
        node.attribute_nodes.each do |attr|
          name = attr.name.downcase

          # on* handlers are the classic injection route and must never survive,
          # regardless of what the allow list says.
          attr.remove and next if name.start_with?("on")
          attr.remove and next if !ALLOWED_ATTRIBUTES.include?(name)

          if %w[href src].include?(name)
            resolved = absolutize(attr.value, base_url)
            resolved.nil? ? attr.remove : attr.value = resolved
          end
        end
      end

      cleaned =
        Rails::HTML5::SafeListSanitizer.new.sanitize(
          fragment.to_html,
          tags: ALLOWED_TAGS,
          attributes: ALLOWED_ATTRIBUTES,
        ).to_s

      final = Loofah.html5_fragment(cleaned)

      # An image whose src was refused above would render as a broken image icon,
      # so the element goes with it.
      final.css("img").each { |img| img.remove if img["src"].blank? }

      # Audio always gets controls, because a player with no controls is an
      # invisible element the visitor cannot start. An audio element with no
      # source, its src having been refused above, is removed for the same reason
      # a broken image is.
      final.css("audio").each do |audio|
        audio["controls"] = "controls"
        audio["preload"] = "metadata"
        audio.remove if audio["src"].blank? && audio.css("source[src]").empty?
      end

      # Links leave our control entirely, so they open in a new tab and are told
      # not to leak the opener reference or the referrer. A link whose href was
      # refused is unwrapped, keeping its text but losing the dead anchor.
      final.css("a").each do |a|
        if a["href"].blank?
          a.replace(a.children)
          next
        end
        a["target"] = "_blank"
        a["rel"] = "noopener noreferrer nofollow"
      end

      final.to_html
    end

    # Turns a possibly relative URL into an absolute one on the forum, and
    # returns nil for anything that is not plainly http or https. Returning nil
    # means the attribute is dropped rather than guessed at.
    def absolutize(value, base_url)
      raw = value.to_s.strip
      return nil if raw.empty?

      # Reject anything with a scheme we do not allow, javascript: and data:
      # included. A protocol relative URL is also refused, because its scheme is
      # decided by the host page rather than by us.
      return nil if raw.start_with?("//")

      if raw =~ %r{\A([a-z][a-z0-9+.\-]*):}i
        return ALLOWED_SCHEMES.include?(Regexp.last_match(1).downcase) ? raw : nil
      end

      return nil if !raw.start_with?("/")
      "#{base_url.to_s.chomp("/")}#{raw}"
    end
  end
end
