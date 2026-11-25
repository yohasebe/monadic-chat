# frozen_string_literal: true

require_relative '../../workspace/chats'
require_relative '../../utils/tool_dispatch_guard'

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

        # A model that takes images and no tools: it cannot look at the work
        # screen itself, so the picture of the item the user chose goes with
        # each message they send instead (Workbench::Picture, unmarked).
        def by_message?(provider:, model:)
          TRANSPORTS.include?(provider.to_s) && vision?(provider.to_s, model) && !tools_for?(provider.to_s, model)
        end

        # A provider's id here (TRANSPORTS) from an app's provider name.
        # An unknown name is none (not the provider names fall back to).
        def transport_of(provider_name)
          name = provider_name.to_s.downcase.gsub(/[\s\-]+/, '')
          known = MonadicDSL::ProviderConfig::PROVIDER_INFO.any? do |key, info|
            key == name || Array(info[:aliases]).include?(name)
          end
          return '' unless known

          MonadicDSL::ProviderConfig.new(name).helper_module.to_s.delete_suffix('Helper').downcase
        rescue StandardError
          ''
        end

        # Whether the model calls tools; for Ollama, the server's own report.
        def tools_for?(provider, model)
          if provider == 'ollama'
            caps = defined?(OllamaHelper) && OllamaHelper.respond_to?(:fetch_model_capabilities) &&
                   OllamaHelper.fetch_model_capabilities(model)
            return caps.is_a?(Hash) && Array(caps[:capabilities]).include?('tools')
          end
          tools?(model)
        end

        # The files a provider is given as they are by a look, at most (the
        # bytes leave room in the request for its base64 and the rest).
        OFFICE_TYPES = %w[application/vnd.openxmlformats-officedocument.wordprocessingml.document
                          application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
                          application/vnd.openxmlformats-officedocument.presentationml.presentation].freeze
        NATIVE_FILES = {
          'claude' => { types: %w[application/pdf], bytes: 20 * 1024 * 1024, pages: 100 },
          'gemini' => { types: %w[application/pdf], bytes: 14 * 1024 * 1024, pages: 1000 },
          'openai' => { types: %w[application/pdf] + OFFICE_TYPES, bytes: 20 * 1024 * 1024, pages: 100 }
        }.freeze

        # Whether a look gives the file as it is: the provider and the model
        # take it (takes_file?), it is within their limits (a PDF's pages
        # too), and the chat hides no words (a file's text is not checked
        # against them).
        def native_file?(session:, provider:, model:, type:, bytes:, pages:)
          limits = NATIVE_FILES[provider.to_s] or return false
          return false unless limits[:types].include?(type) && bytes.to_i.between?(1, limits[:bytes])
          return false if type == 'application/pdf' && !(pages.is_a?(Integer) && pages.between?(1, limits[:pages]))
          return false unless takes_file?(provider.to_s, model, type)

          !hides_words?(session)
        end

        # What the model is said to take (true, not unknown): a PDF where
        # supports_pdf is, or for OpenAI where its file inputs are; an Office
        # document where its file inputs are.
        def takes_file?(provider, model, type)
          return false unless defined?(Monadic::Utils::ModelSpec)

          property = ->(name) { Monadic::Utils::ModelSpec.get_model_property(model, name) == true }
          inputs = provider == 'openai' && property.call('supports_file_inputs')
          type == 'application/pdf' ? property.call('supports_pdf') || inputs : inputs
        end

        def hides_words?(session)
          !Monadic::Utils::Privacy::Outbound.terms_of(session).empty?
        rescue StandardError
          true
        end

        # The provider (its id here) and the model a request of session's
        # reply goes to.
        def request_of(session)
          app = session.respond_to?(:[]) ? session[:parameters]&.dig('app_name') : nil
          settings = defined?(APPS) && app && APPS[app] ? APPS[app].settings : {}
          provider = transport_of(settings['provider'] || settings[:provider])
          model = Monadic::Workspace::RequestContext.current&.settings&.model
          model ||= session[:parameters]&.dig('model') if session.respond_to?(:[])
          [provider, model]
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
          Monadic::Utils::ToolDispatchGuard.without(tools, [TOOL])
        end
      end
    end
  end
end
