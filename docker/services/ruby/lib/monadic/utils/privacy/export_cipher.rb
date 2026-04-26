# frozen_string_literal: true

require 'argon2'
require 'base64'
require 'digest'
require 'json'
require 'openssl'
require 'securerandom'

module Monadic
  module Utils
    module Privacy
      # Encrypted export envelope for privacy-protected conversations.
      # Format: AES-256-GCM ciphertext + Argon2id KDF + SHA-256 header integrity.
      # See docs_dev/privacy_filter_design.md (Block D §2) for the full spec.
      module ExportCipher
        SCHEMA_VERSION = 1
        SALT_BYTES = 16
        IV_BYTES = 12
        TAG_BYTES = 16
        KEY_BYTES = 32

        # OWASP minimum recommended Argon2id parameters (2024 guideline).
        # m_cost is in log2(KB): 16 → 64 MB working memory.
        ARGON2_M_COST = 16
        ARGON2_T_COST = 3
        ARGON2_P_COST = 4

        class IntegrityError < StandardError; end
        class DecryptionError < StandardError; end

        module_function

        # Build a complete export envelope from header metadata + plaintext payload.
        # Returns a Hash ready to JSON.dump into the .mcp-privacy.json file.
        #
        # @param header [Hash] non-secret metadata (app_name, created_at, …)
        # @param plaintext [String, Hash] payload to protect
        # @param passphrase [String] user-supplied passphrase (zxcvbn ≥ 3 expected)
        def encrypt(header:, plaintext:, passphrase:)
          raise ArgumentError, "passphrase required" if passphrase.nil? || passphrase.empty?

          payload_json = plaintext.is_a?(String) ? plaintext : JSON.generate(plaintext)
          salt = SecureRandom.bytes(SALT_BYTES)
          iv = SecureRandom.bytes(IV_BYTES)
          key = derive_key(passphrase, salt)

          cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
          cipher.key = key
          cipher.iv = iv
          ciphertext = cipher.update(payload_json) + cipher.final
          auth_tag = cipher.auth_tag(TAG_BYTES)

          {
            "schema_version" => SCHEMA_VERSION,
            "header" => header,
            "envelope" => {
              "kdf" => {
                "algorithm" => "argon2id",
                "salt" => Base64.strict_encode64(salt),
                "memory_cost" => ARGON2_M_COST,
                "time_cost" => ARGON2_T_COST,
                "parallelism" => ARGON2_P_COST
              },
              "cipher" => {
                "algorithm" => "AES-256-GCM",
                "iv" => Base64.strict_encode64(iv),
                "ciphertext" => Base64.strict_encode64(ciphertext),
                "auth_tag" => Base64.strict_encode64(auth_tag)
              }
            },
            "integrity" => {
              "header_sha256" => header_digest(header)
            }
          }
        end

        # Verify integrity, derive the key, and decrypt back to the plaintext.
        # Raises IntegrityError on header tampering or DecryptionError on a
        # wrong passphrase / corrupted ciphertext.
        #
        # @param envelope [Hash] full envelope (output of #encrypt) or string keys
        # @param passphrase [String]
        # @return [String] decrypted plaintext (caller can JSON.parse if it expects JSON)
        def decrypt(envelope:, passphrase:)
          raise ArgumentError, "passphrase required" if passphrase.nil? || passphrase.empty?
          raise ArgumentError, "envelope required" unless envelope.is_a?(Hash)

          header = envelope["header"] || envelope[:header]
          integrity = envelope["integrity"] || envelope[:integrity] || {}
          stored_digest = integrity["header_sha256"] || integrity[:header_sha256]
          unless stored_digest && stored_digest == header_digest(header)
            raise IntegrityError, "header_sha256 mismatch (envelope tampered or malformed)"
          end

          env = envelope["envelope"] || envelope[:envelope]
          kdf = env["kdf"] || env[:kdf]
          ciph = env["cipher"] || env[:cipher]

          salt = Base64.strict_decode64(kdf["salt"] || kdf[:salt])
          iv = Base64.strict_decode64(ciph["iv"] || ciph[:iv])
          ciphertext = Base64.strict_decode64(ciph["ciphertext"] || ciph[:ciphertext])
          auth_tag = Base64.strict_decode64(ciph["auth_tag"] || ciph[:auth_tag])

          key = derive_key(passphrase, salt)
          cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
          cipher.key = key
          cipher.iv = iv
          cipher.auth_tag = auth_tag
          cipher.auth_data = ""
          begin
            plaintext = cipher.update(ciphertext) + cipher.final
          rescue OpenSSL::Cipher::CipherError => e
            raise DecryptionError, "wrong passphrase or corrupted ciphertext: #{e.message}"
          end
          plaintext
        end

        # SHA-256 of a canonical (sorted-keys) JSON serialization of the header.
        # Stable across symbol/string keys so re-loaded envelopes still verify.
        def header_digest(header)
          stringified = stringify_keys(header)
          canonical = JSON.generate(stringified.sort.to_h)
          Digest::SHA256.hexdigest(canonical)
        end

        # Internal: derive a 32-byte raw key with Argon2id.
        # Uses the lower-level Engine API (returns hex-encoded raw bytes,
        # decoded to binary for AES key use).
        def derive_key(passphrase, salt)
          hex = Argon2::Engine.hash_argon2id(
            passphrase,
            salt,
            ARGON2_T_COST,
            ARGON2_M_COST,
            KEY_BYTES
          )
          [hex].pack("H*")
        end
        private_class_method :derive_key

        def stringify_keys(value)
          case value
          when Hash
            value.each_with_object({}) { |(k, v), acc| acc[k.to_s] = stringify_keys(v) }
          when Array
            value.map { |v| stringify_keys(v) }
          else
            value
          end
        end
        private_class_method :stringify_keys
      end
    end
  end
end
