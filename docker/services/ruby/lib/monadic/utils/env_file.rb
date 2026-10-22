# frozen_string_literal: true

require_relative 'environment'

module Monadic
  module Utils
    # Reads ~/monadic/config/env for the server and the tasks that start it.
    #
    # The file is parsed here with Dotenv's grammar (KEY=value or KEY: value,
    # an optional `export`, single-, double- or un-quoted values, quoted
    # values over several lines, `#` comments, a leading BOM, CRLF or CR line
    # ends) but nothing in a value is expanded or run: `$VAR`, `${VAR}` and
    # `$(...)` stay text. A quoted value that is never closed is not used,
    # and nothing after it is read.
    # The same parse gives both ENV and CONFIG their values, and the scripts
    # their credentials (SecretReferences).
    #
    # Only the settings the code reads from ENV are put in ENV (ENV_KEYS and
    # ENV_PATTERNS); the rest stay in the parsed file, for CONFIG. Settings
    # that decide where requests go or what program runs are never taken
    # from the file, for ENV or CONFIG (REFUSED): a proxy or a service
    # address written there would send requests, API keys among them,
    # elsewhere. A port (PORT_KEYS) must be a number from 1 to 65535: it is
    # put into addresses. A setting that names a file the server reads
    # (PATH_KEYS) must be an absolute path to an existing file or folder
    # outside the shared folder, which code in another container can write;
    # it is passed on as that real path. The shell's own environment is not
    # changed or filtered: a value set there is the user's.
    #
    # Self-contained (no gems), so the rake task can use it before the
    # server's code is loaded.
    module EnvFile
      REFUSED = %w[
        http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
        no_proxy NO_PROXY ftp_proxy FTP_PROXY
        QDRANT_URL EMBEDDINGS_URL EXTRACTOR_URL MCP_SERVER_HOST
        MONADIC_OP_CLI MONADIC_AUTH_TOKEN MONADIC_LOAD_USER_CODE
        PATH HOME RUBYOPT RUBYLIB GEM_HOME GEM_PATH BUNDLE_GEMFILE
        LD_PRELOAD LD_LIBRARY_PATH DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH NODE_OPTIONS
      ].freeze
      PATH_KEYS = { 'SSL_CERT_FILE' => :file, 'SSL_CERT_DIR' => :directory,
                    'TTS_DICT_PATH' => :file, 'HELP_DATA_DUMP' => :file }.freeze
      PORT_KEYS = %w[QDRANT_DEV_PORT EMBEDDINGS_DEV_PORT EXTRACTOR_DEV_PORT PRIVACY_DEV_PORT
                     JUPYTER_PORT MCP_SERVER_PORT].freeze

      # Read from ENV by the code (checked against the code by a spec).
      ENV_KEYS = %w[
        EXTRA_LOGGING DEBUG DEBUG_MODE DEBUG_TTS DEBUG_LEVEL DEBUG_CLAUDE DEBUG_CATEGORIES
        APP_DEBUG MONADIC_DEBUG MONADIC_DEBUG_LEVEL PROFILE_STARTUP CHECK_DEBUG_MIGRATION
        UI_LANGUAGE WEBSOCKET_PROGRESS_ENABLED DISTRIBUTED_MODE
        EXTRACTOR_SERVICE PRIVACY_LANGS
        PDF_RAG_TOKENS PDF_RAG_OVERLAP_LINES LIBRARY_IMPORT_MAX_BYTES GEMINI_MAX_INLINE_PDF_MB
        HELP_CHUNKS_PER_RESULT HELP_CHUNK_SIZE HELP_OVERLAP_SIZE
        LOG_ROTATE_MAX_FILES LOG_ROTATE_MAX_BYTES SESSION_MAX_BYTES SESSION_MAX_COUNT
        OPENAI_CODE_MODEL OPENAI_CODE_TIMEOUT GROK_CODE_MODEL GROK_CODE_TIMEOUT
      ].freeze + PORT_KEYS + PATH_KEYS.keys
      ENV_PATTERNS = [/\A[A-Z][A-Z0-9_]*_API_KEY\z/, /\A[A-Z][A-Z0-9_]*_DEFAULT_MODEL\z/].freeze

      # Where the shared folder is, in the container and on the host.
      SHARED_FOLDERS = [Environment::CONTAINER_DATA_PATH, '~/monadic/data'].freeze

      # Dotenv's line grammar (dotenv/parser.rb), without its substitutions.
      LINE = /
        (?:^|\A)
        \s*
        (?<export>export\s+)?
        (?<key>[\w.]+)
        (?:
          (?:\s*=\s*?|:\s+?)
          (?<value>
            \s*'(?:\\'|[^'])*'
            |
            \s*"(?:\\"|[^"])*"
            |
            [^\#\n]+
          )?
        )?
        \s*
        (?:\#.*)?
        (?:$|\z)
      /x
      QUOTED = /\A(['"])(.*)\1\z/m

      module_function

      # The file's settings as written, nothing expanded or run, nothing
      # filtered ({} without a file). A key written twice keeps its last value.
      def parse(path)
        parse_with_problems(path).first
      end

      # [settings, keys whose value could not be read (a quote never closed)].
      def parse_with_problems(path)
        # Read straight away (specs stub File.read for a path that is not on
        # disk); a missing file reads as nothing.
        text = begin
          File.read(path)
        rescue Errno::ENOENT, Errno::EISDIR
          return [{}, []]
        end
        text = text.dup.force_encoding('UTF-8').scrub('').delete_prefix("\uFEFF").gsub(/\r\n?/, "\n")
        settings = {}
        broken = []
        text.scan(LINE) do
          match = Regexp.last_match
          # A line with no separator (a bare word) is not a setting.
          next unless match.to_s.match?(/\A\s*(?:export\s+)?[\w.]+(?:\s*=|:\s)/)

          value = value_of(match[:value].to_s)
          if value.nil?
            # A quote never closed: what follows may be its text, so nothing
            # after it is read as a setting.
            broken << match[:key]
            settings.delete(match[:key])
            break
          end
          settings[match[:key]] = value
        end
        [settings, broken.uniq]
      end

      # The settings of the file that may be used, with the value each is
      # used with (a file setting as its real path).
      def accepted(path)
        parse(path).each_with_object({}) do |(key, value), settings|
          used = usable(key, value)
          settings[key] = used unless used.nil?
        end
      end

      # The names of the file's settings that are not used (never values):
      # refused, or a quoted value never closed.
      def refused_keys(path)
        settings, broken = parse_with_problems(path)
        (settings.filter_map { |key, value| key if usable(key, value).nil? } + broken).uniq
      end

      # Puts the accepted settings that the code reads from ENV in ENV,
      # leaving a value the shell set alone. Says which settings of the file
      # are not used (names only). Returns the accepted settings.
      def load!(path, env: ENV, out: $stdout)
        refused = refused_keys(path)
        out.puts "[Config] Not used from the config env file: #{refused.join(', ')}" unless refused.empty?
        accepted(path).tap do |settings|
          settings.each do |key, value|
            env[key] = value if env_key?(key) && !env.key?(key)
          end
        end
      end

      def env_key?(key)
        ENV_KEYS.include?(key) || ENV_PATTERNS.any? { |pattern| pattern.match?(key) }
      end

      # The value a setting of the file is used with, or nil when it is not
      # used, for ENV or CONFIG.
      def usable(key, value)
        return nil if REFUSED.include?(key)
        return port(value) if PORT_KEYS.include?(key)
        return outside_path(value, PATH_KEYS[key]) if PATH_KEYS.key?(key)

        value
      end

      def refused?(key, value)
        usable(key, value).nil?
      end

      def port(value)
        text = value.to_s.strip
        text.match?(/\A[0-9]{1,5}\z/) && text.to_i.between?(1, 65_535) ? text : nil
      end

      # The real path of an existing file or folder (kind) outside the shared
      # folder, or nil: a relative path, a reference, a link that leads
      # nowhere, or anything that cannot be resolved is not used.
      def outside_path(value, kind)
        text = value.to_s.strip
        return nil unless text.start_with?('/', '~/')

        real = File.realpath(File.expand_path(text))
        return nil unless kind == :directory ? File.directory?(real) : File.file?(real)
        return nil if SHARED_FOLDERS.any? { |folder| inside?(real, folder) }

        real
      rescue SystemCallError, ArgumentError
        nil
      end

      def inside?(real, folder)
        root = File.realpath(File.expand_path(folder))
        real == root || real.start_with?("#{root}/")
      rescue SystemCallError
        # A shared folder that is not there holds nothing.
        false
      end

      # As Dotenv's parse_value (its default line-break mode), without
      # substitutions: quotes removed, `\n` and `\r` in double quotes kept as
      # written, other backslashes taken off outside single quotes. nil for a
      # value that opens a quote and never closes it.
      def value_of(raw)
        text = raw.strip
        match = QUOTED.match(text)
        return nil if match.nil? && text.start_with?("'", '"')

        quote = match && match[1]
        text = match[2] if match
        text = text.gsub('\n', "\\\\\\n").gsub('\r', "\\\\\\r") if quote == '"'
        text = text.gsub(/\\([^$])/, '\1') unless quote == "'"
        text
      end

      private_class_method :port, :outside_path, :inside?, :value_of
    end
  end
end
