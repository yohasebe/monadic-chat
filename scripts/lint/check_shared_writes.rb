#!/usr/bin/env ruby
# frozen_string_literal: true

# Anti-pattern lint: raw file writes outside SharedPathGuard.
#
# The shared folder can be changed by code running in another container,
# which can put links there. A raw write (File.write, File.open with a write
# mode, FileUtils.cp/mv/mkdir_p/rm_rf, File.chmod, Dir.mkdir, Tempfile in a
# folder, ...) follows a link at its name or in a folder on the way, and so
# can be sent to a file outside the shared folder that the server can reach.
# Everything the server and its scripts write in the shared folder goes
# through Monadic::Utils::SharedPathGuard (lib/monadic/utils/shared_path_guard.rb),
# which works on folders held open and never follows a link.
#
# A raw write is allowed only by an entry in shared_writes.allow (path, the
# text of the line, where it writes, why). An entry nothing matches fails
# the lint too, so the list never keeps a reason for code that is gone.
# Matching text is not proof: a write can be hidden behind a variable or a
# helper this lint does not know. The guard and its specs are the defence;
# this keeps new raw writes from slipping in unnoticed.

require 'pathname'
require_relative 'scan_floor'

ROOT = Pathname.new(__dir__).join('..', '..').realpath
ALLOW_FILE = Pathname.new(__dir__).join('shared_writes.allow')

# Scan roots with the fewest files a scan of each may read (see scan_floor.rb).
# Floors sit about 20% below the current counts; lower one when files are
# genuinely removed.
SCAN_ROOTS = {
  'docker/services/ruby/lib' => 196,
  'docker/services/ruby/scripts' => 10,
  'docker/services/ruby/apps' => 44
}.freeze
SCANNED = Hash.new(0)

# Calls that create, change or remove files. `::File.new` (HTTP::FormData)
# is not File.new, hence the class of characters before each name.
RAW_WRITE = /
  (?:^|[^A-Za-z_:.])
  (?:
    File\.(?:write|binwrite|chmod|chown|lchmod|delete|unlink|rename|link|symlink|new|truncate|mkfifo)\(
  | File\.open\([^)]*(?:['"](?:w|a|r\+)b?\+?['"]|WRONLY|RDWR|CREAT|TRUNC|APPEND)
  | IO\.(?:write|binwrite|sysopen)\(
  | FileUtils\.(?:cp|cp_r|mv|mkdir_p|mkdir|makedirs|touch|rm|rm_f|rm_r|rm_rf|rmtree|ln|ln_s|ln_sf|install|copy_file|copy_entry|remove|remove_entry|remove_entry_secure|remove_dir|remove_file|chmod|chmod_R|chown)(?![A-Za-z_])
  | Dir\.(?:mkdir|rmdir|unlink|delete)(?![A-Za-z_])
  | Tempfile\.(?:new|create)(?![A-Za-z_])
  | Pathname\.new\([^)]*\)\.(?:write|binwrite|mkpath|rmtree|delete|unlink)
  )
/x.freeze

# File.open whose mode is a variable: the text cannot say whether it writes,
# so it is flagged for review like a write.
def variable_mode_open?(line)
  start = line.index(/(?:^|[^A-Za-z_:.])File\.open\(/)
  return false unless start

  text = line[line.index('File.open(', start) + 'File.open('.length..]
  depth = 0
  args = [+'']
  text.each_char do |ch|
    case ch
    when '(', '[', '{' then depth += 1
    when ')', ']', '}'
      break if depth.zero?

      depth -= 1
    when ','
      if depth.zero?
        args << +''
        next
      end
    end
    args.last << ch
  end
  args.size >= 2 && args[1].strip.match?(/\A[a-z_][a-z0-9_]*\z/)
end

def load_allow
  ALLOW_FILE.readlines(chomp: true).each_with_index.filter_map do |line, idx|
    next if line.strip.empty? || line.start_with?('#')

    path, text, where, why = line.split(' | ', 4).map(&:strip)
    abort "[lint:shared_writes] #{ALLOW_FILE.basename}:#{idx + 1}: needs path | text | where | why" unless why && !why.empty?

    { path: path, text: text, where: where, why: why, line: idx + 1, used: 0 }
  end
end

def each_target_file
  return enum_for(:each_target_file) unless block_given?

  SCAN_ROOTS.each_key do |rel_root|
    Dir.glob(ROOT.join(rel_root, '**', '*.rb')).sort.each do |path|
      next unless File.file?(path)

      SCANNED[rel_root] += 1
      yield Pathname.new(path)
    end
  end
end

allow = load_allow
violations = []
each_target_file do |path|
  rel = path.relative_path_from(ROOT).to_s
  File.readlines(path, encoding: 'UTF-8', invalid: :replace, undef: :replace, replace: '?').each_with_index do |line, idx|
    next if line.lstrip.start_with?('#')
    next unless line =~ RAW_WRITE || variable_mode_open?(line)

    entry = allow.find { |e| e[:path] == rel && line.include?(e[:text]) }
    if entry
      entry[:used] += 1
    else
      violations << "  #{rel}:#{idx + 1}: #{line.strip[0, 110]}"
    end
  end
end

exit 1 unless ScanFloor.met?('lint:shared_writes', SCANNED, SCAN_ROOTS)

unused = allow.select { |e| e[:used].zero? }
unless unused.empty?
  puts "[lint:shared_writes] #{unused.size} entr#{unused.size == 1 ? 'y' : 'ies'} in #{ALLOW_FILE.basename} match nothing:"
  unused.each { |e| puts "  #{ALLOW_FILE.basename}:#{e[:line]}: #{e[:path]} | #{e[:text]}" }
end

if violations.empty? && unused.empty?
  puts '[lint:shared_writes] OK — no raw writes outside SharedPathGuard and the allow list.'
  exit 0
end

unless violations.empty?
  puts "[lint:shared_writes] #{violations.size} raw write(s) not in #{ALLOW_FILE.basename}:"
  puts violations
  puts ''
  puts 'Write in the shared folder through Monadic::Utils::SharedPathGuard'
  puts '(write_file!, copy_file!, read_file!, delete_file!, mkdir_p!, make_dir!,'
  puts 'rename_file!, remove_tree!). A write that cannot be in the shared folder'
  puts '(state, logs, the system temporary folder) gets an entry in the allow list'
  puts 'saying where it writes and why.'
end
exit 1
