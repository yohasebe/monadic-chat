# frozen_string_literal: true

require 'json'
require_relative '../workspace'

module Monadic
  module Routes
    # POST /attachments?tab_id=<tab>  (multipart: file, purpose)
    #
    # Runs behind UploadContext (same origin, which chat) and UploadLimit (how large),
    # both mounted in config.ru ahead of the application.
    module AttachmentRoutes
      PATH = '/attachments'

      def self.registered(app)
        app.post PATH do
          content_type :json
          headers 'Cache-Control' => 'no-store'

          # UploadContext has checked the origin and fixed the chat; without
          # it (not mounted, or the tab unknown) there is no chat to add to.
          chat_id = request.env[Monadic::Workspace::UploadContext::CHAT_KEY]
          unless Monadic::Workspace::Ids.valid?(:chat, chat_id)
            halt 409, { error: 'This page is no longer connected. Reload the page and attach the file again.',
                        reason: 'no_chat' }.to_json
          end

          upload = params['file']
          unless upload.is_a?(Hash) && upload[:tempfile]
            halt 400, { error: 'No file was sent.', reason: 'no_file' }.to_json
          end

          begin
            record = Monadic::Workspace::Attachments.accept!(
              chat_id: chat_id,
              app_name: request.env[Monadic::Workspace::UploadContext::APP_KEY],
              purpose: params['purpose'].to_s,
              original_name: upload[:filename].to_s,
              source: upload[:tempfile]
            )
            status 201
            { attachment_id: record[:attachment_id], name: record[:original_name], size: record[:size],
              purpose: record[:purpose], status: record[:status] }.to_json
          rescue Monadic::Workspace::FileTypes::Rejected => e
            halt 415, { error: e.message, reason: e.reason }.to_json
          rescue Monadic::Workspace::Attachments::Unusable => e
            halt 409, { error: e.message, reason: e.reason }.to_json
          rescue Monadic::Workspace::Folders::Unavailable, Monadic::Workspace::Ledger::Unreadable
            halt 503, { error: 'The chat folder is not available. Check the shared folder and try again.',
                        reason: 'unavailable' }.to_json
          ensure
            upload[:tempfile].close! if upload[:tempfile].respond_to?(:close!)
          end
        end
      end
    end
  end
end
