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
      VERSION = 1
      COLLECTIONS = %w[chats workspaces attachments artifacts publications].freeze
      ATTACHMENT_STATES = %w[validating ready failed].freeze
      SHA256 = /\A[0-9a-f]{64}\z/

      # Wrong form (as opposed to JSON that cannot be read at all).
      class Shape < StandardError; end
      # Written by a newer version.
      class Newer < StandardError; end

      module_function

      # Fills in empty collections for a ledger that has none yet and checks
      # the whole of it. Returns data.
      def check!(data)
        raise Shape, 'the ledger is not an object' unless data.is_a?(Hash)

        version!(data)
        # A collection that is not there yet is added empty; one that is
        # there must be an object (null is not taken for empty).
        COLLECTIONS.each do |name|
          data[name] = {} unless data.key?(name)
          raise Shape, "#{name} is not an object" unless data[name].is_a?(Hash)
        end
        chats!(data)
        workspaces!(data)
        attachments!(data)
        ids!(data['artifacts'], :artifact, 'artifacts')
        ids!(data['publications'], :publication, 'publications')
        data
      end

      def version!(data)
        unless data.key?('schema_version')
          has_records = COLLECTIONS.any? { |name| data[name].is_a?(Hash) && !data[name].empty? }
          raise Shape, 'schema_version is missing' if has_records

          data['schema_version'] = VERSION
          return
        end
        version = data['schema_version']
        raise Shape, 'schema_version is not a whole number' unless version.is_a?(Integer)
        raise Newer, "ledger schema #{version} is newer than this version understands" if version > VERSION
        raise Shape, 'schema_version is out of range' if version < 1
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

          contents!(record, required: record['status'] == 'ready')
          raise Shape, 'attachments.failure is not text' if record.key?('failure') && !record['failure'].is_a?(String)

          time!(record['created_at'], 'attachments.created_at')
        end
      end

      # size and sha256: required on a ready attachment, of their form
      # wherever they are.
      def contents!(record, required:)
        raise Shape, 'a ready attachment has no size' if required && !record.key?('size')
        raise Shape, 'a ready attachment has no sha256' if required && !record.key?('sha256')
        if record.key?('size') && !(record['size'].is_a?(Integer) && record['size'] >= 0)
          raise Shape, 'attachments.size is not a count of bytes'
        end
        if record.key?('sha256') && !(record['sha256'].is_a?(String) && SHA256.match?(record['sha256']))
          raise Shape, 'attachments.sha256 is not a sha256'
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
