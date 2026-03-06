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
  
  # Check if pgvector container is running
  def check_pgvector_container
    container_name = "monadic-chat-pgvector-container"
    `docker ps --format '{{.Names}}' | grep -q "^#{container_name}$"`
    $?.success?
  end
  
  # Check if PostgreSQL is actually accepting connections
  def pgvector_connectable?
    conn = PG.connect(postgres_connection_params)
    conn.close
    true
  rescue PG::ConnectionBad
    false
  end

  # Create a test database
  def create_test_database(db_name)
    conn = PG.connect(postgres_connection_params)

    suppress_pg_notices(conn)
    conn.exec("CREATE DATABASE #{db_name}")
    conn.close
  rescue PG::DuplicateDatabase
    # Database already exists, that's fine
  rescue PG::ConnectionBad => e
    skip "PostgreSQL is not accepting connections: #{e.message}"
  end

  # Drop a test database
  def drop_test_database(db_name)
    conn = PG.connect(postgres_connection_params)

    suppress_pg_notices(conn)
    conn.exec("DROP DATABASE IF EXISTS #{db_name}")
    conn.close
  rescue PG::ConnectionBad
    # Cannot connect to drop database; silently ignore during cleanup
  end
end