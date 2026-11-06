# frozen_string_literal: true

require_relative 'artifact'
require_relative 'view_tokens'
require_relative '../workspace/chats'

module Monadic
  module Workbench
    # Serves an image of the workbench to the page at
    # /workbench/asset/<token> (ViewTokens), ahead of the application so
    # that the request is not written to the access log: the token in the
    # address is the permission. A :download token serves it as a file to
    # save (Content-Disposition: attachment).
    #
    # Only a GET or HEAD sent by a page of this server (Sec-Fetch-Site:
    # same-origin) is served, and only while the token's tab still has the
    # connection it was given to and its chat is at the same epoch and not
    # Private. Anything else gets the same "not found". For a token that
    # holds, the image is read from the chat's folder (Artifact): a file
    # that is no longer the one recorded is answered 409 (changed) or 410
    # (gone), so the page can say which.
    class AssetServer
      PREFIX = '/workbench/asset/'
      HEADERS = {
        'cache-control' => 'no-store',
        'x-content-type-options' => 'nosniff',
        'cross-origin-resource-policy' => 'same-origin',
        'referrer-policy' => 'no-referrer',
        'content-security-policy' => "default-src 'none'"
      }.freeze

      # live: the generation of the connection a tab has now (or nil).
      # private_chat: whether a chat is Private.
      def initialize(app, live:, private_chat:)
        @app = app
        @live = live
        @private_chat = private_chat
      end

      def call(env)
        path = env['PATH_INFO'].to_s
        return @app.call(env) unless path.start_with?(PREFIX)

        serve(env, path.delete_prefix(PREFIX))
      rescue StandardError
        plain(404, 'Not found')
      end

      private

      def serve(env, token)
        return plain(404, 'Not found') unless %w[GET HEAD].include?(env['REQUEST_METHOD'])
        return plain(404, 'Not found') unless env['HTTP_SEC_FETCH_SITE'] == 'same-origin'

        view = ViewTokens.view(token) or return plain(404, 'Not found')
        return plain(404, 'Not found') unless @live.call(view.tab) == view.generation
        return plain(404, 'Not found') unless view.epoch == Monadic::Workspace::Chats.epoch(view.chat_id)
        return plain(404, 'Not found') if @private_chat.call(view.chat_id)

        read = Artifact.read(view.artifact_id, chat_id: view.chat_id)
        return plain(409, 'Changed') unless read[:record][:sha256] == view.sha256

        bytes = read[:bytes]
        headers = HEADERS.merge('content-type' => read[:record][:content_type], 'content-length' => bytes.bytesize.to_s)
        headers['content-disposition'] = attachment(File.basename(read[:record][:copy_path])) if view.purpose == :download
        [200, headers, env['REQUEST_METHOD'] == 'HEAD' ? [] : [bytes]]
      rescue Artifact::Changed
        plain(409, 'Changed')
      rescue Artifact::Missing
        plain(410, 'Gone')
      rescue Artifact::NotAllowed
        plain(404, 'Not found')
      end

      # The name is an image name of the ledger (ASCII letters, digits, _ -
      # and one dot), so it needs no quoting beyond the encoded form.
      def attachment(name)
        encoded = name.bytes.map { |b| b.chr.match?(/[A-Za-z0-9._-]/) ? b.chr : format('%%%02X', b) }.join
        "attachment; filename=\"#{encoded}\"; filename*=UTF-8''#{encoded}"
      end

      def plain(status, text)
        [status, HEADERS.merge('content-type' => 'text/plain', 'content-length' => text.bytesize.to_s), [text]]
      end
    end
  end
end
