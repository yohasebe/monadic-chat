# frozen_string_literal: true

# Convenience entry point for the PDF storage subsystem. Pulls in the
# Store class so callers can write `Monadic::Pdf::Store.new(...)`.

require_relative 'pdf/store'

module Monadic
  module Pdf
    module_function

    # Construct a Store scoped to the calling app. Falls back to the
    # 'global' scope used by the generic /pdf upload route.
    def store_for(app_key: Store::DEFAULT_APP_KEY)
      Store.new(app_key: app_key)
    end
  end
end
