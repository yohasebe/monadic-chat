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
    # (key and values: the fields of one value, for an app that has them;
    # lists: its collections of items, in the order they were added)
    # and may add lines made from other things (its private
    # state_notes_extra(session): { label => text }).
    module Notes
      DIRNAME = 'notes'

      module_function

      # Makes the page of the session's app again. show: put it on the work
      # screen when it is not there yet (after a reply, or when the chat is
      # resumed or read from a file; a deleted turn only changes a page
      # already shown), selected for tab (the tab the reply or the chat is
      # in). The chat's folder is made for a page to show. Returns its path,
      # or nil.
      def refresh(session, show: false, tab: nil)
        app = declaring_app(session)
        return nil unless app

        declaration = app.send(:state_notes)
        text = render(session, declaration, app)
        folder = text ? Monadic::Workspace::Folders.ensure!(session, app_name: TurnState.app_of(session)) : Monadic::Workspace::Folders.lookup(session)
        return nil unless folder && folder[:status] == :ready

        path = page_path(folder, declaration)
        chat_id = session[Monadic::Workspace::Chats::SESSION_KEY]
        unless text
          Monadic::Workbench::Document.remove(path)
          Monadic::Workbench::Document.drop(chat_id, [path])
          return nil
        end

        write(path, text)
        put_on_screen(chat_id, path, show, { actor: :assistant, tab: tab, generation: session[:_ws_generation] })
        path
      rescue ArgumentError, Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError => e
        Monadic::Utils::ExtraLogger.log { "[TurnState::Notes] not made: #{e.class}" } if defined?(Monadic::Utils::ExtraLogger)
        nil
      end

      # The page of the session's app that is there now: its path, or nil.
      def current(session)
        app = declaring_app(session)
        folder = app && Monadic::Workspace::Folders.lookup(session)
        return nil unless folder && folder[:status] == :ready

        path = page_path(folder, app.send(:state_notes))
        Monadic::Workspace::Folders.real_path(path) ? path : nil
      rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError
        nil
      end

      def page_path(folder, declaration)
        File.join(folder[:relative_dir], DIRNAME, "#{Monadic::Workbench::Document.slug(declaration[:title], 60)}.md")
      end

      # The app the session is in, when it declares its notes.
      def declaring_app(session)
        return nil unless session.respond_to?(:[])

        name = TurnState.app_of(session)
        app = defined?(APPS) ? APPS[name] : nil
        app.respond_to?(:state_notes, true) && app.send(:state_notes).is_a?(Hash) ? app : nil
      end

      # The page in Markdown, or nil when the state holds nothing to show.
      def render(session, declaration, app = nil)
        turns = turn_numbers(session)
        parts = []
        value = declaration[:key] ? TurnState.value(session, declaration[:key].to_s) : { found: false }
        data = value[:found] && value[:data].is_a?(Hash) ? value[:data] : {}
        lines = (declaration[:values] || {}).filter_map do |field, label|
          text = data[field.to_s]
          "- **#{label}**: #{inline(text)}" unless blank?(text)
        end
        lists = (declaration[:lists] || {}).filter_map do |collection, list|
          items = TurnState.items(session, collection.to_s)
          next if items.empty?

          body = items.map { |item| entry(item, list, turns) }.join("\n\n")
          section(list[:label] || collection.to_s, nil, body)
        end
        # Lines made from other things are shown with the state, never alone.
        return nil if lines.empty? && lists.empty?

        extra = app.respond_to?(:state_notes_extra, true) ? app.send(:state_notes_extra, session) : nil
        (extra || {}).each { |label, text| lines << "- **#{label}**: #{inline(text)}" unless blank?(text) }
        parts << section('Settings', turns[value[:by]], lines.join("\n")) unless lines.empty?
        parts.concat(lists)

        "# #{declaration[:title]}\n\n#{parts.join("\n\n")}\n"
      end

      def section(label, turn, body)
        changed = turn ? " (turn #{turn})" : ''
        "## #{label}#{changed}\n\n#{body}"
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

      # Read again where the work screen shows it; put there when asked,
      # for origin's tab to select. A page already there is selected only
      # for a tab that shows nothing (a page loaded again): what the user
      # is looking at stays.
      def put_on_screen(chat_id, path, show, origin)
        board = chat_id && (show ? Monadic::Workbench::Board.for(chat_id) : Monadic::Workbench::Board.existing(chat_id))
        return unless board

        if (item = board.snapshot[:items].find { |found| found[:path] == path })
          Monadic::Workbench::Document.refresh(chat_id, [path])
          if show && origin[:tab] && board.selected(tab: origin[:tab], generation: origin[:generation]).nil?
            board.select(tab: origin[:tab], generation: origin[:generation], item_id: item[:id])
            Monadic::Workbench::Channel.changed(chat_id)
          end
        elsif show
          board.add_file(path: path, origin: origin, epoch: Monadic::Workspace::Chats.epoch(chat_id), wait: 0)
          Monadic::Workbench::Channel.changed(chat_id)
        end
      rescue Monadic::Workbench::Board::Refused, Monadic::Workbench::FileItem::Busy
        nil
      end
    end
  end
end
