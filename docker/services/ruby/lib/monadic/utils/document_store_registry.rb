# frozen_string_literal: true

require 'json'
require 'fileutils'

module Monadic
  module Utils
    module DocumentStoreRegistry
      module_function

      def registry_path
        File.join(Environment.data_path, 'document_store_registry.json')
      end

      def load
        path = registry_path
        return {} unless File.exist?(path)
        JSON.parse(File.read(path)) rescue {}
      end

      def with_lock
        path = registry_path
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        lock_path = path + ".lock"
        File.open(lock_path, File::CREAT) do |lock|
          lock.flock(File::LOCK_EX)
          data = load
          result = yield(data)
          tmp = path + ".tmp.#{Process.pid}"
          File.write(tmp, JSON.pretty_generate(result))
          File.rename(tmp, path)
          result
        ensure
          begin
            lock.flock(File::LOCK_UN) if lock
          rescue StandardError
            # ignore
          end
        end
      rescue StandardError => e
        puts "[Registry] with_lock failed: #{e.message}"
        raise
      end

      def sanitize_app_key(app_key)
        (app_key.to_s.strip.downcase.gsub(/[^a-z0-9_\-]/, '_'))
      end

      def get_app(app_key)
        key = sanitize_app_key(app_key)
        load[key] || {}
      end

      def set_cloud_vs(app_key, vs_id)
        key = sanitize_app_key(app_key)
        with_lock do |reg|
          reg[key] ||= {}
          reg[key]['cloud'] ||= {}
          if vs_id.nil? || vs_id.to_s.empty?
            reg[key]['cloud'].delete('vector_store_id')
          else
            reg[key]['cloud']['vector_store_id'] = vs_id
          end
          reg
        end
      end

      def add_cloud_file(app_key, file_id:, filename:, hash: nil)
        key = sanitize_app_key(app_key)
        with_lock do |reg|
          reg[key] ||= {}
          reg[key]['cloud'] ||= {}
          reg[key]['cloud']['files'] ||= []
          # avoid duplication
          unless reg[key]['cloud']['files'].any? { |f| f['file_id'] == file_id }
            reg[key]['cloud']['files'] << {
              'file_id' => file_id,
              'filename' => filename,
              'hash' => hash,
              'created_at' => Time.now.utc.iso8601
            }
          end
          reg
        end
      end

      def remove_cloud_file(app_key, file_id)
        key = sanitize_app_key(app_key)
        with_lock do |reg|
          files = reg.dig(key, 'cloud', 'files')
          if files.is_a?(Array)
            reg[key]['cloud']['files'] = files.reject { |f| f['file_id'] == file_id }
          end
          reg
        end
      end

      def clear_cloud(app_key)
        key = sanitize_app_key(app_key)
        with_lock do |reg|
          if reg[key] && reg[key]['cloud']
            reg[key]['cloud']['files'] = []
          end
          reg
        end
      end
    end
  end
end
