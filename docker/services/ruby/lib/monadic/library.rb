# frozen_string_literal: true

# Convenience entry point for the Library subsystem. Pulls in the schema
# validator, format-version constant, and the Qdrant-backed Store facade.
#
# Library is the unified Knowledge Base across all Monadic Chat apps. It
# is project-wide; cross-app retrieval is gated by the per-conversation
# `scope_app` payload value (an app class name or the literal "Global").

require_relative 'library/version'
require_relative 'library/schema'
require_relative 'library/store'
require_relative 'library/importers'
require_relative 'library/turn_segmenter'
require_relative 'library/hierarchical'
require_relative 'library/retriever'
require_relative 'library/manager'
require_relative 'library/inventory'
require_relative 'library/file_importer'
require_relative 'library/title_suggester'
require_relative 'library/import_tracker'
