# frozen_string_literal: true

# Administration for the chat bridge. Run inside the Discourse container:
#
#   cd /var/discourse && ./launcher enter app
#   rake chat_bridge:site:add[Marketing,https://zoobc.com]
#   rake chat_bridge:site:list
#
# Site keys are printed in full. They are identifiers, not secrets: a site key
# says which configuration to load and grants nothing on its own.
#
# The guard below is load bearing. Discourse adds every plugin's lib/tasks
# directory with Rake.add_rakelib, and Rails::Engine loads the same directory
# through its own rake_tasks hook, so this file is read twice. Rake appends
# actions to an existing task rather than replacing it, so without this guard
# every task body would run twice per invocation: site:add would create a row
# and then report it as a duplicate.
if !defined?(CHAT_BRIDGE_RAKE_TASKS_DEFINED)
  CHAT_BRIDGE_RAKE_TASKS_DEFINED = true

  desc "List every website registered to embed the chat widget"
  task "chat_bridge:site:list" => :environment do
    sites = ChatBridge::Site.order(:id)

    if sites.empty?
      puts "No sites registered. Add one with rake chat_bridge:site:add[Name,https://example.com]"
      next
    end

    sites.each do |site|
      status = site.enabled ? "enabled" : "disabled"
      channels = site.allowed_channel_ids.presence&.join(",") || "all the visitor can see"
      puts "##{site.id}  #{site.name}"
      puts "    origin   #{site.origin}"
      puts "    key      #{site.site_key}"
      puts "    status   #{status}"
      puts "    channels #{channels}"
      puts "    sessions #{site.tokens.active.count} active"
      puts
    end
  end

  desc "Register a website to embed the chat widget: rake chat_bridge:site:add[Name,https://example.com]"
  task "chat_bridge:site:add", %i[name origin] => :environment do |_task, args|
    if args[:name].blank? || args[:origin].blank?
      abort "Usage: rake chat_bridge:site:add[Name,https://example.com]"
    end

    site =
      ChatBridge::Site.new(
        name: args[:name],
        origin: args[:origin].strip,
        site_key: ChatBridge::Site.generate_site_key,
        enabled: true,
      )

    if !site.save
      abort "Could not add the site:\n  #{site.errors.full_messages.join("\n  ")}"
    end

    puts "Added #{site.name} (#{site.origin})"
    puts
    puts "Add this to that website, once, before the closing body tag:"
    puts
    puts %(  <script src="#{Discourse.base_url}/plugins/discourse-chat-bridge/widget.js")
    puts %(          data-site-key="#{site.site_key}" defer></script>)
    puts
    puts "Then add #{site.origin} to the cors_origins site setting, or the browser will"
    puts "refuse the connection. Admin, Settings, search for cors_origins."
  end

  desc "Disable a registered website: rake chat_bridge:site:disable[site_key]"
  task "chat_bridge:site:disable", [:site_key] => :environment do |_task, args|
    site = ChatBridge::Site.find_by(site_key: args[:site_key])
    abort "No site with that key." if site.nil?

    site.update!(enabled: false)
    revoked = ChatBridge::Token.where(site_id: site.id, revoked_at: nil).update_all(revoked_at: Time.zone.now)

    puts "Disabled #{site.name} (#{site.origin}) and revoked #{revoked} active session(s)."
    puts "Remember to remove #{site.origin} from the cors_origins site setting as well."
  end

  desc "Re-enable a registered website: rake chat_bridge:site:enable[site_key]"
  task "chat_bridge:site:enable", [:site_key] => :environment do |_task, args|
    site = ChatBridge::Site.find_by(site_key: args[:site_key])
    abort "No site with that key." if site.nil?

    site.update!(enabled: true)
    puts "Enabled #{site.name} (#{site.origin})."
  end

  desc "Revoke every widget session for one forum user: rake chat_bridge:user:revoke[username]"
  task "chat_bridge:user:revoke", [:username] => :environment do |_task, args|
    user = User.find_by_username(args[:username])
    abort "No user with that username." if user.nil?

    count = ChatBridge::Token.revoke_all_for_user!(user.id)
    puts "Revoked #{count} widget session(s) for #{user.username}."
  end

  desc "Delete expired tokens and used login nonces"
  task "chat_bridge:prune" => :environment do
    tokens = ChatBridge::Token.prune!
    nonces = ChatBridge::AuthNonce.prune!
    puts "Pruned #{tokens} expired token(s) and #{nonces} old nonce(s)."
  end
end
