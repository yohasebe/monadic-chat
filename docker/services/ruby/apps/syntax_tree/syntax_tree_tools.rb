require 'json'
require 'tmpdir'
require_relative '../../lib/monadic/shell'
require_relative '../../lib/monadic/workbench/chat_output'

# Shared tools for Syntax Tree (provider-independent)
module SyntaxTreeTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations

  # What a drawing leaves in its run folder.
  OUTPUT_NAME = "syntax_tree.svg"
  TIKZ_NAME = "syntax_tree.tex"
  # The RSyntaxTree command. It is not in the app's bundle (its drawing
  # libraries are built in the Ruby container only), so it runs outside it.
  COMMAND = "rsyntaxtree"
  DRAW_TIMEOUT = 60
  # The look of every tree: serif, black, packed close (short rows, narrow
  # gaps between nodes), the words on one row with dashed lines up to their
  # nodes. A hyphen is a hyphen.
  STYLE = %w[
    --fontstyle serif --color off --tidy low --vheight 0.6 --vmargin 0.2 --hspacing 0.6
    --leaf-align words --leafstyle dashed --hyphen literal --transparent on
  ].freeze
  # Languages written right to left: the tree is mirrored, the first word
  # at the right edge.
  RIGHT_TO_LEFT = %w[arabic hebrew persian farsi urdu yiddish ar he fa ur yi].freeze

  # Draws the tree as an SVG in a run folder of the chat's folder
  # (artifacts/j_<id>/syntax_tree.svg) and shows it on the work screen.
  # Notation the drawing cannot read is not drawn: what is wrong in it, with
  # a hint, comes back to be fixed. tikz: also keep the tree as LaTeX
  # (forest) source.
  def render_syntax_tree(bracket_notation:, language:, tikz: false, session: nil, workbench: nil)
    job = nil
    notation = bracket_notation.to_s.strip
    return "❌ Bracket notation is required." if notation.empty?

    style = STYLE + (RIGHT_TO_LEFT.include?(language.to_s.strip.downcase) ? %w[--mirror on] : [])
    Dir.mktmpdir("syntax-tree") do |dir|
      input = File.join(dir, "notation.txt")
      File.write(input, notation)

      problems = notation_problems(input, style)
      return problems if problems

      app_name = (session && session.dig(:parameters, "app_name")) || self.class.name
      job = Monadic::Workbench::ChatOutput.run_folder(session: session, workbench: workbench, app_name: app_name)
      return "❌ The syntax tree could not be kept: there is no chat folder to keep it in." unless job

      formats = tikz ? { "svg" => OUTPUT_NAME, "tikz" => TIKZ_NAME } : { "svg" => OUTPUT_NAME }
      formats.each do |format, name|
        failure = draw(input, style, format, dir)
        if failure
          Monadic::Workbench::ChatOutput.drop_if_empty(job)
          return "❌ Error generating syntax tree: #{failure}"
        end
        drawn = File.binread(File.join(dir, "syntree.#{format == 'tikz' ? 'tex' : format}"))
        Monadic::Workbench::ChatOutput.keep(job, name, drawn)
      end

      path = File.join(job[:relative], OUTPUT_NAME)
      shown = Monadic::Workbench::ChatOutput.show(path, workbench) ? " It is shown on the work screen beside the chat." : ""
      source = tikz ? " Its LaTeX (forest) source is #{File.join(job[:relative], TIKZ_NAME)}; movement paths are not in it." : ""
      "The syntax tree was drawn as #{path}.#{shown}#{source}\n" \
        "The notation, indented, to show the user exactly as it is in a text code block:\n#{indented(notation)}"
    end
  rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError => e
    Monadic::Workbench::ChatOutput.drop_if_empty(job)
    "❌ The syntax tree could not be kept: #{e.message}"
  end

  private

  # The notation with each node that has nodes below it opened on a line of
  # its own, its nodes indented two spaces under it, and its closing
  # bracket on a line of its own; a node with no node below it stays on
  # one line. A character after a backslash is never a bracket. Notation
  # whose brackets do not pair comes back as it is.
  def indented(notation)
    stack = [[]]
    text = +""
    flush = lambda do
      stack.last << text.strip unless text.strip.empty?
      text = +""
    end
    chars = notation.each_char.to_a
    i = 0
    while i < chars.size
      char = chars[i]
      if char == "\\" && i + 1 < chars.size
        text << char << chars[i + 1]
        i += 2
        next
      end
      case char
      when "["
        flush.call
        stack.push([])
      when "]"
        flush.call
        return notation if stack.size < 2

        node = stack.pop
        stack.last << node
      else
        text << char
      end
      i += 1
    end
    flush.call
    return notation unless stack.size == 1

    stack.first.map { |item| indented_lines(item, 0) }.join("\n")
  end

  def indented_lines(item, depth)
    pad = "  " * depth
    return "#{pad}#{item}" if item.is_a?(String)
    return "#{pad}[#{item.join(' ')}]" if item.none?(Array)

    label = item.first.is_a?(String) ? item.first : nil
    rest = label ? item.drop(1) : item
    ["#{pad}[#{label}", *rest.map { |child| indented_lines(child, depth + 1) }, "#{pad}]"].join("\n")
  end

  # What RSyntaxTree finds wrong in the notation, as a message to fix it
  # by; nil when it reads.
  def notation_problems(input, style)
    out, err, = run_rsyntaxtree(["--validate", *style, input])
    report = JSON.parse(out)
    return nil if report["ok"]

    lines = Array(report["errors"]).map do |error|
      ["- #{error['message'].to_s.lines.map(&:strip).reject(&:empty?).join(': ')}", error["hint"]].compact.join(" — ")
    end
    "❌ The notation was not drawn. Fix it and call render_syntax_tree again:\n#{lines.join("\n")}"
  rescue JSON::ParserError
    "❌ Error generating syntax tree: #{err.to_s.strip[0, 1000]}"
  rescue Monadic::Shell::TimedOut, SystemCallError => e
    "❌ Error generating syntax tree: #{e.message}"
  end

  # Draws the notation in format into dir (syntree.<ext>); nil when drawn,
  # or what went wrong.
  def draw(input, style, format, dir)
    out, err, status = run_rsyntaxtree(["-f", format, "-o", dir, "-u", "syntree", *style, input])
    status.success? ? nil : "#{err}#{out}".strip[0, 1000]
  rescue Monadic::Shell::TimedOut, SystemCallError => e
    e.message
  end

  def run_rsyntaxtree(args)
    Monadic::Shell.capture([COMMAND, *args], timeout: DRAW_TIMEOUT, env: unbundled_env)
  end

  # The environment without the app's bundle in it (a variable the bundle
  # set is unset, one it changed is put back).
  def unbundled_env
    return {} unless defined?(Bundler) && Bundler.respond_to?(:unbundled_env)

    original = Bundler.unbundled_env
    ENV.keys.each_with_object(original.dup) { |key, env| env[key] = nil unless original.key?(key) }
  end
end

# OpenAI version uses shared tools
class SyntaxTreeOpenAI < MonadicApp
  include OpenAIHelper
  include SyntaxTreeTools
end

# Claude version uses shared tools
class SyntaxTreeClaude < MonadicApp
  include ClaudeHelper
  include SyntaxTreeTools
end
