# frozen_string_literal: true

module ::ChatBridge
  class Engine < ::Rails::Engine
    engine_name ChatBridge::PLUGIN_NAME
    isolate_namespace ChatBridge
    config.autoload_paths << File.join(config.root, "lib")
  end
end
