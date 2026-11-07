# frozen_string_literal: true

require 'base64'
require 'digest'
require 'json'
require 'securerandom'
require 'time'
require_relative 'board'
require_relative 'image_check'
require_relative 'artifact'
require_relative 'file_item'
require_relative '../history/policy'
require_relative '../workspace/chats'
require_relative '../workspace/request_context'
require_relative '../workspace/shared_folder_preview'
require_relative '../utils/privacy/outbound'
require_relative '../utils/privacy/backend'

module Monadic
  module Workbench
    # What the model asked to see of the work screen (look_at_workbench):
    # the item the asking tab has selected, at the version it has, read when
    # the tool runs. Each look is an observation of its own, kept for the
    # request it was made in (Ledger): the image goes to the model with the
    # tool's result, from the bytes read here, never from a name the model
    # or the page gives.
    module Look
      TOOL = 'look_at_workbench'
      SCOPES = %w[visible whole].freeze
      # Why a look gave nothing. The model is told the reason and a short
      # sentence; a refusal is never a look.
      REASONS = %w[
        private vision_unsupported tools_unsupported transport_unsupported connection_gone no_selection
        selection_changed changed missing range_unknown not_shown drawing capture_timeout browser_unavailable
        pdf_text_unavailable unsupported_kind too_large busy cancelled filtered
      ].freeze
      # Bytes of a text file read for scope whole, and characters returned.
      TEXT_WHOLE_BYTES = 1024 * 1024
      TEXT_CHARS = 64_000

      class Refused < StandardError
        attr_reader :reason

        def initialize(reason, message)
          raise ArgumentError, "unknown reason #{reason}" unless REASONS.include?(reason)

          super(message)
          @reason = reason
        end
      end

      # An image the server read and checked, to go to the model. Made only
      # by checked (from bytes the server read itself), never from a Hash,
      # JSON or a record read back: nothing a model, a page or an import
      # gives can become one. Its text forms name it without its bytes.
      class ImageValue
        # The base64 text sent for an image, at most (as for the shared
        # folder's tool images, ToolImageUtils).
        MAX_BASE64 = 5 * 1024 * 1024

        attr_reader :bytes, :content_type, :sha256, :width, :height, :source

        private_class_method :new

        # source: what the bytes are (workbench_image, workbench_file).
        # Raises Refused (too_large, unsupported_kind) for bytes that are
        # not a PNG, JPEG or WebP image within the limits.
        def self.checked(bytes, source:)
          info = ImageCheck.check!(bytes)
          raise Refused.new('too_large', 'the image is too large to send') if Base64.strict_encode64(bytes).bytesize > MAX_BASE64

          new(bytes.b.dup.freeze, info, source)
        rescue ImageCheck::Refused => e
          reason = e.message == 'image too large' ? 'too_large' : 'unsupported_kind'
          raise Refused.new(reason, e.message)
        end

        def initialize(bytes, info, source)
          @bytes = bytes
          @content_type = info[:content_type]
          @width = info[:width]
          @height = info[:height]
          @sha256 = Digest::SHA256.hexdigest(bytes)
          @source = source
          freeze
        end

        def data_url
          "data:#{content_type};base64,#{base64}"
        end

        def base64
          Base64.strict_encode64(bytes)
        end

        def to_s
          "#<#{self.class.name} #{content_type} #{width}x#{height} sha256=#{sha256[0, 12]}>"
        end
        alias_method :inspect, :to_s

        def to_json(*args)
          to_s.to_json(*args)
        end
      end

      # What a look gives the tool call: the text the model reads, and the
      # observation it made (its image, if any, follows the tool's result
      # in the request). to_s is the text, as for any tool result.
      Result = Struct.new(:observation_id, :text, keyword_init: true) do
        def to_s
          text
        end
      end

      module_function

      # Runs a look for the caller (Caller): refused (a "❌" sentence, as
      # other tools of the work screen) or a Result.
      def run(caller, scope: 'visible')
        scope = scope.to_s
        raise Refused.new('unsupported_kind', "scope must be one of #{SCOPES.join(', ')}") unless SCOPES.include?(scope)
        raise Refused.new('connection_gone', 'this reply cannot look at the work screen') unless caller
        raise Refused.new('private', 'nothing is sent from the work screen in a Private chat') if private?(caller)

        board = Board.existing(caller.chat_id) or raise Refused.new('no_selection', 'nothing is shown in the work screen')
        raise Refused.new('private', 'nothing is sent from the work screen in a Private chat') if board.private?

        item = target(board, caller)
        ledger = Ledger.for(caller.chat_id, caller.epoch, caller.request_id, session: caller.session, tab: caller.tab)
        ledger.one_at_a_time do
          seen = read(board, item, scope)
          unless board.still_selected?(tab: caller.tab, generation: caller.generation, item: item)
            raise Refused.new('selection_changed', 'the work screen shows something else now; nothing was looked at')
          end
          raise Refused.new('cancelled', 'the reply was stopped') unless current?(caller)

          id = "look_#{SecureRandom.hex(8)}"
          # What goes to the model as text (the result, the caption before
          # an image) passes the chat's Privacy Filter here, as the user's
          # words do; the words the user marked are checked again when the
          # request is sent.
          result = filtered(caller.session, result_text(id, seen, scope))
          caption = seen[:image] ? filtered(caller.session, caption_text(id, seen)) : nil
          ledger.add(seen.merge(id: id, scope: scope, result: result, caption: caption))
          Result.new(observation_id: id, text: result)
        end
      rescue Refused => e
        "❌ Nothing was looked at in the work screen (#{e.reason}): #{e.message}."
      end

      # The item the caller's tab has selected (Board#look_target).
      def target(board, caller)
        found = board.look_target(tab: caller.tab, generation: caller.generation)
        case found
        when :connection_gone
          raise Refused.new('connection_gone', 'the tab this message came from is no longer connected')
        when nil
          raise Refused.new('no_selection', 'nothing is selected in the work screen of the tab this message came from')
        end
        found
      end

      def private?(caller)
        Monadic::History::Policy.private?(caller.session) || Monadic::History::Policy.known_private?(caller.chat_id)
      end

      # Whether what the caller reads may still go to the model: the
      # caller's session is still in its chat, the chat is at the epoch the
      # reply began in, and it is not Private.
      def current?(caller)
        caller.session.respond_to?(:[]) && caller.session[Monadic::Workspace::Chats::SESSION_KEY] == caller.chat_id &&
          Monadic::Workspace::Chats.epoch(caller.chat_id) == caller.epoch && !private?(caller)
      end

      # text as the chat's Privacy Filter lets it go: masked with the chat's
      # pipeline when the filter is on, and with no word the user marked
      # left. Refused (filtered) otherwise.
      def filtered(session, text)
        outbound = Monadic::Utils::Privacy::Outbound
        pipeline = outbound.pipeline!(session)
        words = outbound.terms_of(session)
        text = outbound.mask(text, pipeline, 'user') if pipeline
        left = false
        outbound.each_text(text) { |value| left ||= outbound.holds_word?(value, words) } unless words.empty?
        raise Refused.new('filtered', 'the Privacy Filter does not let it go to the model') if left

        text
      rescue Monadic::Utils::Privacy::Outbound::Refused, Monadic::Utils::Privacy::BackendError
        raise Refused.new('filtered', 'the Privacy Filter could not check it, so it was not sent')
      end

      # What the item shows, read now at its version:
      # { item_id:, kind:, name:, path:, version:, image: | text: ... }.
      def read(board, item, scope)
        if item['artifact']
          entry = item['artifact']
          read = Artifact.read(entry['id'], chat_id: board.chat_id)
          return seen(item, 'image', entry['name'], entry['path'], read[:record][:sha256],
                      image: ImageValue.checked(read[:bytes], source: 'workbench_image'))
        end
        raise Refused.new('browser_unavailable', 'the browser cannot be looked at yet') if item['browser']

        file = item['file'] or raise Refused.new('unsupported_kind', 'this item cannot be looked at')
        case file['preview']
        when 'image'
          bytes = board.file_read(item['id'], sha256: file['sha256'])[:bytes]
          seen(item, 'image', file['name'], file['path'], file['sha256'],
               image: ImageValue.checked(bytes, source: 'workbench_file'))
        when 'text'
          unless scope == 'whole'
            raise Refused.new('range_unknown', 'the lines in view cannot be read yet; look with scope whole')
          end

          bytes = board.file_read(item['id'], sha256: file['sha256'])[:bytes]
          seen(item, 'text', file['name'], file['path'], file['sha256'], **whole_text(bytes))
        else
          raise Refused.new('unsupported_kind', "a #{file['preview']} file cannot be looked at yet")
        end
      rescue Artifact::Missing
        raise Refused.new('missing', 'the file is no longer in the shared folder; it was not looked at')
      rescue Artifact::Changed, Artifact::NotAllowed
        raise Refused.new('changed', 'the file changed since it was opened; open it again to look at it')
      rescue FileItem::Busy
        raise Refused.new('busy', 'the work screen is reading other files; try again in a moment')
      rescue Monadic::Workspace::SharedFolderPreview::NotText
        raise Refused.new('unsupported_kind', 'the file is not text')
      end

      def seen(item, kind, name, path, version, **content)
        { item_id: item['id'], kind: kind, name: name.to_s, path: path.to_s, version: version, **content }
      end

      # The text of a whole file as the work screen shows text (text_view),
      # from its first TEXT_WHOLE_BYTES, cut to TEXT_CHARS at a line's end
      # when one is near: { text:, first_line:, last_line:, total_lines:,
      # truncated:, partial_line:, empty: }. total_lines is nil when the
      # file was not read to its end; partial_line says the last line given
      # is only its beginning; empty says the file holds no line.
      def whole_text(bytes)
        view = Monadic::Workspace::SharedFolderPreview.text_view(bytes, limit: TEXT_WHOLE_BYTES)
        text = view[:text]
        cut = text.length > TEXT_CHARS
        if cut
          text = text[0, TEXT_CHARS]
          line_end = text.rindex("\n")
          text = text[0..line_end] if line_end && line_end >= TEXT_CHARS / 2
        end
        lines = Monadic::Workspace::SharedFolderPreview.text_lines(text).size
        whole = !view[:truncated] && !cut
        { text: text, first_line: lines.zero? ? nil : 1, last_line: lines.zero? ? nil : lines,
          total_lines: whole ? lines : nil, truncated: !whole,
          partial_line: !whole && !text.empty? && !text.end_with?("\n"), empty: lines.zero? && whole }
      end

      # The tool's result for the model: what was looked at, and the text
      # (or that the image follows).
      def result_text(id, seen, scope)
        out = { 'status' => 'looked', 'observation_id' => id, 'scope' => scope,
                'item' => { 'kind' => seen[:kind], 'name' => seen[:name], 'path' => seen[:path],
                            'version' => seen[:version].to_s[0, 12] } }
        if seen[:image]
          out['image'] = 'The image is attached after this result.'
        else
          out['lines'] = { 'first' => seen[:first_line], 'last' => seen[:last_line], 'total' => seen[:total_lines],
                           'last_line_cut' => seen[:partial_line] }
          out['truncated'] = seen[:truncated]
          out['empty'] = true if seen[:empty]
          out['text'] = seen[:text]
        end
        JSON.generate(out)
      end

      # The text before a look's image in a request: which observation it
      # is, as data (the name is the user's file name, not an instruction).
      def caption_text(id, seen)
        "The image below is what #{TOOL} looked at: " +
          JSON.generate({ 'observation_id' => id, 'name' => seen[:name], 'version' => seen[:version].to_s[0, 12] })
      end
    end
  end
end

require_relative 'look/ledger'
require_relative 'look/attempt'
