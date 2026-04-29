# frozen_string_literal: true

require_relative 'help_embeddings'
require_relative '../help/dump_loader'

# Initialise HELP_EMBEDDINGS_DB on application boot. Steps:
#   1. Construct the HelpEmbeddings facade (this only configures clients;
#      it does not contact qdrant or the embeddings service yet).
#   2. Bootstrap Qdrant collections idempotently.
#   3. If the collections are still empty (fresh install / new image), load
#      the prebuilt JSON dump shipped in the container at HELP_DATA_DUMP.
#
# Failures are logged but never raise — the rest of Monadic Chat must keep
# running even when the help database is unavailable.

DEFAULT_HELP_DUMP = '/monadic/help_data/help_db.json'

HELP_EMBEDDINGS_DB =
  begin
    db = HelpEmbeddings.new
    db.bootstrap_collections!

    unless db.data_loaded?
      dump_path = ENV.fetch('HELP_DATA_DUMP', DEFAULT_HELP_DUMP)
      if File.exist?(dump_path)
        Monadic::Help::DumpLoader.load(store: db.store, path: dump_path)
      else
        puts "[help_embeddings_loader] No dump at #{dump_path}; help search will be empty until 'rake help:build' runs."
      end
    end
    db
  rescue StandardError => e
    puts "[WARNING] Failed to initialize help embeddings database: #{e.class}: #{e.message}"
    nil
  end

# Public predicate other code uses to gate help-related features.
def help_database_available?
  !HELP_EMBEDDINGS_DB.nil?
end
