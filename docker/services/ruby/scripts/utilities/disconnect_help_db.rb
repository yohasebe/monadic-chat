#!/usr/bin/env ruby
# frozen_string_literal: true

require "pg"

# Define IN_CONTAINER constant
IN_CONTAINER = File.file?("/.dockerenv")

# Connect to PostgreSQL
conn = if IN_CONTAINER
         PG.connect(dbname: "postgres", host: "pgvector_service", port: 5432, user: "postgres")
       else
         PG.connect(dbname: "postgres")
       end

# Terminate all connections to monadic_help database
puts "Terminating all connections to monadic_help database..."

begin
  result = conn.exec(<<~SQL)
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname = 'monadic_help'
      AND pid <> pg_backend_pid()
  SQL
  
  terminated_count = result.ntuples
  puts "Terminated #{terminated_count} connections."
  
rescue PG::Error => e
  puts "Error terminating connections: #{e.message}"
ensure
  conn.close if conn
end

puts "Done."