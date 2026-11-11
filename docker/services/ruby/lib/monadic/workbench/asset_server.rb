# frozen_string_literal: true

require_relative 'artifact'
require_relative 'board'
require_relative 'view_tokens'
require_relative '../workspace/chats'
require_relative '../workspace/shared_folder_preview'

module Monadic
  module Workbench
    # Serves an image or a file of the workbench to the page at
    # /workbench/asset/<token> (ViewTokens), ahead of the application so
    # that the request is not written to the access log: the token in the
    # address is the permission. A :download token serves it as a file to
    # save (Content-Disposition: attachment).
    #
    # Only a GET or HEAD sent by a page of this server (Sec-Fetch-Site:
    # same-origin) is served, and only while the token's tab still has the
    # connection it was given to and its chat is at the same epoch.
    # Anything else gets the same "not
    # found". For a token that holds, the image is read from the chat's
    # folder (Artifact), the file from the shared folder (FileItem): one
    # that is no longer the version given is answered 409 (changed) or 410
    # (gone), so the page can say which. A text file is served as it is
    # shown (SharedFolderPreview.text_view: its beginning, as UTF-8 with
    # "\n" line ends; x-workbench-truncated when cut), or 415 when that is
    # not text. A single byte range is served from the checked bytes (audio, video).
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
      def initialize(app, live:)
        @app = app
        @live = live
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
        return serve_file(env, view) if view.item_id

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

      def serve_file(env, view)
        return plain(404, 'Not found') unless %i[view render].include?(view.purpose)

        board = Board.existing(view.chat_id) or return plain(404, 'Not found')
        return serve_render(env, board, view) if view.purpose == :render

        read = board.file_read(view.item_id, sha256: view.sha256)
        entry = read[:entry]
        bytes = read[:bytes]
        headers = HEADERS.merge('content-type' => entry['content_type'])
        bytes = text_shown(board, view, bytes, headers) if entry['preview'] == 'text'
        status, bytes = ranged(env, headers, bytes) if %w[audio video].include?(entry['preview'])
        headers['content-length'] = bytes.bytesize.to_s
        [status || 200, headers, env['REQUEST_METHOD'] == 'HEAD' ? [] : [bytes]]
      rescue Artifact::Changed
        board&.mark(view.item_id, sha256: view.sha256, status: 'changed')
        plain(409, 'Changed')
      rescue Artifact::Missing
        board&.mark(view.item_id, sha256: view.sha256, status: 'missing')
        plain(410, 'Gone')
      rescue FileItem::Busy
        plain(503, 'Busy')
      rescue Monadic::Workspace::SharedFolderPreview::NotText
        # The same version cannot be shown as text: not a change of the file.
        plain(415, 'Not text')
      rescue Artifact::NotAllowed
        plain(404, 'Not found')
      end

      # The whole of a text file the page draws (SharedFolderPreview.render_for
      # names which, from the path the board holds), as text, never cut. A
      # file larger than the limit (as opened, or as it is now) is refused
      # before it is read (413), and again by the bytes read; bytes that are
      # not UTF-8 are 415. Served as text: nothing runs here. The lines a
      # text item shows (note_text) stay as the text view gave them.
      def serve_render(env, board, view)
        entry = board.file_entry(view.item_id, sha256: view.sha256)
        return plain(404, 'Not found') unless Monadic::Workspace::SharedFolderPreview.render_for(entry['path'])
        return plain(413, 'Too large') if entry['size'].to_i > Monadic::Workspace::SharedFolderPreview::RENDER_LIMIT

        limit = Monadic::Workspace::SharedFolderPreview::RENDER_LIMIT
        text = Monadic::Workspace::SharedFolderPreview.render_text(board.file_read(view.item_id, sha256: view.sha256,
                                                                                  limit: limit)[:bytes])
        bytes = text.b
        headers = HEADERS.merge('content-type' => 'text/plain; charset=utf-8', 'content-length' => bytes.bytesize.to_s)
        [200, headers, env['REQUEST_METHOD'] == 'HEAD' ? [] : [bytes]]
      rescue Monadic::Workspace::SharedFolderPreview::TooLarge, FileItem::TooLarge
        plain(413, 'Too large')
      rescue Monadic::Workspace::SharedFolderPreview::NotText
        plain(415, 'Not text')
      end

      # What a text item shows of its file (SharedFolderPreview.text_view),
      # as UTF-8 bytes; the board keeps how many lines that is for this
      # version (what the page says it shows is checked against it).
      def text_shown(board, view, bytes, headers)
        shown = Monadic::Workspace::SharedFolderPreview.text_view(bytes)
        board.note_text(view.item_id, sha256: view.sha256,
                                      lines: Monadic::Workspace::SharedFolderPreview.text_lines(shown[:text]).size,
                                      truncated: shown[:truncated])
        headers['x-workbench-truncated'] = '1' if shown[:truncated]
        shown[:text].b
      end

      # One range of bytes (Range: bytes=a-b, a-, -n), 206; the whole, 200;
      # a range outside the bytes, 416.
      def ranged(env, headers, bytes)
        headers['accept-ranges'] = 'bytes'
        range = Monadic::Workspace::SharedFolderPreview.range_for(env['HTTP_RANGE'], bytes.bytesize)
        return [200, bytes] unless range
        if range == :unsatisfiable
          headers['content-range'] = "bytes */#{bytes.bytesize}"
          return [416, '']
        end

        first, last = range
        headers['content-range'] = "bytes #{first}-#{last}/#{bytes.bytesize}"
        [206, bytes.byteslice(first, last - first + 1)]
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
