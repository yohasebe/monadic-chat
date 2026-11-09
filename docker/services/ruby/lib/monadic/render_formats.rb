# frozen_string_literal: true

require 'json'

module Monadic
  # The kinds of content the web UI draws, from one table
  # (render_formats.json): each kind's id, the code fence languages and the
  # file extensions it is known by (extensions of two parts, such as
  # vl.json, are looked at first). The server reads it to tell which files
  # the work screen draws; the page is given the same table (FORMATS_JSON)
  # and draws by it. Nothing here draws anything.
  module RenderFormats
    PATH = File.join(__dir__, 'render_formats.json')
    KEYS = %w[id fences extensions compound_extensions].freeze

    # The table, checked: every entry has the keys, in lower case, and no
    # id, fence or extension is named twice.
    def self.load(path = PATH)
      table = JSON.parse(File.read(path))
      raise ArgumentError, 'render formats must be a list' unless table.is_a?(Array)

      seen = Hash.new { |h, k| h[k] = {} }
      table.map do |entry|
        raise ArgumentError, "a render format needs #{KEYS.join(', ')}" unless entry.is_a?(Hash) && entry.keys.sort == KEYS.sort

        entry.each do |key, value|
          values = key == 'id' ? [value] : value
          raise ArgumentError, "#{key} of a render format must be text in lower case" unless
            values.is_a?(Array) && values.all? { |v| v.is_a?(String) && !v.empty? && v == v.downcase }

          group = key == 'compound_extensions' ? 'extensions' : key
          values.each do |v|
            raise ArgumentError, "#{v} is named twice in the render formats" if seen[group].key?(v)

            seen[group][v] = true
          end
        end
        entry.transform_values { |v| v.is_a?(Array) ? v.dup.freeze : v }.freeze
      end.freeze
    end

    TABLE = load
    # The table as the page is given it, safe inside a script element.
    FORMATS_JSON = JSON.generate(TABLE).gsub('</', '<\/').freeze

    # The id of the kind a file name is drawn as, or nil.
    def self.for_name(name)
      base = File.basename(name.to_s).downcase
      TABLE.each do |entry|
        entry['compound_extensions'].each { |ext| return entry['id'] if base.end_with?(".#{ext}") && base.size > ext.size + 1 }
      end
      ext = File.extname(base).delete_prefix('.')
      found = TABLE.find { |entry| entry['extensions'].include?(ext) }
      found && found['id']
    end

    # Every extension of one part, and of two parts.
    def self.extensions
      TABLE.flat_map { |entry| entry['extensions'] }
    end

    def self.compound_extensions
      TABLE.flat_map { |entry| entry['compound_extensions'] }
    end
  end
end
