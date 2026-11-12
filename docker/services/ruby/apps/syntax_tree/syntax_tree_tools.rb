require 'json'
require 'tmpdir'
require_relative '../../lib/monadic/shell'
require_relative '../../lib/monadic/workspace/jobs'
require_relative '../../lib/monadic/workspace/chats'
require_relative '../../lib/monadic/utils/shared_path_guard'
require_relative '../../lib/monadic/shared_tools/workbench_tools'

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

      job = syntax_tree_job(session, workbench)
      return "❌ The syntax tree could not be kept: there is no chat folder to keep it in." unless job

      formats = tikz ? { "svg" => OUTPUT_NAME, "tikz" => TIKZ_NAME } : { "svg" => OUTPUT_NAME }
      formats.each do |format, name|
        failure = draw(input, style, format, dir)
        if failure
          drop_empty_job(job)
          return "❌ Error generating syntax tree: #{failure}"
        end
        drawn = File.binread(File.join(dir, "syntree.#{format == 'tikz' ? 'tex' : format}"))
        Monadic::Utils::SharedPathGuard.write_file!(File.join(job[:path], name), drawn, mode: "wb", replace: false, strict: true)
      end

      path = File.join(job[:relative], OUTPUT_NAME)
      said = workbench ? MonadicSharedTools::WorkbenchTools.show_file(path, workbench) : ""
      shown = said.start_with?("{") ? " It is shown on the work screen beside the chat." : ""
      source = tikz ? " Its LaTeX (forest) source is #{File.join(job[:relative], TIKZ_NAME)}; movement paths are not in it." : ""
      "The syntax tree was drawn as #{path}.#{shown}#{source}"
    end
  rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError => e
    drop_empty_job(job) if job
    "❌ The syntax tree could not be kept: #{e.message}"
  end

  private

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

  # A run folder in the chat's folder for one drawing: the chat the reply
  # was asked in, or the session's. nil without a chat or its folder.
  def syntax_tree_job(session, workbench)
    chat_id = workbench&.chat_id || (session && session[Monadic::Workspace::Chats::SESSION_KEY])
    return nil unless Monadic::Workspace::Ids.valid?(:chat, chat_id)

    app_name = (session && session.dig(:parameters, "app_name")) || self.class.name
    folder = Monadic::Workspace::Folders.ensure_for_chat!(chat_id, app_name: app_name)
    return nil unless folder[:status] == :ready

    Monadic::Workspace::Jobs.create!(folder[:workspace_id])
  rescue Monadic::Workspace::Folders::Unavailable, Monadic::Workspace::Jobs::Unavailable,
         Monadic::Workspace::Ledger::Unreadable
    nil
  end

  # A run folder a failed drawing left empty goes; one with anything in it
  # stays.
  def drop_empty_job(job)
    Dir.rmdir(job[:path]) if Monadic::Workspace::Folders.real_path(job[:relative], :directory)
  rescue SystemCallError
    nil
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
