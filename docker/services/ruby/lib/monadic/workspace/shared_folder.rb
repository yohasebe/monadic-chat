# frozen_string_literal: true

require 'securerandom'
require 'time'
require_relative 'ids'
require_relative 'ledger'
require_relative 'folders'
require_relative '../utils/environment'

module Monadic
  module Workspace
    # What the shared folder holds, for the page that shows it: one folder at
    # a time, each entry with its kind, size, what it is, whether it must not
    # be removed and whether a chat is using it. Read only; nothing here
    # changes a file.
    #
    # What an entry is comes from the ledger where the ledger says so (chat
    # folders, attachments' public copies) and otherwise only from its name,
    # reported as such: a name is never proof that a file is unused or safe
    # to remove. Links are listed as links and never followed.
    module SharedFolder
      class Invalid < StandardError; end

      # A random id kept in the shared folder. The desktop app reads it from
      # the folder it resolves on the host and acts on an entry only when it
      # matches, so it never acts on a different folder that happens to
      # have the same relative path.
      ROOT_ID_FILE = '.monadic-shared-root'

      # Entries at the top of the shared folder that Monadic Chat or the
      # user's own setup reads: never offered for removal, nor anything in
      # them. The value says why (a code the page words in its language).
      PROTECTED = {
        'scripts' => 'user_scripts',
        'apps' => 'user_apps',
        'helpers' => 'user_apps',
        'services' => 'user_services',
        'compose_user.yml' => 'user_services',
        '.help-installation' => 'help_install',
        '.browser_session_id' => 'browser_session',
        'monadic-qdrant.tar.gz' => 'database_backup',
        'monadic-qdrant.tar.gz.enc' => 'database_backup',
        ROOT_ID_FILE => 'folder_id'
      }.freeze

      # Folders at the top whose contents are kept for a purpose.
      FOLDERS = {
        Folders::ROOT_DIRNAME => 'chat_folders',
        'auto_forge' => 'projects',
        'transcriptions' => 'transcriptions',
        'documents' => 'documents',
        'library' => 'library_sources'
      }.freeze

      GENERATED_EXTENSIONS = %w[
        .png .jpg .jpeg .gif .webp .svg .bmp .tiff
        .mp3 .wav .m4a .ogg .opus .flac .aac .mid .midi
        .mp4 .webm .mov .mkv
        .drawio .tex .vtt .srt .ipynb .html .pdf
      ].freeze

      # Files that look like what a tool leaves while working. A candidate
      # only: the user can name a file this way too.
      INTERMEDIATE_PATTERNS = [
        /\A\d{10}_[0-9a-f]{8}\.md\z/,   # text given to speech
        /\A\d{10}\.json\z/,             # notebook cells sent in one go
        /\A\d{10}\.pdf\z/,              # a PDF copied for text extraction
        /\.md\.json\z/,                 # text extraction output
        /\Asyntree_\d+\./,              # syntax tree drawing steps
        /\.part-\d+\z/                  # a copy that was not finished
      ].freeze

      PER_PAGE = 200

      module_function

      def data_root
        File.realpath(Monadic::Utils::Environment.data_path)
      end

      # The shared folder's id, made the first time it is asked for: the
      # one write this module does. The id is written to a file of its own
      # and then linked into place, so nobody reads a file still empty, and
      # two first requests end with one id.
      def root_id(root = data_root)
        path = File.join(root, ROOT_ID_FILE)
        unless File.exist?(path) || File.symlink?(path)
          temp = File.join(root, "#{ROOT_ID_FILE}.#{SecureRandom.hex(6)}")
          begin
            File.open(temp, File::WRONLY | File::CREAT | File::EXCL, 0o644) { |f| f.write(SecureRandom.hex(16)) }
            File.link(temp, path)
          rescue Errno::EEXIST
            nil
          ensure
            File.unlink(temp) if File.exist?(temp)
          end
        end
        raise Invalid, "#{ROOT_ID_FILE} is not a plain file" unless File.lstat(path).file?

        id = File.read(path, 64).to_s.strip
        raise Invalid, "#{ROOT_ID_FILE} does not hold an id" unless id.match?(/\A[0-9a-f]{32}\z/)

        id
      end

      # The id, or why there is none (the folder may be read-only): the list
      # is shown either way, only showing entries on this computer needs it.
      def root_id_or_reason(root)
        [root_id(root), nil]
      rescue Invalid, SystemCallError => e
        [nil, e.is_a?(Invalid) ? e.message : e.class.name.split('::').last]
      end

      MAX_NAMES = 20_000 # names read from one folder for one listing

      # One page of the folder at relative ("" for the shared folder itself).
      # live_chat_ids are the chats open in some tab; their folders are
      # reported as in use. sizes gives what the background count knows of
      # each folder's size. A folder with more than MAX_NAMES entries is
      # listed from the first MAX_NAMES read (truncated).
      def list(relative = '', page: 1, per_page: PER_PAGE, live_chat_ids: [], ledger: Ledger.default, sizes: nil)
        root = data_root
        id, id_problem = root_id_or_reason(root) # made before the listing, so it is listed too
        parts = parts_of(relative)
        dir = folder_at(root, parts)
        names = []
        truncated = false
        Dir.each_child(dir) do |name|
          if names.size >= MAX_NAMES
            truncated = true
            break
          end
          names << name
        end
        names.sort!
        page = [page.to_i, 1].max
        per_page = per_page.to_i.clamp(1, 1000)
        shown = names.slice((page - 1) * per_page, per_page) || []

        index = ledger_index(ledger, live_chat_ids)
        items = shown.map { |name| describe(dir, parts, name, index, sizes, reveal: !id.nil?) }.compact

        { root_id: id, root_id_problem: id_problem, path: parts.join('/'), total: names.size, truncated: truncated,
          page: page, per_page: per_page, items: items, ledger_readable: !index[:unreadable],
          listed_at: Time.now.utc.iso8601 }
      end

      # What the background count knows of the given folders, without
      # listing anything (what the page asks for while counts finish).
      def sizes_of(relatives, sizes:)
        root = data_root
        Array(relatives).first(PER_PAGE).each_with_object({}) do |relative, out|
          parts = parts_of(relative)
          next if parts.empty?

          folder_at(root, parts)
          known = sizes.lookup(parts.join('/'))
          out[parts.join('/')] = known ? { bytes: known[:bytes], files: known[:files], size_status: known[:status], size_at: known[:at] } : { size_status: 'pending' }
        rescue Invalid
          out[relative.to_s] = { size_status: 'vanished' }
        end
      end

      # The relative path as its parts, refused when it could leave the
      # shared folder or name something other than a folder in it.
      def parts_of(relative)
        text = relative.to_s
        raise Invalid, 'the path is not text' if text.include?("\0") || text.include?('\\')
        return [] if text.empty?
        raise Invalid, 'the path is not relative' if text.start_with?('/')

        parts = text.split('/')
        raise Invalid, 'the path has an empty, . or .. part' if parts.any? { |p| p.empty? || p == '.' || p == '..' }

        parts
      end

      # The folder reached by parts from root, with no link at any level.
      def folder_at(root, parts)
        dir = root
        parts.each do |part|
          dir = File.join(dir, part)
          stat = File.lstat(dir)
          raise Invalid, 'the path goes through a link' if stat.symlink?
          raise Invalid, 'the path is not a folder' unless stat.directory?
        end
        dir
      rescue Errno::ENOENT, Errno::ENOTDIR
        raise Invalid, 'the folder is not there'
      end

      def ledger_index(ledger, live_chat_ids)
        snapshot = ledger.snapshot
        by_dir = {}
        snapshot[:workspaces].each do |workspace_id, record|
          by_dir[record['relative_dir']] = record.merge('workspace_id' => workspace_id)
        end
        { workspaces: by_dir, attachments: snapshot[:attachments], live: live_chat_ids.compact.to_a }
      rescue Ledger::Unreadable, SystemCallError
        { workspaces: {}, attachments: {}, live: live_chat_ids.compact.to_a, unreadable: true }
      end

      def describe(dir, parts, name, index, sizes, reveal: true)
        path = File.join(dir, name)
        stat = File.lstat(path)
        relative = (parts + [name]).join('/')
        kind = if stat.symlink? then 'link'
               elsif stat.directory? then 'folder'
               elsif stat.file? then 'file'
               else 'other'
               end
        item = { name: name, path: relative, kind: kind, modified_at: stat.mtime.utc.iso8601 }
        item.merge!(size_of(kind, stat, relative, sizes))
        item.merge!(what_it_is(parts, name, kind, index))
        protected_reason = PROTECTED[parts.first || name]
        item[:protected_reason] = protected_reason if protected_reason
        item[:capabilities] = { reveal: reveal && %w[file folder].include?(kind) }
        item
      rescue Errno::ENOENT
        nil # gone between the listing and the look
      end

      def size_of(kind, stat, relative, sizes)
        case kind
        when 'file' then { bytes: stat.size, size_status: 'complete' }
        when 'folder'
          known = sizes&.lookup(relative)
          known ? { bytes: known[:bytes], files: known[:files], size_status: known[:status], size_at: known[:at] } : { size_status: 'pending' }
        else { size_status: 'none' }
        end
      end

      def what_it_is(parts, name, kind, index)
        top = parts.first || name
        return { classification: 'protected', classification_source: 'name' } if PROTECTED.key?(top)

        if parts.empty?
          return { classification: FOLDERS[name], classification_source: 'name' } if FOLDERS.key?(name) && kind == 'folder'

          return public_copy(name, index) if name.start_with?('pub_')
          return { classification: 'intermediate_candidate', classification_source: 'name' } if INTERMEDIATE_PATTERNS.any? { |re| re.match?(name) }
          return { classification: 'generated', classification_source: 'name' } if kind == 'file' && GENERATED_EXTENSIONS.include?(File.extname(name).downcase)

          return { classification: 'other', classification_source: 'none' }
        end

        if parts == [Folders::ROOT_DIRNAME]
          record = index[:workspaces]["#{Folders::ROOT_DIRNAME}/#{name}"]
          return { classification: 'chat_folder', classification_source: 'none' } unless record

          info = { classification: 'chat_folder', classification_source: 'ledger', owner_chat_id: record['chat_id'],
                   app_name: record['app_name'], created_at: record['created_at'] }
          info[:busy_reason] = 'open_in_tab' if index[:live].include?(record['chat_id'])
          return info
        end

        { classification: FOLDERS[top] || 'other', classification_source: FOLDERS.key?(top) ? 'name' : 'none' }
      end

      # pub_<attachment id>.<ext> is tied to its chat when the ledger has the
      # attachment; any other pub_ file is a copy whose chat is not known.
      def public_copy(name, index)
        id = name[/\Apub_(a_[a-z0-9]{16})\./, 1]
        record = id && Ids.valid?(:attachment, id) ? index[:attachments][id] : nil
        return { classification: 'public_copy', classification_source: 'name' } unless record

        { classification: 'public_copy', classification_source: 'ledger', owner_chat_id: record['chat_id'] }
      end
    end
  end
end
