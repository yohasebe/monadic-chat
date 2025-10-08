# frozen_string_literal: true

require 'openssl'

module Monadic
  module Utils
    module SSLConfiguration
      class << self
        def configure!(config = {})
          config ||= {}
          adjust_default_params(config)
          apply_http_defaults(config)
        rescue StandardError => e
          log("SSL configuration failed: #{e.class}: #{e.message}", config)
        end

        private

        def adjust_default_params(config)
          defaults = OpenSSL::SSL::SSLContext::DEFAULT_PARAMS

          verify_flags = defaults[:verify_flags]
          verify_flags ||= begin
            OpenSSL::SSL::SSLContext.new.verify_flags
          rescue StandardError
            nil
          end

          if verify_flags
            verify_flags &= ~OpenSSL::X509::V_FLAG_CRL_CHECK if defined?(OpenSSL::X509::V_FLAG_CRL_CHECK)
            verify_flags &= ~OpenSSL::X509::V_FLAG_CRL_CHECK_ALL if defined?(OpenSSL::X509::V_FLAG_CRL_CHECK_ALL)
            defaults[:verify_flags] = verify_flags
          end

          defaults[:verify_mode] ||= OpenSSL::SSL::VERIFY_PEER

          ca_file = resolve_ca_file(config, defaults)
          defaults[:ca_file] = ca_file if ca_file

          ca_path = resolve_ca_path(config, defaults)
          defaults[:ca_path] = ca_path if ca_path

          log("SSL defaults configured (ca_file=#{defaults[:ca_file] || 'system'}, ca_path=#{defaults[:ca_path] || 'system'})", config)
        end

        def apply_http_defaults(config)
          require 'http'
          ctx = OpenSSL::SSL::SSLContext.new
          params = OpenSSL::SSL::SSLContext::DEFAULT_PARAMS

          ctx.verify_mode = params[:verify_mode] if params[:verify_mode]
          ctx.verify_flags = params[:verify_flags] if params[:verify_flags]
          ctx.ca_file = params[:ca_file] if params[:ca_file]
          ctx.ca_path = params[:ca_path] if params[:ca_path]

          HTTP.default_options = HTTP.default_options.merge(ssl_context: ctx)
          log('HTTP default SSL context updated', config)
        rescue LoadError
          # HTTP gem not available yet; nothing to configure
        rescue StandardError => e
          log("Failed to update HTTP default SSL context: #{e.class}: #{e.message}", config)
        end

        def resolve_ca_file(config, defaults)
          candidates = [
            config['SSL_CERT_FILE'],
            ENV['SSL_CERT_FILE'],
            defaults[:ca_file],
            OpenSSL::X509::DEFAULT_CERT_FILE
          ]

          candidates.compact.map(&:to_s).map(&:strip).find do |path|
            next if path.empty?
            File.file?(path) && path
          end
        end

        def resolve_ca_path(config, defaults)
          candidates = [
            config['SSL_CERT_DIR'],
            ENV['SSL_CERT_DIR'],
            defaults[:ca_path],
            OpenSSL::X509::DEFAULT_CERT_DIR
          ]

          candidates.compact.map(&:to_s).map(&:strip).find do |path|
            next if path.empty?
            Dir.exist?(path) && path
          end
        end

        def log(message, config)
          enabled = if config.is_a?(Hash)
            config['EXTRA_LOGGING'] == true
          else
            ENV['EXTRA_LOGGING'] == 'true'
          end

          puts "[SSLConfiguration] #{message}" if enabled
        end

        public

        # Create an SSL context for Net::HTTP with configured settings
        def create_ssl_context
          ctx = OpenSSL::SSL::SSLContext.new
          params = OpenSSL::SSL::SSLContext::DEFAULT_PARAMS

          ctx.verify_mode = params[:verify_mode] if params[:verify_mode]
          ctx.verify_flags = params[:verify_flags] if params[:verify_flags]
          ctx.ca_file = params[:ca_file] if params[:ca_file]
          ctx.ca_path = params[:ca_path] if params[:ca_path]

          ctx
        end

        # Apply SSL context to a Net::HTTP instance
        def apply_to_net_http(http)
          http.use_ssl = true
          http.ssl_version = :TLSv1_2

          ctx = create_ssl_context
          http.cert_store = ctx.cert_store if ctx.cert_store
          http.verify_mode = ctx.verify_mode
          http.ca_file = ctx.ca_file if ctx.ca_file
          http.ca_path = ctx.ca_path if ctx.ca_path

          # Disable CRL checks
          http.verify_flags = ctx.verify_flags if ctx.verify_flags
        end
      end
    end
  end
end
