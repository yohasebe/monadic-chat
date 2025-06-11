# frozen_string_literal: true

# Only load help embeddings if the database exists
begin
  require_relative "help_embeddings"
  
  # Initialize the help embeddings database as a global constant
  # This allows all apps to access the help documentation
  HELP_EMBEDDINGS_DB = HelpEmbeddings.new
rescue => e
  puts "[WARNING] Failed to initialize help embeddings database: #{e.message}"
  HELP_EMBEDDINGS_DB = nil
end

# Provide a method to check if help database is available
def help_database_available?
  !HELP_EMBEDDINGS_DB.nil?
end