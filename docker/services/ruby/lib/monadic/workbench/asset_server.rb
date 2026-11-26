# frozen_string_literal: true

require_relative 'artifact'
require_relative 'board'
require_relative 'view_tokens'
require_relative 'whiteboard'
require_relative '../workspace/chats'
require_relative '../workspace/shared_folder_preview'
require_relative '../library/entry_text'

module Monadic
  module Workbench
    # Serves an image or a file of the workbench to the page at
    # /workbench/asset/<token> (ViewTokens), ahead of the application so
    # that the request is not written to the access log: the token in the
    # address is the permission. A :download token serves it once, as a
    # file to save (application/octet-stream, Content-Disposition:
    # attachment), never as something the browser shows; the other tokens
    # serve it inline, never as an attachment. Either way the header names
    # the file by its own name (disposition).
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
    # A :background token serves the picture under a whiteboard drawn on
    # one (serve_background).
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

        ViewTokens.spend(token) if view.purpose == :download && env['REQUEST_METHOD'] == 'GET'
        return serve_file(env, view) if view.item_id

        read = Artifact.read(view.artifact_id, chat_id: view.chat_id)
        return plain(409, 'Changed') unless read[:record][:sha256] == view.sha256

        bytes = read[:bytes]
        return saved(env, bytes, File.basename(read[:record][:copy_path])) if view.purpose == :download

        headers = HEADERS.merge('content-type' => read[:record][:content_type], 'content-length' => bytes.bytesize.to_s)
        [200, headers, env['REQUEST_METHOD'] == 'HEAD' ? [] : [bytes]]
      rescue Artifact::Changed
        plain(409, 'Changed')
      rescue Artifact::Missing
        plain(410, 'Gone')
      rescue Artifact::NotAllowed
        plain(404, 'Not found')
      end

      def serve_file(env, view)
        board = Board.existing(view.chat_id) or return plain(404, 'Not found')
        return serve_library(env, board, view) if board.item(view.item_id)&.fetch('kind', nil) == 'library'
        return serve_render(env, board, view) if view.purpose == :render
        return serve_background(env, board, view) if view.purpose == :background

        entry = board.file_entry(view.item_id, sha256: view.sha256)
        # A video or an audio file is served a range at a time from the file.
        return streamed(env, entry) if %w[audio video].include?(entry['preview']) && view.purpose != :download

        read = board.file_read(view.item_id, sha256: view.sha256)
        entry = read[:entry]
        bytes = read[:bytes]
        return saved(env, bytes, File.basename(entry['path'])) if view.purpose == :download

        headers = HEADERS.merge('content-type' => entry['content_type'],
                                'content-disposition' => disposition('inline', File.basename(entry['path'])))
        bytes = text_shown(board, view, bytes, headers) if entry['preview'] == 'text'
        headers['content-length'] = bytes.bytesize.to_s
        [200, headers, env['REQUEST_METHOD'] == 'HEAD' ? [] : [bytes]]
      rescue Artifact::Changed
        board&.mark(view.item_id, sha256: view.sha256, status: 'changed')
        plain(409, 'Changed')
      rescue Artifact::Missing
        board&.mark(view.item_id, sha256: view.sha256, status: 'missing')
        plain(410, 'Gone')
      rescue FileItem::Busy
        plain(503, 'Busy')
      rescue FileItem::TooLarge
        plain(413, 'Too large')
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

      # A Library item at the version given, read from the Library now
      # (EntryText.bytes_for: its kept file while the entry names it, or
      # its text): a PDF as it is, text as a text file is shown (text_view;
      # the board keeps how many lines it is). 409 when it is not that
      # version any more, 410 when it is gone, 415 when the Library did not
      # keep its whole text; a download is not served.
      def serve_library(env, board, view)
        return plain(404, 'Not found') unless view.purpose == :view

        record = board.library_entry(view.item_id, version: view.sha256)
        bytes = Monadic::Library::EntryText.bytes_for(record)
        if record['preview'] == 'pdf'
          headers = HEADERS.merge('content-type' => 'application/pdf')
        else
          headers = HEADERS.merge('content-type' => 'text/plain; charset=utf-8')
          bytes = text_shown(board, view, bytes, headers)
        end
        headers['content-length'] = bytes.bytesize.to_s
        [200, headers, env['REQUEST_METHOD'] == 'HEAD' ? [] : [bytes]]
      rescue Monadic::Library::EntryText::Changed
        board.mark(view.item_id, sha256: view.sha256, status: 'changed')
        plain(409, 'Changed')
      rescue Monadic::Library::EntryText::Missing
        board.mark(view.item_id, sha256: view.sha256, status: 'missing')
        plain(410, 'Gone')
      rescue Monadic::Library::EntryText::Incomplete
        plain(415, 'Not text')
      rescue Artifact::Changed, Artifact::NotAllowed
        plain(409, 'Changed')
      end

      # The picture under the whiteboard of the item at the version given:
      # the copy its record names beside it (WhiteboardBackground.read), as
      # the image it is. 404 for a file that is not a whiteboard or a board
      # with no picture; 410 when the copy is gone; 409 when it is not the
      # picture recorded.
      def serve_background(env, board, view)
        entry = board.file_entry(view.item_id, sha256: view.sha256)
        return plain(404, 'Not found') unless Whiteboard.kept_as?(entry['path'])

        data = JSON.parse(board.file_read(view.item_id, sha256: view.sha256, limit: Whiteboard::BYTES_LIMIT)[:bytes].to_s)
        record = Whiteboard.background_of(data) or return plain(404, 'Not found')
        bytes = WhiteboardBackground.read(entry['path'], record)
        headers = HEADERS.merge('content-type' => record['content_type'], 'content-length' => bytes.bytesize.to_s)
        [200, headers, env['REQUEST_METHOD'] == 'HEAD' ? [] : [bytes]]
      rescue JSON::ParserError, Whiteboard::Refused, FileItem::TooLarge
        plain(404, 'Not found')
      rescue WhiteboardBackground::Missing
        plain(410, 'Gone')
      rescue WhiteboardBackground::Changed
        plain(409, 'Changed')
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

      # A video or an audio file (FileItem.stream): one range of its bytes
      # (Range: bytes=a-b, a-, -n), 206; the whole, 200; a range outside
      # them, 416. The body reads the file as it is sent.
      def streamed(env, entry)
        headers = HEADERS.merge('content-type' => entry['content_type'], 'accept-ranges' => 'bytes',
                                'content-disposition' => disposition('inline', File.basename(entry['path'])))
        part = FileItem.stream(entry, env['HTTP_RANGE'])
        if part[:status] == 416
          headers['content-range'] = "bytes */#{part[:size]}"
          headers['content-length'] = '0'
          return [416, headers, []]
        end

        headers['content-range'] = "bytes #{part[:first]}-#{part[:last]}/#{part[:size]}" if part[:status] == 206
        headers['content-length'] = part[:length].to_s
        if env['REQUEST_METHOD'] == 'HEAD'
          part[:body].close
          return [part[:status], headers, []]
        end

        [part[:status], headers, part[:body]]
      end

      # The checked bytes as a file to save: the whole of it (no range),
      # as bytes the browser does not show.
      def saved(env, bytes, name)
        headers = HEADERS.merge('content-type' => 'application/octet-stream',
                                'content-disposition' => disposition('attachment', name),
                                'content-length' => bytes.bytesize.to_s)
        [200, headers, env['REQUEST_METHOD'] == 'HEAD' ? [] : [bytes]]
      end

      NAME_BYTES = 255 # the longest file name the file systems hold
      FALLBACK_CHARS = 200

      # Content-Disposition naming the file: filename*, every byte of the
      # name (UTF-8, at most NAME_BYTES, cut at a character) percent-encoded
      # but RFC 5987's attr-chars; filename, for clients that read only it,
      # those of its characters that need no quoting (letters, digits and
      # . _ - ( ) + and space; anything else, and a leading dot, as _).
      # Neither can end the header or start another parameter.
      def disposition(kind, name)
        name = name.to_s.dup.force_encoding(Encoding::UTF_8)
        name = name.scrub('_') unless name.valid_encoding?
        name = name.byteslice(0, NAME_BYTES).scrub('') if name.bytesize > NAME_BYTES
        encoded = name.bytes.map { |b| b.chr.match?(/[A-Za-z0-9!\#$&+\-.^_`|~]/) ? b.chr : format('%%%02X', b) }.join
        fallback = name.gsub(/[^A-Za-z0-9._\-()+ ]/, '_').sub(/\A\./, '_')[0, FALLBACK_CHARS]
        fallback = 'file' if fallback.strip.empty?
        "#{kind}; filename=\"#{fallback}\"; filename*=UTF-8''#{encoded}"
      end

      def plain(status, text)
        [status, HEADERS.merge('content-type' => 'text/plain', 'content-length' => text.bytesize.to_s), [text]]
      end
    end
  end
end
