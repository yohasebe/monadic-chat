# frozen_string_literal: true

require_relative 'base'

module Monadic
  module Library
    module Importers
      # Importer for Monadic Chat's own session export format. The legacy
      # frontend export looks like:
      #   {
      #     "parameters": { "app_name": "ChatOpenAI", "model": "gpt-5.4", ... },
      #     "messages":   [ { "role": "user|assistant|system", "text": "...",
      #                       "mid": "...", "thinking": null, "images": null,
      #                       ... }, ... ]
      #   }
      # We preserve mid as the message id, capture provider/model where
      # available, and route thinking / images / tool_calls into
      # message metadata so nothing useful is lost on round-trip.
      module MonadicChatExport
        module_function

        ROLE_MAP = {
          'user' => 'human',
          'assistant' => 'assistant',
          'system' => 'system'
        }.freeze

        def can_import?(input)
          return false unless input.is_a?(Hash)
          msgs = input['messages'] || input[:messages]
          params = input['parameters'] || input[:parameters]
          return false unless msgs.is_a?(Array) && params.is_a?(Hash)
          msgs.all? { |m| m.is_a?(Hash) && (m['role'] || m[:role]) && (m['text'] || m[:text]) }
        rescue StandardError
          false
        end

        def import(input, options = {})
          raise ArgumentError, 'Monadic Chat export must be a Hash' unless input.is_a?(Hash)
          msgs = input['messages'] || input[:messages] || []
          params = input['parameters'] || input[:parameters] || {}

          provider = guess_provider(params)
          model = params['model'] || params[:model]

          participants = {}
          messages = msgs.each_with_index.map do |m, idx|
            role = (m['role'] || m[:role]).to_s
            mapped = ROLE_MAP.fetch(role, 'other')
            participants[mapped] ||= Base.participant_id(mapped)
            metadata = build_message_metadata(m, mapped, provider, model)
            entry = {
              'id' => (m['mid'] || m[:mid]).to_s.empty? ? Base.message_id(idx) : (m['mid'] || m[:mid]).to_s,
              'speaker' => { 'id' => participants[mapped] },
              'text' => (m['text'] || m[:text]).to_s
            }
            entry['metadata'] = metadata unless metadata.empty?
            entry
          end

          participant_objs = participants.map do |role_key, pid|
            { 'id' => pid, 'role' => role_key, 'description' => role_key }
          end

          opts_with_app = options.dup
          opts_with_app[:title] ||= params['app_name'] || params[:app_name] || opts_with_app['title']

          {
            'format_version' => Monadic::Library::FORMAT_VERSION,
            'conversation_id' => options[:conversation_id] || Base.new_conversation_id,
            'conversation_metadata' => Base.build_metadata(source: 'monadic-chat', options: opts_with_app),
            'participants' => participant_objs,
            'messages' => messages
          }
        end

        # ─── Internals ─────────────────────────────────────────────────

        # Guess provider from the app_name or explicit "provider" parameter.
        # app_name typically ends with the provider (e.g. ChatOpenAI,
        # ChatClaude); fall back to known suffix scan.
        def guess_provider(params)
          explicit = params['provider'] || params[:provider]
          return explicit.to_s if explicit
          app_name = (params['app_name'] || params[:app_name]).to_s
          case app_name
          when /OpenAI\z/   then 'openai'
          when /Claude\z/   then 'anthropic'
          when /Gemini\z/   then 'gemini'
          when /Grok\z/, /Xai\z/i then 'xai'
          when /Mistral\z/i then 'mistral'
          when /Cohere\z/   then 'cohere'
          when /DeepSeek\z/i then 'deepseek'
          when /Perplexity\z/ then 'perplexity'
          when /Ollama\z/   then 'ollama'
          end
        end

        def build_message_metadata(msg, mapped_role, provider, model)
          meta = {}
          if mapped_role == 'assistant'
            meta['provider'] = provider if provider
            meta['model'] = model if model
          end
          thinking = msg['thinking'] || msg[:thinking]
          meta['thinking'] = thinking unless thinking.nil? || thinking.to_s.empty?
          images = msg['images'] || msg[:images]
          meta['images'] = images if images.is_a?(Array) && !images.empty?
          tools = msg['tools'] || msg[:tools]
          meta['tools'] = tools if tools.is_a?(Array) && !tools.empty?
          meta
        end
      end
    end
  end
end
