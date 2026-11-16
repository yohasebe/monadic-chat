# frozen_string_literal: true

# Entry point for the store of the MCP server's knowledge bases. Pulls in
# the Store class so callers can write `Monadic::Pdf::Store.new(...)`.

require_relative 'pdf/store'
