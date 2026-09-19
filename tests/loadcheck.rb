# Pre-flight check for the chat bridge plugin.
#
#   docker exec app rails runner \
#     /var/www/discourse/plugins/discourse-chat-bridge/tests/loadcheck.rb
#
# Catches the failures a syntax check cannot: missing constants, bad require
# paths, a route pointing at an action that does not exist, an error code with no
# translation, and Discourse internals that moved between versions. Read only.
#
# Worth running after any Discourse upgrade. This plugin calls chat service
# objects and guardian methods that are not public API, so an upgrade can move
# them, and this says so in seconds rather than at the first request.
DIR = File.expand_path("..", __dir__)
errors = []

def try(label, errors)
  yield
  puts "  ok    #{label}"
rescue Exception => e
  puts "  FAIL  #{label}"
  puts "          #{e.class}: #{e.message}"
  puts "          #{e.backtrace.first}" if e.backtrace
  errors << label
end

puts "1. plugin.rb metadata header"
header = File.read("#{DIR}/plugin.rb").lines.first(10).join
%w[name: about: version: authors: url:].each do |k|
  puts(header.include?(k) ? "  ok    #{k} present" : "  FAIL  #{k} missing")
  errors << k unless header.include?(k)
end

puts "\n2. explicit requires from plugin.rb"
try("lib/chat_bridge/engine.rb", errors) { require "#{DIR}/lib/chat_bridge/engine.rb" } if !defined?(ChatBridge::Engine)
try("lib/chat_bridge/sanitizer.rb", errors) { load "#{DIR}/lib/chat_bridge/sanitizer.rb" }
try("lib/chat_bridge/presenter.rb", errors) { load "#{DIR}/lib/chat_bridge/presenter.rb" }

puts "\n3. constants the controllers depend on resolve"
{
  "ChatBridge::Sanitizer"            => -> { ChatBridge::Sanitizer },
  "ChatBridge::Presenter"            => -> { ChatBridge::Presenter },
  "Chat::ListUserChannels"           => -> { ::Chat::ListUserChannels },
  "Chat::ListChannelMessages"        => -> { ::Chat::ListChannelMessages },
  "Chat::CreateMessage"              => -> { ::Chat::CreateMessage },
  "Chat::UpdateUserChannelLastRead"  => -> { ::Chat::UpdateUserChannelLastRead },
  "Chat::UserChatChannelMembership"  => -> { ::Chat::UserChatChannelMembership },
  "Chat::MessageRevision"            => -> { ::Chat::MessageRevision },
  "Chat::Channel"                    => -> { ::Chat::Channel },
  "Rails::HTML5::SafeListSanitizer"  => -> { Rails::HTML5::SafeListSanitizer },
  "Loofah"                           => -> { Loofah },
}.each { |label, fn| try(label, errors) { fn.call } }

puts "\n4. guardian methods the controllers call exist"
g = Guardian.new(User.where("id > 0").order(:id).first)
%i[can_chat? can_preview_chat_channel?].each do |m|
  ok = g.respond_to?(m)
  puts(ok ? "  ok    Guardian##{m}" : "  FAIL  Guardian##{m} missing")
  errors << m.to_s unless ok
end

puts "\n5. routes file evaluates"
try("config/routes.rb parses as ruby", errors) { RubyVM::InstructionSequence.compile(File.read("#{DIR}/config/routes.rb")) }

puts "\n6. every route target maps to a real controller action"
routes = File.read("#{DIR}/config/routes.rb")
pairs = routes.scan(/=> "([a-z_]+)#([a-z_]+)"/)
controllers = {}
Dir["#{DIR}/app/controllers/chat_bridge/*.rb"].each do |f|
  src = File.read(f)
  name = File.basename(f, ".rb").sub(/_controller$/, "")
  controllers[name] = src.scan(/^\s{4}def ([a-z_]+)/).flatten
end
pairs.each do |ctrl, action|
  defined_here = controllers[ctrl] || []
  ok = defined_here.include?(action)
  puts(ok ? "  ok    #{ctrl}##{action}" : "  FAIL  #{ctrl}##{action} not found (has: #{defined_here.join(", ")})")
  errors << "#{ctrl}##{action}" unless ok
end

puts "\n7. locale keys used by the controllers all exist"
locale = YAML.safe_load(File.read("#{DIR}/config/locales/server.en.yml"))["en"]["chat_bridge"]["errors"]
used = Dir["#{DIR}/app/controllers/chat_bridge/*.rb"].flat_map { |f| File.read(f).scan(/render_bridge_error\("([a-z_]+)"/) }.flatten.uniq
used.each do |k|
  ok = locale.key?(k)
  puts(ok ? "  ok    #{k}" : "  FAIL  #{k} has no translation")
  errors << k unless ok
end

puts "\n" + (errors.empty? ? "LOAD DRY RUN CLEAN" : "PROBLEMS: #{errors.uniq.join(", ")}")
