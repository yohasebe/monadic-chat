# frozen_string_literal: true

require_relative 'availability'
require_relative '../sent'
require_relative '../../workspace/chats'

module Monadic
  module Workbench
    module Look
      # A request to the provider was not sent: it held what a look read,
      # and that may no longer go to the model.
      class Withheld < StandardError; end

      # One post of a request that holds looks (the ids a helper put in it).
      # Checked right before it is sent; the images it holds are kept as
      # sent (Sent) as it is handed to the provider, then it is settled by
      # what happened to it; a post that never settles (the thread stopped)
      # settles in its ensure.
      class Attempt
        NETWORK_ERRORS = [IOError, SystemCallError].freeze

        def initialize(ledger, ids)
          @ledger = ledger
          @ids = ids
        end

        # Checks, then runs the block (the HTTP post) and records the
        # outcome. Raises Withheld when the looks may not go.
        def send!(session, provider:, model:)
          refusal = refusal(session, provider: provider, model: model)
          if refusal
            @ledger.mark(@ids, 'unsent')
            raise Withheld, "The request was not sent: #{refusal}."
          end

          started = false
          settled = false
          begin
            keep_images(session)
            started = true
            res = yield
            ok = res.respond_to?(:status) && res.status.success?
            @ledger.mark(@ids, ok ? 'sent' : 'refused')
            settled = true
            res
          rescue *network_errors
            @ledger.mark(@ids, 'unknown')
            settled = true
            raise
          end
        ensure
          @ledger.mark(@ids, started ? 'unknown' : 'unsent') if refusal.nil? && !settled
        end

        # Why the looks may not go now, or nil.
        def refusal(session, provider:, model:)
          # A Rack session is not a Hash; it is read by key.
          chat = session.respond_to?(:[]) ? session[Monadic::Workspace::Chats::SESSION_KEY] : nil
          return 'the looks of this reply were let go' if @ledger.closed?
          return 'the chat of this reply is no longer the one in this tab' unless chat == @ledger.chat_id
          return 'the chat was reset' unless Monadic::Workspace::Chats.epoch(chat) == @ledger.epoch

          held = @ledger.observations(@ids)
          return 'the model does not take images' if held.any?(&:image) && !Availability.vision?(provider.to_s, model)

          files = held.filter_map(&:file)
          unless files.all? { |f| native?(session, provider, model, f) }
            return 'the model or the chat does not take the PDF as it is'
          end

          nil
        end

        private

        def native?(session, provider, model, file)
          pages = @ledger.observations(@ids).find { |o| o.file.equal?(file) }&.pages
          Availability.native_file?(session: session, provider: provider, model: model, type: file.content_type,
                                    bytes: file.bytes.bytesize, pages: pages && pages[:total])
        end

        # The images and the files the post holds, kept as sent before it
        # goes. When the
        # chat keeps too much, the post is kept back (Withheld), as nothing
        # went; an image the chat has no folder for goes without being kept.
        def keep_images(session)
          images = @ledger.observations(@ids).flat_map { |o| [o.image, o.file] }.compact
          return if images.empty?

          app_name = session.respond_to?(:[]) ? session[:parameters]&.dig('app_name') : nil
          shas = []
          images.each do |image|
            shas << Sent.keep!(@ledger.chat_id, image.bytes, image.content_type, app_name: app_name)
          rescue Sent::Unavailable
            next
          end
          @ledger.kept(shas)
        rescue Sent::Full => e
          Sent.done(@ledger.chat_id, shas)
          raise Withheld, "The request was not sent: #{e.message}."
        end

        def network_errors
          defined?(HTTP::Error) ? [HTTP::Error, HTTP::TimeoutError, *NETWORK_ERRORS] : NETWORK_ERRORS
        end
      end
    end
  end
end
