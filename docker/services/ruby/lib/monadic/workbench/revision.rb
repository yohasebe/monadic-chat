# frozen_string_literal: true

require_relative '../utils/environment'
require_relative '../utils/shared_fs'
require_relative '../workspace/ledger'
require_relative 'shown'
require_relative 'turn_trash'

module Monadic
  module Workbench
    # What a reply changes in place that an earlier turn made in the chat's
    # folder (a project folder, a file). Before the reply's first change it
    # is copied as it is to <chat folder>/revisions/<label>/<its path in the
    # folder>, and the reply's message keeps { "path", "before" }
    # (Workbench::Made). Deleting that message, or a reply stopped before
    # its message, puts it back: what the reply made of it goes to the
    # trash and the copy takes its place (undo).
    module Revision
      DIRNAME = 'revisions'

      module_function

      # Keeps path (relative to the shared folder, inside the folder of the
      # chat chat_id) as it is now, before the running reply request_id
      # changes it. Once per reply and path; nothing for what the reply made
      # itself, or for what is not there. Returns the revision or nil.
      def keep!(request_id, path, chat_id:)
        return nil unless request_id && chat_id && Shown.running?(request_id)
        return nil if Made.handled?(request_id, path)

        folder = folder_of(chat_id)
        rest = folder && TurnTrash.inside(folder, path)
        return nil unless rest && rest.first != DIRNAME

        label = TurnTrash.label("before-#{request_id}")
        return nil unless copy(folder, rest, [DIRNAME, label] + rest)

        Made.revise(request_id, path, File.join(folder, DIRNAME, label, *rest), chat_id: chat_id)
      end

      # Puts back what revisions (of a deleted message, or of a stopped
      # reply) changed in the chat folder folder_dir; label names the part
      # of the trash it goes to. later: the revisions of the messages after
      # it, in order. When a later one changed the same thing again, nothing
      # is put back now: that later revision takes this one's copy (its own
      # goes to the trash), so deleting it later puts back the state before
      # both. Returns the paths put back.
      def undo(folder_dir, revisions, label, later: [])
        revisions.each_with_object([]) do |rev, put_back|
          path = rev['path']
          before = rev['before']
          next unless TurnTrash.inside(folder_dir, path) && TurnTrash.inside(folder_dir, before)&.first == DIRNAME

          following = later.find { |other| other['path'] == path }
          if following
            TurnTrash.move(folder_dir, [following['before']], label)
            following['before'] = before
          elsif present?(path)
            moved = TurnTrash.move(folder_dir, [path], label)
            put_back << path if moved == [path] && TurnTrash.put_back(folder_dir, before, path)
          else
            TurnTrash.move(folder_dir, [before], label)
          end
        end
      end

      # The chat's folder (relative to the shared folder), or nil.
      def folder_of(chat_id)
        Monadic::Workspace::Ledger.default.workspace_for_chat(chat_id)&.[](:relative_dir)
      rescue Monadic::Workspace::Ledger::Unreadable
        nil
      end

      def present?(path)
        File.exist?(File.join(Monadic::Utils::Environment.data_path, path)) ||
          File.symlink?(File.join(Monadic::Utils::Environment.data_path, path))
      end

      # Copies what is at from (parts below the chat folder folder_dir) to
      # to, a new place in it. True when it was copied.
      def copy(folder_dir, from, to)
        base = folder_dir.split('/')
        copy_tree(base + from, base + to)
      end

      # Copies what is at from (parts below the shared folder) to to, a new
      # place: a file, or a folder with everything in it. Links are left out
      # and never followed. True when it was copied.
      def copy_tree(from, to)
        root = File.realpath(Monadic::Utils::Environment.data_path)
        fs = Monadic::Utils::SharedFs
        fs.in_dir(root, from[0..-2]) do |from_dir|
          return false unless fs.entry(from_dir, from.last).is_a?(File::Stat)
        end
        fs.in_dir(root, to[0..-2], create: true) do |to_dir|
          return false if fs.entry(to_dir, to.last)

          copy_entry(root, from, to_dir, to.last, 0)
        end
        true
      rescue Monadic::Utils::SharedFs::Unsafe, SystemCallError, IOError => e
        warn "[Revision] #{File.join(*from)} was not copied: #{e.class.name.split('::').last}"
        false
      end

      # Each folder is opened from the shared folder down, never through a
      # link; a listing is only a hint of the names to try.
      def copy_entry(root, from, to_dir, to_name, depth)
        fs = Monadic::Utils::SharedFs
        raise fs::Unsafe, 'the folder is too deep' if depth > fs::TREE_DEPTH

        fs.in_dir(root, from[0..-2]) do |from_dir|
          found = fs.entry(from_dir, from.last)
          next unless found.is_a?(File::Stat)

          if found.directory?
            names = Dir.children(File.join(root, *from))
            fs.make_dir(to_dir, to_name) do |made|
              names.each { |name| copy_entry(root, from + [name], made, name, depth + 1) }
            end
          elsif found.file?
            source = fs.open_read(from_dir, from.last)
            begin
              fs.write_new(to_dir, to_name, perm: found.mode & 0o777, replace: false) { |out| IO.copy_stream(source, out) }
            ensure
              source.close
            end
          end
        end
      end
      private_class_method :copy_entry, :present?
    end
  end
end
