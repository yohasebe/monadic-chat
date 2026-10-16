# frozen_string_literal: true

require 'securerandom'
require 'set'
require 'fileutils'
require_relative '../../lib/monadic/workspace/shared_folder'

# Files a spec makes in the user's shared folder (~/monadic/data), which
# specs that run tools in the containers cannot avoid.
#
# - Names: every such file starts with TEST_PREFIX and the run's id
#   (`monadic-test-<run>-<name>`), so it cannot collide with a user's file
#   and the Shared Folder panel can tell it apart.
# - Cleanup: only what was not there before the example AND is the test's
#   own is removed (`snapshot` before, `remove_new` after). Being new is not
#   enough: the user (or an app) can make files while a spec runs. A file that
#   was already there, whatever its name, is never touched.
module SharedFolderTestFiles
  # The Shared Folder panel reads the same prefix.
  TEST_PREFIX = Monadic::Workspace::SharedFolder::TEST_PREFIX
  RUN_ID = ENV['MONADIC_TEST_RUN_ID'] ||= "#{Time.now.strftime('%Y%m%d%H%M%S')}#{SecureRandom.hex(2)}"

  module_function

  # "monadic-test-<run>-<base>"
  def name(base)
    "#{TEST_PREFIX}#{RUN_ID}-#{base}"
  end

  # The names directly in dir now.
  def snapshot(dir)
    Dir.exist?(dir) ? Dir.children(dir).to_set : Set.new
  end

  # Names this run gave (see name).
  def mine
    /\A#{Regexp.escape(TEST_PREFIX)}#{Regexp.escape(RUN_ID)}-/
  end

  # Removes the entries of dir that were not in before and whose name matches
  # match (by default, the names this run gave). A tool that names its own
  # files is given a folder of this run's (such as FETCH_DIR) to write in,
  # never cleaned up by the tool's own names, which a user's files share.
  def remove_new(dir, before, match: mine)
    return [] unless Dir.exist?(dir)

    added = Dir.children(dir).reject { |n| before.include?(n) }.select { |n| match.match?(n) }
    added.each { |n| FileUtils.rm_rf(File.join(dir, n)) }
    added
  end

  # Where webpage_fetcher.py writes the pages the specs fetch.
  FETCH_DIR = name('fetched')
end
