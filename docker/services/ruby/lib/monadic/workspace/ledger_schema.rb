# frozen_string_literal: true

require 'time'
require_relative 'ids'

module Monadic
  module Workspace
    # The form the ledger must have, checked whenever it is read and before a
    # change is saved: ids of the right kind, records that point at each
    # other, paths inside the chat's folder, and what a ready attachment must
    # carry. A record may hold fields it does not know (a later version may
    # add some); a known field must have its form. Messages name the field,
    # never an id or a name from the ledger.
    module LedgerSchema
      VERSION = 2
      # Collections a version 1 ledger had; version 2 adds the rest.
      V1_COLLECTIONS = %w[chats workspaces attachments].freeze
      COLLECTIONS = %w[chats workspaces attachments artifacts publications].freeze
      # Collections version 2 sets aside for records this version does not
      # make yet: only empty ones are taken (a later version that makes them
      # defines their form, and an earlier one never writes over them).
      RESERVED = [].freeze
      ATTACHMENT_STATES = %w[validating ready failed].freeze
      # What the server makes, by kind, and the name it has (the same in the
      # state folder and in the run folder's copy).
      ARTIFACT_KINDS = { 'subtitle_vtt' => 'transcript.vtt', 'subtitle_srt' => 'transcript.srt' }.freeze
      ARTIFACT_STATES = %w[ready].freeze
      # Folders of the shared folder that hold runs asked for from outside
      # any chat (the MCP server).
      OUTSIDE_ROOTS = %w[transcriptions].freeze
      SHA256 = /\A[0-9a-f]{64}\z/
      # A publication is a checked copy of an attachment or an artifact that
      # the page loads by its own name (/data/<name>). Pending while it is
      # being made (by the operation holding the token), ready while it may
      # be served; missing when its copy was found gone, revoked when its
      # chat's folder was.
      PUBLICATION_STATES = %w[pending ready missing revoked].freeze
      PUBLICATION_LIVE = %w[pending ready].freeze
      # What may be published, by extension, and the type it is served with.
      PUBLICATION_TYPES = {
        'mp4' => 'video/mp4', 'm4v' => 'video/x-m4v', 'mov' => 'video/quicktime', 'webm' => 'video/webm',
        'mp3' => 'audio/mpeg', 'm4a' => 'audio/mp4', 'wav' => 'audio/wav',
        'vtt' => 'text/vtt', 'srt' => 'application/x-subrip'
      }.freeze
      # pub_<the random part of the publication id>.<ext>
      PUBLICATION_NAME = /\Apub_([a-z0-9]{16})\.([a-z0-9]{1,5})\z/
      TOKEN = /\A[0-9a-f]{16}\z/

      # Wrong form (as opposed to JSON that cannot be read at all).
      class Shape < StandardError; end
      # Written by a newer version.
      class Newer < StandardError; end

      module_function

      # Checks a ledger as read from disk and returns it in the form of the
      # current version, with the version it was written in: [data, version].
      # A version 1 ledger is checked as version 1 and then given what
      # version 2 adds; nothing is written here. A file with nothing in it
      # yet ({}) counts as version 1.
      def check!(data)
        raise Shape, 'the ledger is not an object' unless data.is_a?(Hash)

        version = version_of(data)
        version == 1 ? from_v1(data) : present!(data, COLLECTIONS)
        current!(data)
        [data, version]
      end

      # Checks a ledger in the form of the current version (before it is
      # saved).
      def check_current!(data)
        raise Shape, 'the ledger is not an object' unless data.is_a?(Hash)
        raise Shape, 'schema_version is not the current one' unless data['schema_version'] == VERSION

        present!(data, COLLECTIONS)
        current!(data)
        data
      end

      def version_of(data)
        unless data.key?('schema_version')
          has_records = COLLECTIONS.any? { |name| data[name].is_a?(Hash) && !data[name].empty? }
          raise Shape, 'schema_version is missing' if has_records

          return 1
        end
        version = data['schema_version']
        raise Shape, 'schema_version is not a whole number' unless version.is_a?(Integer)
        raise Newer, "ledger schema #{version} is newer than this version understands" if version > VERSION
        raise Shape, 'schema_version is out of range' if version < 1

        version
      end

      # A version 1 ledger: its collections may be missing (an empty ledger)
      # but not null; artifacts and publications, which a version 1 ledger
      # may carry empty, must be empty.
      def from_v1(data)
        COLLECTIONS.each do |name|
          data[name] = {} unless data.key?(name)
          raise Shape, "#{name} is not an object" unless data[name].is_a?(Hash)
        end
        data['schema_version'] = VERSION
      end

      def present!(data, names)
        names.each do |name|
          raise Shape, "#{name} is missing" unless data.key?(name)
          raise Shape, "#{name} is not an object" unless data[name].is_a?(Hash)
        end
      end

      def current!(data)
        chats!(data)
        workspaces!(data)
        attachments!(data)
        artifacts!(data)
        publications!(data)
        RESERVED.each { |name| raise Shape, "#{name} holds records this version does not know" unless data[name].empty? }
      end

      def chats!(data)
        ids!(data['chats'], :chat, 'chats')
        data['chats'].each_value do |chat|
          workspace_id = chat['workspace_id']
          raise Shape, 'a chat has no valid workspace_id' unless Ids.valid?(:workspace, workspace_id)
          time!(chat['created_at'], 'chats.created_at')
        end
        data['chats'].each do |chat_id, chat|
          workspace = data['workspaces'][chat['workspace_id']]
          raise Shape, 'a chat names a workspace that is not its own' unless workspace.is_a?(Hash) && workspace['chat_id'] == chat_id
        end
      end

      def workspaces!(data)
        ids!(data['workspaces'], :workspace, 'workspaces')
        dirs = {}
        data['workspaces'].each do |workspace_id, workspace|
          chat_id = workspace['chat_id']
          raise Shape, 'a workspace has no valid chat_id' unless Ids.valid?(:chat, chat_id)
          unless data['chats'].dig(chat_id, 'workspace_id') == workspace_id
            raise Shape, 'a workspace names a chat that is not its own'
          end

          dir = workspace['relative_dir']
          relative!(dir, 'workspaces.relative_dir')
          raise Shape, 'two workspaces share a folder' if dirs.key?(dir)

          dirs[dir] = true
          raise Shape, 'workspaces.app_name is not text' unless workspace['app_name'].is_a?(String)

          time!(workspace['created_at'], 'workspaces.created_at')
        end
      end

      def attachments!(data)
        ids!(data['attachments'], :attachment, 'attachments')
        data['attachments'].each_value do |record|
          workspace = data['workspaces'][record['workspace_id']]
          unless workspace.is_a?(Hash) && Ids.valid?(:chat, record['chat_id']) && workspace['chat_id'] == record['chat_id']
            raise Shape, 'an attachment does not belong to a workspace of its chat'
          end

          path = record['relative_path']
          relative!(path, 'attachments.relative_path')
          raise Shape, 'an attachment is outside its chat folder' unless path.start_with?("#{workspace['relative_dir']}/")

          %w[purpose original_name].each { |key| raise Shape, "attachments.#{key} is not text" unless record[key].is_a?(String) }
          raise Shape, 'attachments.status is unknown' unless ATTACHMENT_STATES.include?(record['status'])

          contents!(record, 'attachments', required: record['status'] == 'ready')
          raise Shape, 'attachments.failure is not text' if record.key?('failure') && !record['failure'].is_a?(String)

          time!(record['created_at'], 'attachments.created_at')
        end
      end

      # An artifact belongs to a chat (its workspace's run folder) or to a
      # folder for runs outside any chat; its copy_path is exactly where the
      # run folder's copy is, built from that owner, the job and the kind.
      def artifacts!(data)
        ids!(data['artifacts'], :artifact, 'artifacts')
        data['artifacts'].each_value do |record|
          base = artifact_base(data, record)
          raise Shape, 'artifacts.job_id is not a job id' unless Ids.valid?(:job, record['job_id'])

          name = ARTIFACT_KINDS[record['kind']]
          raise Shape, 'artifacts.kind is unknown' unless name
          unless record['copy_path'] == "#{base}/artifacts/#{record['job_id']}/#{name}"
            raise Shape, 'artifacts.copy_path is not the run folder of its owner'
          end

          contents!(record, 'artifacts', required: true)
          raise Shape, 'artifacts.status is unknown' unless ARTIFACT_STATES.include?(record['status'])

          time!(record['created_at'], 'artifacts.created_at')
        end
      end

      # A publication names its source (a ready attachment or artifact of its
      # chat) with the source's sha256, carries the source's size and sha256,
      # and has a name of its own that no other publication has. One source
      # has at most one publication pending or ready.
      def publications!(data)
        ids!(data['publications'], :publication, 'publications')
        names = {}
        live = {}
        data['publications'].each do |publication_id, record|
          name = record['name']
          random, ext = name.is_a?(String) && name.match(PUBLICATION_NAME)&.captures
          raise Shape, 'publications.name is not a public name' unless ext && PUBLICATION_TYPES.key?(ext)
          raise Shape, 'publications.name is not made from its id' unless "p_#{random}" == publication_id
          raise Shape, 'two publications share a name' if names.key?(name)

          names[name] = true
          raise Shape, 'publications.content_type does not go with its name' unless record['content_type'] == PUBLICATION_TYPES[ext]

          source = publication_source!(data, record)
          contents!(record, 'publications', required: true)
          unless record['size'] == source['size'] && record['sha256'] == source['sha256']
            raise Shape, 'a publication does not carry the size and sha256 of its source'
          end
          raise Shape, 'publications.status is unknown' unless PUBLICATION_STATES.include?(record['status'])

          token!(record)
          if PUBLICATION_LIVE.include?(record['status'])
            key = record['source'].values_at('kind', 'id')
            raise Shape, 'one source has two publications pending or ready' if live.key?(key)

            live[key] = true
          end
          time!(record['created_at'], 'publications.created_at')
        end
      end

      def publication_source!(data, record)
        source = record['source']
        raise Shape, 'publications.source is not an object' unless source.is_a?(Hash)

        target = case source['kind']
                 when 'attachment' then Ids.valid?(:attachment, source['id']) && data['attachments'][source['id']]
                 when 'artifact' then Ids.valid?(:artifact, source['id']) && data['artifacts'][source['id']]
                 else raise Shape, 'publications.source.kind is unknown'
                 end
        raise Shape, 'a publication names no ready record as its source' unless target.is_a?(Hash) && target['status'] == 'ready'
        unless Ids.valid?(:chat, record['chat_id']) && target['chat_id'] == record['chat_id']
          raise Shape, 'a publication is not of the chat of its source'
        end
        raise Shape, 'publications.source.sha256 is not the sha256 of its source' unless source['sha256'] == target['sha256']

        target
      end

      def token!(record)
        if record['status'] == 'pending'
          raise Shape, 'a pending publication has no token' unless record['token'].is_a?(String) && TOKEN.match?(record['token'])
        elsif record.key?('token')
          raise Shape, 'a publication that is not pending has a token'
        end
      end

      def artifact_base(data, record)
        case record['owner']
        when 'chat'
          workspace = data['workspaces'][record['workspace_id']]
          unless workspace.is_a?(Hash) && Ids.valid?(:chat, record['chat_id']) && workspace['chat_id'] == record['chat_id']
            raise Shape, 'an artifact does not belong to a workspace of its chat'
          end
          raise Shape, 'an artifact of a chat has a root' if record.key?('root')

          workspace['relative_dir']
        when 'outside'
          if record.key?('chat_id') || record.key?('workspace_id')
            raise Shape, 'an artifact outside any chat names a chat or a workspace'
          end
          raise Shape, 'artifacts.root is not a folder for runs outside any chat' unless OUTSIDE_ROOTS.include?(record['root'])

          record['root']
        else
          raise Shape, 'artifacts.owner is unknown'
        end
      end

      # size and sha256: required on a ready record, of their form wherever
      # they are.
      def contents!(record, name, required:)
        raise Shape, "#{name}: a ready record has no size" if required && !record.key?('size')
        raise Shape, "#{name}: a ready record has no sha256" if required && !record.key?('sha256')
        if record.key?('size') && !(record['size'].is_a?(Integer) && record['size'] >= 0)
          raise Shape, "#{name}.size is not a count of bytes"
        end
        if record.key?('sha256') && !(record['sha256'].is_a?(String) && SHA256.match?(record['sha256']))
          raise Shape, "#{name}.sha256 is not a sha256"
        end
      end

      def ids!(collection, kind, name)
        collection.each do |id, record|
          raise Shape, "#{name} has a key that is not an id of its kind" unless Ids.valid?(kind, id)
          raise Shape, "#{name} has a record that is not an object" unless record.is_a?(Hash)
        end
      end

      def relative!(path, name)
        valid = path.is_a?(String) && !path.empty? && !path.start_with?('/') &&
                !path.split('/').include?('..') && !path.include?("\0")
        raise Shape, "#{name} is not a path inside the shared folder" unless valid
      end

      def time!(value, name)
        Time.iso8601(value)
      rescue ArgumentError, TypeError
        raise Shape, "#{name} is not a time"
      end
    end
  end
end
