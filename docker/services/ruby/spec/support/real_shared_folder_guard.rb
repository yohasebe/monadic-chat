# frozen_string_literal: true

require 'etc'
require_relative '../../lib/monadic/utils/shared_path_guard'

# Stops a spec that would change the shared folder of the person running
# the specs. Every write, folder, rename, copy and removal the server makes
# in the shared folder goes through SharedPathGuard; a spec gives
# Environment.data_path a folder of its own, so a path in the user's
# ~/monadic/data here means it did not.
module RealSharedFolderGuard
  FOLDER = File.join(Etc.getpwuid.dir, 'monadic', 'data')
  CHANGES = %i[write_file! mkdir_p! make_dir! rename_file! copy_file! delete_file! remove_tree!].freeze

  module_function

  def roots
    real = File.realpath(FOLDER)
    [FOLDER, real].uniq
  rescue SystemCallError
    [FOLDER]
  end

  def check!(path)
    return unless path.is_a?(String)

    full = File.expand_path(path)
    return unless roots.any? { |root| full == root || full.start_with?("#{root}/") }

    raise "A spec tried to change the user's shared folder: stub Environment.data_path with a folder of its own"
  end
end

Monadic::Utils::SharedPathGuard.singleton_class.prepend(Module.new do
  RealSharedFolderGuard::CHANGES.each do |name|
    define_method(name) do |path, *args, **kwargs, &block|
      RealSharedFolderGuard.check!(path)
      RealSharedFolderGuard.check!(args.first) if %i[rename_file! copy_file!].include?(name)
      super(path, *args, **kwargs, &block)
    end
  end
end)
