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
require 'prism'
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
  | IO\.(?:write|binwrite|sysopen)\(
  | FileUtils\.(?:cp|cp_r|mv|mkdir_p|mkdir|makedirs|touch|rm|rm_f|rm_r|rm_rf|rmtree|ln|ln_s|ln_sf|install|copy_file|copy_entry|remove|remove_entry|remove_entry_secure|remove_dir|remove_file|chmod|chmod_R|chown)(?![A-Za-z_])
  | Dir\.(?:mkdir|rmdir|unlink|delete)(?![A-Za-z_])
  | Tempfile\.(?:new|create)(?![A-Za-z_])
  | Pathname\.new\([^)]*\)\.(?:write|binwrite|mkpath|rmtree|delete|unlink)
  )
/x.freeze

# File.open calls that may write, found by parsing the file as Ruby does, so
# a path with its own parentheses (File.join(...)) or a call over several
# lines is read whole. A call may write when its mode or flags: is a string
# that writes, a write flag, a number other than 0, or something the text
# cannot say (a variable, an expression, arguments spread in), which is
# flagged for review like a write. Returns their lines.
class WritingOpens < Prism::Visitor
  WRITE_MODE = /\A(?:w|a|r\+)|\+/
  WRITE_FLAGS = %i[WRONLY RDWR CREAT TRUNC APPEND].freeze

  def self.lines(source)
    finder = new
    Prism.parse(source).value.accept(finder)
    finder.lines
  end

  attr_reader :lines

  def initialize
    super
    @lines = []
  end

  def visit_call_node(node)
    @lines << node.location.start_line if node.name == :open && file?(node.receiver) && may_write?(node)
    super
  end

  private

  def file?(receiver)
    case receiver
    when Prism::ConstantReadNode then receiver.name == :File
    when Prism::ConstantPathNode then receiver.parent.nil? && receiver.name == :File
    else false
    end
  end

  def may_write?(node)
    args = node.arguments&.arguments || []
    options = args.find { |arg| arg.is_a?(Prism::KeywordHashNode) }
    # Arguments spread in (*args, **options) can say anything
    return true if args.any? { |arg| arg.is_a?(Prism::SplatNode) }
    return true if options&.elements&.any? { |el| el.is_a?(Prism::AssocSplatNode) }

    mode = args[1] unless args[1].is_a?(Prism::KeywordHashNode)
    mode ||= keyword(options, 'mode')
    flags = keyword(options, 'flags')
    [mode, flags].compact.any? { |value| writes?(value) }
  end

  def keyword(options, name)
    options&.elements&.find { |el| el.is_a?(Prism::AssocNode) && el.key.is_a?(Prism::SymbolNode) && el.key.unescaped == name }&.value
  end

  def writes?(mode)
    case mode
    when Prism::StringNode then mode.unescaped.match?(WRITE_MODE)
    when Prism::IntegerNode then !mode.value.zero? # 0 is RDONLY; other numbers may set write bits
    else
      # File::WRONLY | File::CREAT and the like: writes when a flag does. A
      # mode the text cannot say (a variable, another constant) may write.
      flags = file_flags(mode)
      flags.nil? || flags.intersect?(WRITE_FLAGS)
    end
  end

  def mode_zero?(node)
    node.value.zero?
  end

  # The names of the File:: flags an expression ORs together, or nil when it
  # is anything else (a number other than 0 included).
  def file_flags(node)
    case node
    when Prism::ConstantPathNode
      node.parent.is_a?(Prism::ConstantReadNode) && node.parent.name == :File ? [node.name] : nil
    when Prism::IntegerNode then mode_zero?(node) ? [] : nil # a number may set write bits
    when Prism::ParenthesesNode then file_flags(node.body&.body&.first)
    when Prism::CallNode
      return nil unless node.name == :| && node.arguments&.arguments&.size == 1

      left = file_flags(node.receiver)
      right = file_flags(node.arguments.arguments.first)
      left && right && left + right
    end
  end
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
  source = File.read(path, encoding: 'UTF-8', invalid: :replace, undef: :replace, replace: '?')
  opens = WritingOpens.lines(source)
  source.lines.each_with_index do |line, idx|
    next if line.lstrip.start_with?('#')
    next unless line =~ RAW_WRITE || opens.include?(idx + 1)

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
