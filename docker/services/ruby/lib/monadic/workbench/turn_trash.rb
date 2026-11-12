# frozen_string_literal: true

require 'time'
require_relative '../utils/environment'
require_relative '../utils/shared_fs'

module Monadic
  module Workbench
    # What a deleted turn made (Workbench::Made), moved into the trash of
    # its chat's folder (<chat folder>/trash/<label>/), each under the path
    # it had in the folder, so it can be taken back until the chat itself
    # is deleted. Only what is really inside that chat's folder moves:
    # never a link, never anything elsewhere, never the trash itself.
    module TurnTrash
      DIRNAME = 'trash'

      module_function

      # Moves paths (relative to the shared folder) that are inside the
      # chat folder folder_dir into its trash under label. Returns the paths
      # moved; one that is missing, a link, or not inside the folder is
      # left, and one that cannot be moved is logged and left.
      def move(folder_dir, paths, label)
        root = File.realpath(Monadic::Utils::Environment.data_path)
        base = folder_dir.to_s.split('/')
        return [] if base.empty? || base.any? { |part| part.empty? || part == '.' || part == '..' }

        Array(paths).each_with_object([]) do |path, moved|
          rest = inside(folder_dir, path) or next
          moved << path if move_one(root, base, rest, label)
        rescue Monadic::Utils::SharedFs::Unsafe, SystemCallError, IOError => e
          warn "[TurnTrash] #{path} was not moved to the trash: #{e.class.name.split('::').last}"
        end
      end

      # A name for one deleted turn's part of the trash.
      def label(mid, now: Time.now)
        tag = mid.to_s.gsub(/[^A-Za-z0-9_-]/, '')[0, 40]
        [now.utc.strftime('%Y%m%d-%H%M%S'), tag].reject(&:empty?).join('-')
      end

      # The parts of path below folder_dir, or nil when it is not inside it
      # (or is its trash).
      def inside(folder_dir, path)
        return nil unless path.is_a?(String) && path.start_with?("#{folder_dir}/")

        rest = path.delete_prefix("#{folder_dir}/").split('/', -1)
        return nil if rest.empty? || rest.first == DIRNAME
        return nil if rest.any? { |part| part.empty? || part == '.' || part == '..' }

        rest
      end

      def move_one(root, base, rest, label)
        name = rest.last
        Monadic::Utils::SharedFs.in_dir(root, base + rest[0..-2]) do |from|
          found = Monadic::Utils::SharedFs.entry(from, name)
          return false unless found.is_a?(File::Stat)

          Monadic::Utils::SharedFs.in_dir(root, base + [DIRNAME, label] + rest[0..-2], create: true) do |to|
            return false if Monadic::Utils::SharedFs.entry(to, name)

            Monadic::Utils::SharedFs.rename(from, name, to, name)
          end
        end
        true
      end
      private_class_method :move_one
    end
  end
end
