# frozen_string_literal: true

require_relative '../turn_state'
require_relative '../workbench/document'
require_relative '../workbench/board'
require_relative '../workbench/channel'
require_relative '../workspace/folders'
require_relative '../utils/shared_path_guard'

module Monadic
  module TurnState
    # An app's state as a page on the work screen (a story's notes: its
    # plot, its characters): made by the server from the state the
    # conversation leaves, never written by the model, and made again when
    # a reply changes the state or a turn is deleted. Each part says the
    # turn that changed it last.
    #
    # An app shows its state so by declaring it (the app's private
    # state_notes):
    #   { title:, key:, values: { field => label },
    #     lists: { collection => { label:, name: field, fields: { field => label } } } }
    # and may add lines made from other things (its private
    # state_notes_extra(session): { label => text }).
    module Notes
      DIRNAME = 'notes'

      module_function

      # Makes the page of the session's app again. show: put it on the work
      # screen when it is not there yet (after a reply; a deleted turn only
      # changes a page already shown). Returns its path, or nil.
      def refresh(session, show: false)
        app = declaring_app(session)
        return nil unless app

        declaration = app.send(:state_notes)
        folder = Monadic::Workspace::Folders.lookup(session)
        return nil unless folder && folder[:status] == :ready

        path = File.join(folder[:relative_dir], DIRNAME, "#{Monadic::Workbench::Document.slug(declaration[:title], 60)}.md")
        chat_id = session[Monadic::Workspace::Chats::SESSION_KEY]
        text = render(session, declaration, app)
        unless text
          Monadic::Workbench::Document.remove(path)
          Monadic::Workbench::Document.drop(chat_id, [path])
          return nil
        end

        write(path, text)
        put_on_screen(chat_id, path, show)
        path
      rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError => e
        Monadic::Utils::ExtraLogger.log { "[TurnState::Notes] not made: #{e.class}" } if defined?(Monadic::Utils::ExtraLogger)
        nil
      end

      # The app the session is in, when it keeps its state by turn and
      # declares its notes.
      def declaring_app(session)
        return nil unless session.is_a?(Hash) && TurnState.enabled?(session)

        name = TurnState.app_of(session)
        app = defined?(APPS) ? APPS[name] : nil
        app.respond_to?(:state_notes, true) && app.send(:state_notes).is_a?(Hash) ? app : nil
      end

      # The page in Markdown, or nil when the state holds nothing to show.
      def render(session, declaration, app = nil)
        turns = turn_numbers(session)
        parts = []
        value = TurnState.value(session, declaration[:key].to_s)
        data = value[:found] && value[:data].is_a?(Hash) ? value[:data] : {}
        lines = (declaration[:values] || {}).filter_map do |field, label|
          text = data[field.to_s]
          "- **#{label}**: #{inline(text)}" unless blank?(text)
        end
        lists = (declaration[:lists] || {}).filter_map do |collection, list|
          items = TurnState.items(session, collection.to_s)
          next if items.empty?

          body = items.map { |item| entry(item, list, turns) }.join("\n\n")
          section(collection.to_s, list[:label] || collection.to_s, nil, body)
        end
        # Lines made from other things are shown with the state, never alone.
        return nil if lines.empty? && lists.empty?

        extra = app.respond_to?(:state_notes_extra, true) ? app.send(:state_notes_extra, session) : nil
        (extra || {}).each { |label, text| lines << "- **#{label}**: #{inline(text)}" unless blank?(text) }
        parts << section('settings', 'Settings', turns[value[:by]], lines.join("\n")) unless lines.empty?
        parts.concat(lists)

        "# #{declaration[:title]}\n\n#{parts.join("\n\n")}\n"
      end

      def section(key, label, turn, body)
        changed = turn ? " (turn #{turn})" : ''
        "#{Monadic::Workbench::Document::MARK} #{key}\n## #{label}#{changed}\n\n#{body}"
      end

      def entry(item, list, turns)
        data = item[:data]
        unless data.is_a?(Hash)
          turn = turns[item[:by]]
          return "- #{inline(data)}#{turn ? " (turn #{turn})" : ''}"
        end

        name = data[list[:name].to_s] || data.values.first
        turn = turns[item[:by]]
        heading = "### #{inline(name)}#{turn ? " (turn #{turn})" : ''}"
        fields = (list[:fields] || {}).filter_map do |field, label|
          text = data[field.to_s]
          "- **#{label}**: #{inline(text)}" unless blank?(text)
        end
        ([heading] + fields).join("\n")
      end

      # The number of each reply among the chat's replies, by its mid.
      def turn_numbers(session)
        turn = 0
        Array(session[:messages]).each_with_object({}) do |message, out|
          next unless message.is_a?(Hash) && message['role'] == 'assistant'

          out[message['mid']] = (turn += 1)
        end
      end

      def inline(value)
        text = value.is_a?(String) ? value : JSON.generate(value)
        text.gsub(/\s*\n\s*/, ' ').strip
      end

      def blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end

      def write(path, text)
        root = File.realpath(Monadic::Utils::Environment.data_path)
        full = File.join(root, path)
        return if Monadic::Workspace::Folders.real_path(path) && File.read(full, encoding: 'UTF-8') == text

        Monadic::Utils::SharedPathGuard.mkdir_p!(File.dirname(full), strict: true)
        Monadic::Utils::SharedPathGuard.write_file!(full, text, mode: 'w', replace: true, strict: true)
      end

      # Read again where the work screen shows it; put there when asked.
      def put_on_screen(chat_id, path, show)
        board = chat_id && (show ? Monadic::Workbench::Board.for(chat_id) : Monadic::Workbench::Board.existing(chat_id))
        return unless board

        if board.snapshot[:items].any? { |item| item[:path] == path }
          Monadic::Workbench::Document.refresh(chat_id, [path])
        elsif show
          board.add_file(path: path, origin: { actor: :assistant }, epoch: Monadic::Workspace::Chats.epoch(chat_id), wait: 0)
          Monadic::Workbench::Channel.changed(chat_id)
        end
      rescue Monadic::Workbench::Board::Refused, Monadic::Workbench::FileItem::Busy
        nil
      end
    end
  end
end
