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
end

require_relative "lib/chat_bridge/engine"
require_relative "lib/chat_bridge/sanitizer"
require_relative "lib/chat_bridge/presenter"

after_initialize do
  Discourse::Application.routes.append { mount ::ChatBridge::Engine, at: "/chat-bridge" }

  # The chat plugin must be present and enabled for any of this to mean anything.
  # We check at request time rather than here, because plugin load order is not guaranteed.
end
