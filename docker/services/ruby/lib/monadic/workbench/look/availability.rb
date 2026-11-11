# frozen_string_literal: true

require_relative '../../workspace/chats'

module Monadic
  module Workbench
    module Look
      # Whether the model of a request is offered look_at_workbench. Every
      # app declares the tool; a request offers it only when all hold:
      # the provider's helper carries a look's image to the model
      # (TRANSPORTS), the model takes tools and is known to take images
      # (a model whose image input is not known is not offered it), for a
      # reply of a chat. A call of the tool when it was not offered
      # is refused by ToolDispatchGuard, which records the tools after this
      # filter.
      module Availability
        # The providers whose helpers place a look's image in the request.
        TRANSPORTS = %w[openai claude gemini grok mistral cohere deepseek ollama].freeze

        module_function

        # tools, as the provider's request holds them, without the look
        # tool when it is not to be offered.
        def filter(tools, session:, provider:, model:)
          return tools if tools.nil? || offered?(session: session, provider: provider, model: model)

          without_look(tools)
        end

        def offered?(session:, provider:, model:)
          TRANSPORTS.include?(provider.to_s) && chat?(session) && tools?(model) && vision?(provider.to_s, model)
        end

        # A session of a chat: looks go only for a reply of a chat.
        def chat?(session)
          session.respond_to?(:[]) && !session[Monadic::Workspace::Chats::SESSION_KEY].nil?
        end

        def tools?(model)
          defined?(Monadic::Utils::ModelSpec) ? Monadic::Utils::ModelSpec.tool_capability?(model) : false
        end

        # Known to take images: the model list says so (not "unknown, so
        # yes"); for Ollama, the server's own report of the model.
        def vision?(provider, model)
          if provider == 'ollama'
            caps = defined?(OllamaHelper) && OllamaHelper.respond_to?(:fetch_model_capabilities) &&
                   OllamaHelper.fetch_model_capabilities(model)
            return caps.is_a?(Hash) && Array(caps[:capabilities]).include?('vision')
          end
          return false unless defined?(Monadic::Utils::ModelSpec)

          Monadic::Utils::ModelSpec.get_model_property(model, 'vision_capability') == true
        end

        # Every provider's tool shapes: {name:}, {function: {name:}},
        # {type: "function", name:}, and Gemini's {function_declarations:}.
        def without_look(tools)
          return tools unless tools.is_a?(Array)

          tools.filter_map do |entry|
            next entry unless entry.is_a?(Hash)

            decls_key = %w[function_declarations functionDeclarations].find { |k| entry.key?(k) } ||
                        %i[function_declarations functionDeclarations].find { |k| entry.key?(k) }
            if decls_key
              kept = Array(entry[decls_key]).reject { |d| look?(d) }
              next nil if kept.empty?

              entry.merge(decls_key => kept)
            else
              look?(entry) ? nil : entry
            end
          end
        end

        def look?(entry)
          return false unless entry.is_a?(Hash)

          fn = entry['function'] || entry[:function]
          name = (fn.is_a?(Hash) ? (fn['name'] || fn[:name]) : nil) || entry['name'] || entry[:name]
          name.to_s.strip == TOOL
        end
      end
    end
  end
end
