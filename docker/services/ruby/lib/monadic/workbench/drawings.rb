# frozen_string_literal: true

require 'json'
require 'digest'
require 'securerandom'
require_relative 'store'
require_relative '../workspace/ledger'

module Monadic
  module Workbench
    # What the user drew on an image of the work screen, as each message sent
    # it: the shapes one message added, kept once by their digest in the
    # chat's workbench folder (drawings/<sha256>.json), named by the marks'
    # operations (Marks: draw, erase_drawing) and the turns' records. They go
    # with the chat.
    module Drawings
      DIRNAME = 'drawings'
      DIGEST = /\A\h{64}\z/

      module_function

      # Keeps shapes (as the server checked them) and returns their digest.
      def keep!(chat_id, shapes, store: Store.default)
        json = JSON.generate(shapes)
        digest = Digest::SHA256.hexdigest(json)
        dir = store.chat_subdir(chat_id, DIRNAME, make: true)
        path = File.join(dir, "#{digest}.json")
        return digest if File.file?(path)

        disk = Monadic::Workspace::Ledger::Disk
        temp = File.join(dir, ".#{digest}.#{SecureRandom.hex(6)}")
        disk.create_exclusive(temp, json)
        disk.replace(temp, path)
        digest
      end

      # The shapes kept as digest, or nil.
      def read(chat_id, digest, store: Store.default)
        return nil unless digest.is_a?(String) && digest.match?(DIGEST)

        path = File.join(store.chat_subdir(chat_id, DIRNAME), "#{digest}.json")
        return nil unless File.file?(path) && !File.symlink?(path)

        shapes = JSON.parse(File.read(path))
        shapes.is_a?(Array) ? shapes : nil
      rescue JSON::ParserError, SystemCallError, ArgumentError
        nil
      end
    end
  end
end
