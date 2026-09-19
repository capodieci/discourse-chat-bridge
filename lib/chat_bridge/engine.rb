# frozen_string_literal: true

module ::ChatBridge
  class Engine < ::Rails::Engine
    engine_name ChatBridge::PLUGIN_NAME
    isolate_namespace ChatBridge

    # Deliberately no autoload_paths entry for lib. Everything under lib is
    # required explicitly, and adding it here risks the same file being defined
    # twice, once by the require and once by the autoloader.
  end
end
