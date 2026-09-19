# frozen_string_literal: true

# Self checks for the security critical parts of the chat bridge.
#
# Run inside the Discourse container:
#
#   docker exec app rails runner /var/www/discourse/plugins/discourse-chat-bridge/tests/checks.rb
#
# Written as a plain script rather than RSpec on purpose. These need to be
# runnable against a real installation, including a production one, where no
# test database exists. Everything that touches the database runs inside a
# transaction that is always rolled back, so running this changes nothing.

module ChatBridgeChecks
  @passed = 0
  @failed = []

  class << self
    attr_reader :passed, :failed

    def check(name)
      result = yield
      if result == true
        @passed += 1
      else
        @failed << "#{name}\n      #{result}"
      end
    rescue StandardError => e
      @failed << "#{name}\n      raised #{e.class}: #{e.message}"
    end

    def eq(actual, expected)
      actual == expected ? true : "expected #{expected.inspect}, got #{actual.inspect}"
    end

    def includes(haystack, needle)
      haystack.to_s.include?(needle) ? true : "expected to find #{needle.inspect} in #{haystack.inspect}"
    end

    def excludes(haystack, needle)
      !haystack.to_s.include?(needle) ? true : "expected NOT to find #{needle.inspect} in #{haystack.inspect}"
    end
  end
end

C = ChatBridgeChecks
BASE = Discourse.base_url

puts "Chat bridge self checks"
puts "base url: #{BASE}"
puts

# ---------------------------------------------------------------- sanitizer
#
# This is the boundary where forum content enters a page we do not control, so
# it gets the most attention.

san = ->(html) { ChatBridge::Sanitizer.clean(html, base_url: BASE) }

C.check("script tags are removed entirely, including their text") do
  out = san.call("<p>before</p><script>alert(1)</script><p>after</p>")
  C.excludes(out, "alert") == true ? C.includes(out, "before") : C.excludes(out, "alert")
end

C.check("event handler attributes are stripped") do
  C.excludes(san.call('<div onclick="steal()">x</div>'), "onclick")
end

C.check("uppercase and mixed case event handlers are stripped too") do
  C.excludes(san.call('<div OnClick="steal()" ONMOUSEOVER="x">y</div>').downcase, "onclick")
end

C.check("javascript: urls are refused and the link unwrapped") do
  out = san.call('<a href="javascript:alert(1)">text</a>')
  C.excludes(out, "javascript") == true ? C.includes(out, "text") : C.excludes(out, "javascript")
end

C.check("data: urls are refused") do
  C.excludes(san.call('<a href="data:text/html,<b>x</b>">t</a>'), "data:")
end

C.check("protocol relative urls are refused, the scheme is not ours to choose") do
  C.excludes(san.call('<img src="//evil.test/a.png">'), "evil.test")
end

C.check("an image whose src was refused is removed, not left broken") do
  C.excludes(san.call('<img src="//evil.test/a.png">'), "<img")
end

C.check("relative urls become absolute on the forum") do
  C.includes(san.call('<img src="/uploads/a.png">'), "#{BASE}/uploads/a.png")
end

C.check("absolute forum urls are left alone") do
  C.includes(san.call(%(<a href="#{BASE}/t/x/1">t</a>)), "#{BASE}/t/x/1")
end

C.check("iframes are removed") do
  C.excludes(san.call('<iframe src="https://evil.test"></iframe>'), "iframe")
end

C.check("form and input elements are removed") do
  C.excludes(san.call('<form><input name="password"></form>'), "input")
end

C.check("svg is removed, it can carry script") do
  C.excludes(san.call('<svg><script>alert(1)</script></svg>'), "svg")
end

C.check("outgoing links get noopener and noreferrer") do
  out = san.call('<a href="https://example.com">x</a>')
  C.includes(out, "noopener") == true ? C.includes(out, "noreferrer") : C.includes(out, "noopener")
end

C.check("legitimate mentions survive with their class") do
  out = san.call('<a class="mention" href="/u/rob">@rob</a>')
  C.includes(out, 'class="mention"') == true ? C.includes(out, "#{BASE}/u/rob") : C.includes(out, 'class="mention"')
end

C.check("emoji images survive") do
  out = san.call('<img src="/images/emoji/x.png" class="emoji" alt=":x:">')
  C.includes(out, "emoji")
end

C.check("code blocks and quotes survive") do
  out = san.call("<pre><code>x = 1</code></pre><blockquote><p>q</p></blockquote>")
  C.includes(out, "<pre>") == true ? C.includes(out, "blockquote") : C.includes(out, "<pre>")
end

C.check("blank input is handled") { C.eq(san.call(nil), "") }

C.check("unknown schemes are refused") do
  C.excludes(san.call('<a href="vbscript:msgbox(1)">x</a>'), "vbscript")
end

# --------------------------------------------------------- origin validation

C.check("an exact https origin is accepted") do
  s = ChatBridge::Site.new(name: "n", origin: "https://check-only.invalid", site_key: "k")
  C.eq(s.valid?, true) == true ? true : s.errors.full_messages.join(", ")
end

C.check("a wildcard origin is refused") do
  C.eq(ChatBridge::Site.new(name: "n", origin: "https://*.example.com", site_key: "k").valid?, false)
end

C.check("a trailing slash is refused, browsers never send one") do
  C.eq(ChatBridge::Site.new(name: "n", origin: "https://example.com/", site_key: "k").valid?, false)
end

C.check("an origin with a path is refused") do
  C.eq(ChatBridge::Site.new(name: "n", origin: "https://example.com/app", site_key: "k").valid?, false)
end

C.check("plain http is refused for a public host") do
  C.eq(ChatBridge::Site.new(name: "n", origin: "http://example.com", site_key: "k").valid?, false)
end

C.check("plain http is allowed for localhost, for development") do
  # A port no one would really serve on, because a port that someone might
  # actually have registered would make this check fail on uniqueness and look
  # like a validation bug. That happened.
  s = ChatBridge::Site.new(name: "n", origin: "http://localhost:59997", site_key: "k")
  C.eq(s.valid?, true) == true ? true : s.errors.full_messages.join(", ")
end

# ------------------------------------------------------- appearance and toggles

C.check("a valid hex accent is accepted, both short and long form") do
  ok6 = ChatBridge::Site.new(name: "n", origin: "https://a.invalid", site_key: "k1", theme: { "accent" => "#0b6ecf" }).valid?
  ok3 = ChatBridge::Site.new(name: "n", origin: "https://b.invalid", site_key: "k2", theme: { "accent" => "#abc" }).valid?
  C.eq(ok6 && ok3, true)
end

C.check("an accent that is not a hex colour is refused, because it reaches a stylesheet") do
  bad = ["red", "#12345", "url(x)", "#0b6ecf; background:url(//evil)", "rgb(1,2,3)", "expression(alert(1))"]
  offenders =
    bad.reject do |value|
      !ChatBridge::Site.new(name: "n", origin: "https://c.invalid", site_key: "k3", theme: { "accent" => value }).valid?
    end
  offenders.empty? ? true : "accepted: #{offenders.inspect}"
end

C.check("position must be one of the two corners") do
  good = ChatBridge::Site.new(name: "n", origin: "https://d.invalid", site_key: "k4", theme: { "position" => "bottom-left" }).valid?
  bad = ChatBridge::Site.new(name: "n", origin: "https://e.invalid", site_key: "k5", theme: { "position" => "middle" }).valid?
  C.eq(good && !bad, true)
end

C.check("an over long launcher label is refused") do
  C.eq(ChatBridge::Site.new(name: "n", origin: "https://f.invalid", site_key: "k6", theme: { "launcher_label" => "x" * 61 }).valid?, false)
end

C.check("theme_settings fills in defaults and drops anything invalid") do
  site = ChatBridge::Site.new(theme: { "accent" => "nonsense", "position" => "nonsense" })
  out = site.theme_settings
  C.eq([out["accent"], out["position"]], [nil, "bottom-right"])
end

C.check("features default to on, so sites created before they existed still work") do
  out = ChatBridge::Site.new(features: nil).feature_settings
  C.eq([out["direct_messages"], out["voice_messages"]], [true, true])
end

C.check("a feature can be turned off") do
  site = ChatBridge::Site.new(features: { "voice_messages" => false })
  C.eq([site.feature?("voice_messages"), site.feature?("direct_messages")], [false, true])
end

C.check("channel permission defaults to everything the visitor can see") do
  C.eq(ChatBridge::Site.new(allowed_channel_ids: nil).permits_channel?(7), true)
end

C.check("an explicit channel list narrows access") do
  s = ChatBridge::Site.new(allowed_channel_ids: [1, 2])
  C.eq(s.permits_channel?(3), false) == true ? C.eq(s.permits_channel?(2), true) : C.eq(s.permits_channel?(3), false)
end

# ------------------------------------------------------------------- tokens
#
# Everything below writes, so it runs in a transaction that always rolls back.

ActiveRecord::Base.transaction do
  site = ChatBridge::Site.create!(name: "check", origin: "https://checks.invalid", site_key: SecureRandom.hex(8))
  other = ChatBridge::Site.create!(name: "other", origin: "https://other.invalid", site_key: SecureRandom.hex(8))
  user = User.where("id > 0").order(:id).first

  plain, record = ChatBridge::Token.issue!(user: user, site: site)

  C.check("the plain token is never stored") do
    C.eq(ChatBridge::Token.where(token_hash: plain).exists?, false)
  end

  C.check("only the hash is stored") do
    C.eq(record.token_hash, Digest::SHA256.hexdigest(plain))
  end

  C.check("a valid token authenticates") do
    C.eq(ChatBridge::Token.authenticate(plain)&.id, record.id)
  end

  C.check("a wrong token does not authenticate") do
    C.eq(ChatBridge::Token.authenticate("not-a-real-token"), nil)
  end

  C.check("a blank token does not authenticate") do
    C.eq(ChatBridge::Token.authenticate(""), nil)
  end

  C.check("a revoked token stops working") do
    record.revoke!
    C.eq(ChatBridge::Token.authenticate(plain), nil)
  end

  C.check("an expired token stops working") do
    p2, r2 = ChatBridge::Token.issue!(user: user, site: site)
    r2.update_column(:expires_at, 1.hour.ago)
    C.eq(ChatBridge::Token.authenticate(p2), nil)
  end

  C.check("a token knows which site it belongs to, so origins cannot be crossed") do
    p3, r3 = ChatBridge::Token.issue!(user: user, site: site)
    C.eq(r3.site_id == site.id && r3.site_id != other.id, true)
  end

  # ---------------------------------------------------------- login handshake
  #
  # The popup cannot always reach the window that opened it, so the widget
  # collects its token by asking. These check that asking is safe.

  record, secret = ChatBridge::AuthNonce.begin!(site: site, state: "abc")

  C.check("a handshake starts unauthorised, so claiming it early gets nothing") do
    C.eq(ChatBridge::AuthNonce.claim!(record.nonce, secret), :pending)
  end

  C.check("the claim secret is stored only as a hash") do
    C.eq(ChatBridge::AuthNonce.where(claim_secret_hash: secret).exists?, false)
  end

  C.check("a wrong secret is refused even once authorised") do
    ChatBridge::AuthNonce.authorize!(record.nonce, user.id)
    C.eq(ChatBridge::AuthNonce.claim!(record.nonce, "wrong-secret"), nil)
  end

  C.check("the right secret claims it once authorised") do
    C.eq(ChatBridge::AuthNonce.claim!(record.nonce, secret)&.user_id, user.id)
  end

  C.check("the same handshake cannot be claimed twice") do
    C.eq(ChatBridge::AuthNonce.claim!(record.nonce, secret), nil)
  end

  C.check("an unknown handshake id is refused") do
    C.eq(ChatBridge::AuthNonce.claim!("nope", secret), nil)
  end

  C.check("an expired handshake is refused") do
    old, old_secret = ChatBridge::AuthNonce.begin!(site: site, state: "s")
    ChatBridge::AuthNonce.authorize!(old.nonce, user.id)
    old.update_column(:created_at, 1.hour.ago)
    C.eq(ChatBridge::AuthNonce.claim!(old.nonce, old_secret), nil)
  end

  C.check("an expired handshake cannot even be authorised") do
    old, _ = ChatBridge::AuthNonce.begin!(site: site, state: "s")
    old.update_column(:created_at, 1.hour.ago)
    C.eq(ChatBridge::AuthNonce.authorize!(old.nonce, user.id), nil)
  end

  C.check("a handshake records which site it belongs to") do
    r2, _ = ChatBridge::AuthNonce.begin!(site: other, state: "x")
    C.eq(r2.site_id, other.id)
  end

  raise ActiveRecord::Rollback
end

C.check("the transaction rolled back, nothing was left behind") do
  C.eq(ChatBridge::Site.where(origin: "https://checks.invalid").exists?, false)
end

# ------------------------------------------------- integration with discourse
#
# These exist because of a real bug. The sanitizer and origin checks above are
# pure functions and were all passing while /channels/list returned a 500, for
# the simple reason that nothing here had ever handed the presenter a real
# Discourse object. The presenter asked a membership record for unread_count,
# which is not a method it has. Everything below touches the live objects.

real_user = User.where("id > 0").order(:id).first
real_guardian = Guardian.new(real_user)

C.check("ListUserChannels still returns the keys the controller reads") do
  st = ::Chat::ListUserChannels.call(guardian: real_guardian).structured
  missing = %i[public_channels direct_message_channels memberships tracking].reject { |k| st.key?(k) }
  missing.empty? ? true : "missing keys: #{missing.inspect}"
end

C.check("the tracking report still exposes channel_tracking with unread_count") do
  report = ::Chat::ListUserChannels.call(guardian: real_guardian).structured[:tracking]
  return "no tracking report" if report.nil?
  return "no channel_tracking method" if !report.respond_to?(:channel_tracking)
  entry = report.channel_tracking.values.first
  entry.nil? || entry.key?(:unread_count) ? true : "entry has no unread_count: #{entry.inspect}"
end

C.check("Presenter.channel works on a real channel and real membership") do
  st = ::Chat::ListUserChannels.call(guardian: real_guardian).structured
  channel = Array(st[:public_channels]).first
  next true if channel.nil?

  membership = Array(st[:memberships]).index_by(&:chat_channel_id)[channel.id]
  tracking = st[:tracking].respond_to?(:channel_tracking) ? st[:tracking].channel_tracking[channel.id] : nil
  out = ChatBridge::Presenter.channel(channel, membership: membership, tracking: tracking)

  required = %i[id title slug kind status last_message_id unread_count mention_count muted]
  missing = required.reject { |k| out.key?(k) }
  missing.empty? ? true : "missing keys: #{missing.inspect}"
end

C.check("Presenter.message works on a real message") do
  r = ::Chat::ListChannelMessages.call(
    params: { channel_id: Array(::Chat::Channel.all).first&.id, page_size: 1 },
    guardian: real_guardian,
    options: { max_page_size: 50 },
  )
  next true if !r.success? || Array(r.messages).empty?

  record = Array(r.messages).first
  out = ChatBridge::Presenter.message(record, edited: false)
  required = %i[id channel_id user html created_at edited deleted]
  missing = required.reject { |k| out.key?(k) }
  missing.empty? ? true : "missing keys: #{missing.inspect}"
end

C.check("Presenter.user produces avatar_url, not a raw template") do
  out = ChatBridge::Presenter.user(real_user)
  next "no avatar_url key" if !out.key?(:avatar_url)
  next true if out[:avatar_url].nil?
  out[:avatar_url].start_with?("http") ? true : "not absolute: #{out[:avatar_url].inspect}"
end

C.check("the chat service objects the controllers call all still exist") do
  missing =
    %w[
      Chat::ListUserChannels
      Chat::ListChannelMessages
      Chat::CreateMessage
      Chat::UpdateUserChannelLastRead
      Chat::UserChatChannelMembership
      Chat::MessageRevision
    ].reject { |c| Object.const_defined?(c) }
  missing.empty? ? true : "missing: #{missing.inspect}"
end

# ------------------------------------------------------------------ results

puts "passed: #{C.passed}"
if C.failed.empty?
  puts "failed: 0"
  puts
  puts "All checks passed."
else
  puts "failed: #{C.failed.size}"
  puts
  C.failed.each_with_index { |f, i| puts "  #{i + 1}. #{f}" }
  exit 1
end
