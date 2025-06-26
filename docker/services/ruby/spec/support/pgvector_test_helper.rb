# frozen_string_literal: true

module PgvectorTestHelper
  # Suppress PostgreSQL NOTICE messages during tests
  def suppress_pg_notices(conn)
    conn.exec("SET client_min_messages = WARNING")
  end
  
  # Create extension with notice suppression
  def create_vector_extension(conn)
    suppress_pg_notices(conn)
    conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
  end
  
  # Drop table with notice suppression
  def drop_table_if_exists(conn, table_name)
    suppress_pg_notices(conn)
    conn.exec("DROP TABLE IF EXISTS #{table_name}")
  end
end