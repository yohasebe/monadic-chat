# frozen_string_literal: true

# The Library's importers: each module under Monadic::Library::Importers::*
# converts a file's content into a Hash conforming to the
# monadic-conversation v1 schema (FileImporter picks one by extension).

require_relative 'importers/base'
require_relative 'importers/markdown'
require_relative 'importers/code'
require_relative 'importers/pdf'
require_relative 'importers/office'
