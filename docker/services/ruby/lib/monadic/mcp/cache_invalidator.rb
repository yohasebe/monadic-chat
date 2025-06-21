# frozen_string_literal: true

module Monadic
  module MCP
    # Invalidate MCP cache when apps are reloaded
    module CacheInvalidator
      def self.setup
        # Hook into app loading process
        if defined?(::AppLoader)
          ::AppLoader.class_eval do
            alias_method :original_load_apps, :load_apps if method_defined?(:load_apps)
            
            def load_apps
              result = original_load_apps if respond_to?(:original_load_apps)
              
              # Clear MCP cache after apps are loaded
              Monadic::MCP::Server.clear_cache if defined?(Monadic::MCP::Server)
              
              result
            end
          end
        end
      end
    end
  end
end

# Auto-setup when loaded
Monadic::MCP::CacheInvalidator.setup