# frozen_string_literal: true

require 'digest'
require_relative 'chat_output'
require_relative 'made'
require_relative 'shown'
require_relative 'board'
require_relative 'channel'
require_relative '../workspace/folders'
require_relative '../utils/shared_path_guard'

module Monadic
  module Workbench
    # A long text written over turns (a story, a draft revised again and
    # again) as sections. Each section a reply writes is a file of its own
    # in a run folder of the chat (<document>--<section>.md), made by that
    # reply (Made): deleting the turn takes it away. What the user reads is
    # one file put together from them, <chat folder>/documents/<document>.md:
    # the sections in the order they were first written, each as the
    # newest turn wrote it, with a mark between them. It is made again from
    # the conversation whenever a section is written or a turn is deleted,
    # so it never says more than the conversation does.
    module Document
      DIRNAME = 'documents'
      SECTION_FILE = /\A(?<document>[a-z0-9-]{1,60})--(?<section>[a-z0-9-]{1,40})\.md\z/
      # The line that marks where a section begins (the work screen scrolls
      # to it).
      MARK = '###### §'
      CONTENT_LIMIT = 512 * 1024

      class Refused < StandardError; end

      module_function

      # A name made of lowercase letters, digits and hyphens, for a title of
      # any language (one with none of them is named by its hash).
      def slug(text, limit)
        plain = text.to_s.unicode_normalize(:nfkc).downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')[0, limit]
        plain = plain.to_s.sub(/-+\z/, '')
        return plain unless plain.empty?

        "h-#{Digest::SHA256.hexdigest(text.to_s)[0, 12]}"
      end

      # Writes a section for the reply of workbench and puts the document
      # together again. Returns { section_path:, path:, shown: }.
      def write(session:, workbench:, app_name:, document:, section:, content:)
        title = document.to_s.strip
        key = section.to_s.strip
        text = content.to_s
        raise Refused, 'a document needs a title' if title.empty?
        raise Refused, 'a section needs a name' if key.empty?
        raise Refused, 'the section is empty' if text.strip.empty?
        raise Refused, 'the section is too long' if text.bytesize > CONTENT_LIMIT

        job = ChatOutput.run_folder(session: session, workbench: workbench, app_name: app_name)
        raise Refused, "there is no chat folder to keep it in" unless job

        doc = slug(title, 60)
        section_path = ChatOutput.keep(job, "#{doc}--#{slug(key, 40)}.md", text)
        request_id = workbench.respond_to?(:request_id) ? workbench.request_id : nil
        folder = folder_of(job[:relative])
        made = made_lists(session) + [Made.pending(request_id)]
        path = rebuild(folder, doc, made, title: title)
        shown = show(path, workbench, slug(key, 40), request_id)
        { section_path: section_path, path: path, shown: shown }
      end

      # The chat folder (conversations/<folder>) a path of it is in.
      def folder_of(relative)
        relative.split('/').first(2).join('/')
      end

      # What the messages of session made, in order.
      def made_lists(session)
        Array(session && session[:messages]).map { |m| Made.clean(m.is_a?(Hash) ? m['workbench_made'] : nil) || [] }
      end

      # The sections of document doc found in what was made (lists of
      # paths, oldest first): { key => path } in the order first written,
      # each the newest.
      def sections(made, doc)
        made.each_with_object({}) do |paths, found|
          Array(paths).each do |path|
            section_files(path, doc).each { |key, file| found[key] = file }
          end
        end
      end

      # The section files of doc a path made holds (a run folder's files,
      # or the file itself), as [key, path].
      def section_files(path, doc)
        dir = Monadic::Workspace::Folders.real_path(path, :directory)
        names = if dir
                  Dir.children(dir).sort.map { |name| [name, File.join(path, name)] }
                else
                  [[File.basename(path), path]]
                end
        names.filter_map do |name, file|
          match = SECTION_FILE.match(name)
          next unless match && match[:document] == doc && Monadic::Workspace::Folders.real_path(file)

          [match[:section], file]
        end
      rescue SystemCallError
        []
      end

      # Puts document doc of the chat folder folder together from what was
      # made and writes it (title: its title; else the one it has). A
      # document with no section left is removed: it is made from the
      # sections, never by a turn. Returns its path, or nil when removed.
      def rebuild(folder, doc, made, title: nil)
        path = File.join(folder, DIRNAME, "#{doc}.md")
        heading = title || title_of(path) || doc
        found = sections(made, doc)
        return remove(path) if found.empty?

        parts = found.map do |key, file|
          body = File.read(Monadic::Workspace::Folders.real_path(file), encoding: 'UTF-8')
          "#{MARK} #{key}\n\n#{body.strip}\n"
        rescue SystemCallError
          nil
        end.compact
        text = "# #{heading.gsub(/[\r\n]+/, ' ')}\n\n#{parts.join("\n---\n\n")}"
        root = File.realpath(Monadic::Utils::Environment.data_path)
        Monadic::Utils::SharedPathGuard.mkdir_p!(File.join(root, folder, DIRNAME), strict: true)
        Monadic::Utils::SharedPathGuard.write_file!(File.join(root, path), text, mode: 'w', replace: true, strict: true)
        path
      end

      # Removes a document with no section left (a plain file of the chat's
      # documents folder, never a link). Returns nil.
      def remove(path)
        real = Monadic::Workspace::Folders.real_path(path)
        File.unlink(real) if real
        nil
      rescue SystemCallError
        nil
      end

      # The title a document was written under (its first line).
      def title_of(path)
        real = Monadic::Workspace::Folders.real_path(path)
        line = real && File.open(real, encoding: 'UTF-8', &:gets)
        line&.start_with?('# ') ? line.delete_prefix('# ').strip : nil
      rescue SystemCallError
        nil
      end

      # Puts every document of the chat folder of session together again
      # (after a turn was deleted), and refreshes those the work screen
      # shows. Returns the paths written.
      def rebuild_all(session)
        folder = Monadic::Workspace::Folders.lookup(session)
        return [] unless folder && folder[:status] == :ready

        dir = Monadic::Workspace::Folders.real_path(File.join(folder[:relative_dir], DIRNAME), :directory)
        return [] unless dir

        made = made_lists(session)
        removed = []
        written = Dir.children(dir).sort.filter_map do |name|
          next unless name.end_with?('.md')

          path = rebuild(folder[:relative_dir], name.delete_suffix('.md'), made)
          removed << File.join(folder[:relative_dir], DIRNAME, name) unless path
          path
        end
        chat_id = session[Monadic::Workspace::Chats::SESSION_KEY]
        refresh(chat_id, written)
        drop(chat_id, removed)
        written
      end

      # Takes removed documents off the work screen.
      def drop(chat_id, paths)
        board = chat_id && !paths.empty? && Board.existing(chat_id)
        Channel.changed(chat_id) if board && !board.drop_files(paths).empty?
      end

      # Every version of the sections of the document at path (a document of
      # the session's own chat folder), as the session's messages made them:
      # [{ 'section' =>, 'path' =>, 'version' => }], version counting the
      # section's versions from 1, oldest first. Empty for any other path.
      def versions(session, path)
        folder = Monadic::Workspace::Folders.lookup(session)
        return [] unless folder && folder[:status] == :ready

        match = %r{\A#{Regexp.escape(folder[:relative_dir])}/#{DIRNAME}/(?<doc>[a-z0-9-]{1,60})\.md\z}.match(path.to_s)
        return [] unless match

        counts = Hash.new(0)
        Array(session[:messages]).each_with_object([]) do |message, found|
          next unless message.is_a?(Hash) && message['role'] == 'assistant'

          Array(Made.clean(message['workbench_made'])).each do |made|
            section_files(made, match[:doc]).each do |key, file|
              found << { 'section' => key, 'path' => file, 'version' => (counts[key] += 1) }
            end
          end
        end
      end

      # The work screen's items of paths are read again, in place.
      def refresh(chat_id, paths)
        board = chat_id && Board.existing(chat_id)
        return unless board

        shown = paths.select do |path|
          board.snapshot[:items].any? { |item| item[:path] == path } &&
            board.add_file(path: path, origin: { actor: :assistant }, epoch: Monadic::Workspace::Chats.epoch(chat_id), wait: 0)
        rescue Board::Refused, FileItem::Busy
          false
        end
        Channel.changed(chat_id) unless shown.empty?
      end

      # Shows the document on the work screen (in place of the version
      # before), and records for the reply's message a line that opens it at
      # the section.
      def show(path, workbench, key, request_id)
        return false unless workbench

        board = Board.for(workbench.chat_id)
        item, = board.add_file(path: path, origin: workbench.origin, epoch: workbench.epoch)
        Shown.add(request_id, item, section: key) if request_id
        Channel.changed(workbench.chat_id)
        true
      rescue Board::Refused, FileItem::Busy
        false
      end
    end
  end
end
