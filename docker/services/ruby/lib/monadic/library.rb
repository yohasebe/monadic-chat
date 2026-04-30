# frozen_string_literal: true

# Convenience entry point for the Library subsystem. Pulls in the schema
# validator, format-version constant, and the Qdrant-backed Store facade.
#
# Library is the unified Knowledge Base across all Monadic Chat apps. It is
# scoped at the *project* level (not per-app) and gates external access via
# the visibility payload.

require_relative 'library/version'
require_relative 'library/schema'
require_relative 'library/store'
