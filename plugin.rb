# frozen_string_literal: true

# name: discourse-chat-bridge
# about: Embed Discourse chat on any website with a single script tag. Visitors sign in with their forum account.
# version: 0.1.0
# authors: Roberto Capodieci
# url: https://github.com/capodieci/discourse-chat-bridge
# required_version: 2.7.0

enabled_site_setting :chat_bridge_enabled

module ::ChatBridge
  PLUGIN_NAME = "discourse-chat-bridge"

  # Where this plugin was installed. Used to read public/widget.js at request
  # time rather than hardcoding a path that differs between installs.
  def self.plugin_root
    @plugin_root ||= File.expand_path("..", __dir__ + "/plugin.rb")
  end
end

ChatBridge.instance_variable_set(:@plugin_root, File.expand_path(__dir__))

require_relative "lib/chat_bridge/engine"
require_relative "lib/chat_bridge/sanitizer"
require_relative "lib/chat_bridge/presenter"

add_admin_route "chat_bridge.admin.title", "chat-bridge", use_new_show_route: true

after_initialize do
  Discourse::Application.routes.append { mount ::ChatBridge::Engine, at: "/chat-bridge" }

  # Administration lives on the forum's own admin routes rather than inside the
  # engine, so it inherits Discourse's admin constraint and sits where an
  # administrator expects to find it.
  Discourse::Application.routes.append do
    scope "/admin/plugins/chat-bridge", constraints: AdminConstraint.new do
      get "" => "chat_bridge/admin#index", :format => :json
      get "/sites" => "chat_bridge/admin#index", :format => :json
      post "/sites" => "chat_bridge/admin#create", :format => :json
      put "/sites/:id" => "chat_bridge/admin#update", :format => :json
      delete "/sites/:id" => "chat_bridge/admin#destroy", :format => :json
    end
  end

  # The chat plugin must be present and enabled for any of this to mean anything.
  # We check at request time rather than here, because plugin load order is not guaranteed.
end
