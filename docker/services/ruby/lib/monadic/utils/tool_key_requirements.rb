# frozen_string_literal: true

module Monadic
  module Utils
    # Tools that call a service other than the app's chat provider, and the
    # config key each one needs. Without the key the tool is not offered to the
    # model at all, so the model cannot pick it or mention it as available.
    module ToolKeyRequirements
      REQUIRED_KEYS = {
        "generate_music_with_elevenlabs" => "ELEVENLABS_API_KEY"
      }.freeze

      module_function

      def available?(tool_name, config = (defined?(CONFIG) ? CONFIG : {}))
        key = REQUIRED_KEYS[tool_name.to_s]
        return true unless key

        !config[key].to_s.strip.empty?
      end

      # Drops the tools whose key is missing. Accepts the shapes the vendor
      # helpers pass around: hashes with "name"/:name, or a nested "function".
      def filter(tools, config = (defined?(CONFIG) ? CONFIG : {}))
        return tools unless tools.is_a?(Array)

        tools.select { |tool| available?(tool_name_of(tool), config) }
      end

      def tool_name_of(tool)
        return nil unless tool.is_a?(Hash)

        tool["name"] || tool[:name] || tool.dig("function", "name") || tool.dig(:function, :name)
      end
    end
  end
end
