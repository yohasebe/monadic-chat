# frozen_string_literal: true

require 'json'
require 'securerandom'
require_relative 'store'
require_relative '../workspace/ids'

module Monadic
  module Workbench
    # What the work screen held when a turn ended, kept so that the turn's
    # card can show it later: the user's turn ends when their message is
    # accepted, the reply's when it ends. One record per turn (its request
    # and who took it), a file of its own in the chat's workbench folder
    # (turns/<request>.<user|agent>.json), taken under the board's lock just
    # before its layers move, and deleted with the turn's message.
    #
    # A record: { 'request_id', 'by', 'at', 'items' (the desk: Now, Latest,
    # Before, in their order, each as the page draws it, with the marks
    # shown on it then), 'put_away' (how many were put away) }.
    module TurnRecords
      DIRNAME = 'turns'
      BY = %w[user agent].freeze

      module_function

      def write(chat_id, request_id, by, record, store: Store.default)
        path = path_of(chat_id, request_id, by, store: store, make: true) or return nil
        temp = "#{path}.#{SecureRandom.hex(6)}"
        File.write(temp, JSON.generate(record.merge('request_id' => request_id, 'by' => by)))
        File.rename(temp, path)
        path
      end

      # The record of the turn, or nil when none was kept.
      def read(chat_id, request_id, by, store: Store.default)
        path = path_of(chat_id, request_id, by, store: store) or return nil
        return nil unless File.file?(path) && !File.symlink?(path)

        data = JSON.parse(File.read(path))
        data.is_a?(Hash) ? data : nil
      rescue JSON::ParserError, SystemCallError
        nil
      end

      def delete(chat_id, request_id, by, store: Store.default)
        path = path_of(chat_id, request_id, by, store: store) or return
        File.delete(path) if File.file?(path)
      rescue SystemCallError
        nil
      end

      # The file of a turn's record, or nil for a request or a side that is
      # not one.
      def path_of(chat_id, request_id, by, store:, make: false)
        return nil unless BY.include?(by) && Monadic::Workspace::Ids.valid?(:request, request_id.to_s)

        dir = File.join(store.chat_dir(chat_id, make: make), DIRNAME)
        if make && !File.directory?(dir)
          Dir.mkdir(dir, 0o700)
        end
        File.join(dir, "#{request_id}.#{by}.json")
      rescue ArgumentError, Errno::EEXIST
        File.join(store.chat_dir(chat_id), DIRNAME, "#{request_id}.#{by}.json")
      end
    end
  end
end
