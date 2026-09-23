# frozen_string_literal: true

require_relative 'help/installation'

module Monadic
  module Help
    # Construct on demand. Availability and search connections are never cached.
    # Installation coordinates independent instances through filesystem locks.
    def self.installation
      default_dump = if Utils::Environment.in_container?
                       Installation::DEFAULT_DUMP
                     else
                       File.expand_path('../../help_data/help_db.json', __dir__)
                     end
      Installation.new(dump_path: ENV.fetch('HELP_DATA_DUMP', default_dump))
    end
  end
end
