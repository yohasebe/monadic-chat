# frozen_string_literal: true

require 'securerandom'

module Monadic
  module Workspace
    # Identifiers are random and lowercase so they survive case-insensitive
    # file systems when they become part of a folder name. Nothing else
    # (file names, times, app names) identifies a chat or a workspace.
    module Ids
      ALPHABET = [*'a'..'z', *'0'..'9'].freeze
      LENGTH = 16
      PREFIXES = { chat: 'c', workspace: 'w', attachment: 'a', job: 'j' }.freeze

      module_function

      def generate(kind)
        "#{PREFIXES.fetch(kind)}_#{SecureRandom.alphanumeric(LENGTH, chars: ALPHABET)}"
      end

      def valid?(kind, value)
        value.is_a?(String) && value.match?(/\A#{PREFIXES.fetch(kind)}_[a-z0-9]{#{LENGTH}}\z/)
      end
    end
  end
end
