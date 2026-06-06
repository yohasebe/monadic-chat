# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/dsl'
require_relative '../../../lib/monadic/dsl/loader'

# Phase 5 of the KB/PF MDSL SSOT refactor: every MDSL in apps/ is
# walked at suite startup and its resolved capability flags are pinned
# against an explicit, hand-maintained allocation.
#
# Two complementary contracts are enforced:
#
#   1. Per-MDSL invariants (always-on guards on the DSL itself).
#      - privacy_enabled=true ⇒ library_save=false AND library_search=false
#      - library_search=true  ⇒ library_save=true
#      These mirror finalize_capabilities! invariants in lib/monadic/dsl.rb;
#      this spec is the second line of defense if invariants ever weaken.
#
#   2. Group allocation pins (coverage check).
#      Every MDSL must appear in exactly one of four lists below
#      (PF-only / KB-search / KB-save-only / Neither). Adding a new MDSL
#      → spec fails with "uncategorized MDSL: …", forcing the developer
#      to think about its capability profile and add it to the correct
#      list. Renaming or moving an MDSL similarly fails until the spec
#      is updated, keeping the docs/basic-usage/basic-apps.md table in
#      lockstep with the code.
#
# Production load order is mirrored at suite startup: all .rb companion
# files (constants/tools) are pre-required before MDSL evaluation, so
# constants like KnowledgeBaseConstants::SYSTEM_PROMPT are visible during
# the DSL eval (matching how lib/monadic.rb#load_app_files orders things).

APPS_DIR = File.expand_path('../../../apps', __dir__)

# Pre-require companion .rb files so MDSL eval has the symbols it needs.
# Best-effort — a few app-specific files may have test-env-only deps;
# any resulting MDSL load failure surfaces in the load_errors spec below.
Dir["#{APPS_DIR}/**/*.rb"].sort.each do |f|
  begin
    require f
  rescue Exception # rubocop:disable Lint/RescueException
    # silently skip — load_errors spec will surface MDSL-level failures
  end
end

ALL_MDSL_FILES = Dir["#{APPS_DIR}/**/*.mdsl"].sort.freeze

# Hand-maintained allocation of every MDSL into one of four capability
# groups. Sizes are sanity-pinned: 25 + 56 + 27 + 26 = 134 (one entry
# per file under apps/). When you add a new MDSL, append it to the
# right list — the spec will tell you which one is wrong.
PF_ONLY_MDSLS = %w[
  chat_plus/chat_plus_claude.mdsl
  chat_plus/chat_plus_cohere.mdsl
  chat_plus/chat_plus_deepseek.mdsl
  chat_plus/chat_plus_gemini.mdsl
  chat_plus/chat_plus_grok.mdsl
  chat_plus/chat_plus_mistral.mdsl
  chat_plus/chat_plus_openai.mdsl
  mail_composer/mail_composer_claude.mdsl
  mail_composer/mail_composer_cohere.mdsl
  mail_composer/mail_composer_deepseek.mdsl
  mail_composer/mail_composer_gemini.mdsl
  mail_composer/mail_composer_grok.mdsl
  mail_composer/mail_composer_mistral.mdsl
  mail_composer/mail_composer_ollama.mdsl
  mail_composer/mail_composer_openai.mdsl
  second_opinion/second_opinion_claude.mdsl
  second_opinion/second_opinion_cohere.mdsl
  second_opinion/second_opinion_deepseek.mdsl
  second_opinion/second_opinion_gemini.mdsl
  second_opinion/second_opinion_grok.mdsl
  second_opinion/second_opinion_mistral.mdsl
  second_opinion/second_opinion_openai.mdsl
  translate/translate_cohere.mdsl
  translate/translate_openai.mdsl
].freeze

KB_SEARCH_MDSLS = %w[
  chat/chat_claude.mdsl
  chat/chat_cohere.mdsl
  chat/chat_deepseek.mdsl
  chat/chat_gemini.mdsl
  chat/chat_grok.mdsl
  chat/chat_mistral.mdsl
  chat/chat_ollama.mdsl
  chat/chat_openai.mdsl
  coding_assistant/coding_assistant_claude.mdsl
  coding_assistant/coding_assistant_cohere.mdsl
  coding_assistant/coding_assistant_deepseek.mdsl
  coding_assistant/coding_assistant_gemini.mdsl
  coding_assistant/coding_assistant_grok.mdsl
  coding_assistant/coding_assistant_mistral.mdsl
  coding_assistant/coding_assistant_ollama.mdsl
  coding_assistant/coding_assistant_openai.mdsl
  language_practice/language_practice_claude.mdsl
  language_practice/language_practice_cohere.mdsl
  language_practice/language_practice_deepseek.mdsl
  language_practice/language_practice_gemini.mdsl
  language_practice/language_practice_grok.mdsl
  language_practice/language_practice_mistral.mdsl
  language_practice/language_practice_ollama.mdsl
  language_practice/language_practice_openai.mdsl
  language_practice_plus/language_practice_plus_claude.mdsl
  language_practice_plus/language_practice_plus_openai.mdsl
  math_tutor/math_tutor_claude.mdsl
  math_tutor/math_tutor_cohere.mdsl
  math_tutor/math_tutor_deepseek.mdsl
  math_tutor/math_tutor_gemini.mdsl
  math_tutor/math_tutor_grok.mdsl
  math_tutor/math_tutor_mistral.mdsl
  math_tutor/math_tutor_openai.mdsl
  novel_writer/novel_writer_mistral.mdsl
  novel_writer/novel_writer_openai.mdsl
  research_assistant/research_assistant_claude.mdsl
  research_assistant/research_assistant_cohere.mdsl
  research_assistant/research_assistant_deepseek.mdsl
  research_assistant/research_assistant_gemini.mdsl
  research_assistant/research_assistant_grok.mdsl
  research_assistant/research_assistant_mistral.mdsl
  research_assistant/research_assistant_openai.mdsl
  speech_draft_helper/speech_draft_helper_openai.mdsl
  voice_chat/voice_chat_claude.mdsl
  voice_chat/voice_chat_cohere.mdsl
  voice_chat/voice_chat_deepseek.mdsl
  voice_chat/voice_chat_gemini.mdsl
  voice_chat/voice_chat_grok.mdsl
  voice_chat/voice_chat_mistral.mdsl
  voice_chat/voice_chat_ollama.mdsl
  voice_chat/voice_chat_openai.mdsl
  wikipedia/wikipedia.mdsl
].freeze

KB_SAVE_ONLY_MDSLS = %w[
  code_interpreter/code_interpreter_claude.mdsl
  code_interpreter/code_interpreter_cohere.mdsl
  code_interpreter/code_interpreter_deepseek.mdsl
  code_interpreter/code_interpreter_gemini.mdsl
  code_interpreter/code_interpreter_grok.mdsl
  code_interpreter/code_interpreter_mistral.mdsl
  code_interpreter/code_interpreter_openai.mdsl
  jupyter_notebook/jupyter_notebook_claude.mdsl
  jupyter_notebook/jupyter_notebook_gemini.mdsl
  jupyter_notebook/jupyter_notebook_grok.mdsl
  jupyter_notebook/jupyter_notebook_openai.mdsl
  knowledge_base/knowledge_base_claude.mdsl
  knowledge_base/knowledge_base_cohere.mdsl
  knowledge_base/knowledge_base_deepseek.mdsl
  knowledge_base/knowledge_base_gemini.mdsl
  knowledge_base/knowledge_base_grok.mdsl
  knowledge_base/knowledge_base_mistral.mdsl
  knowledge_base/knowledge_base_ollama.mdsl
  knowledge_base/knowledge_base_openai.mdsl
  monadic_help/monadic_help_openai.mdsl
  video_describer/video_describer_app.mdsl
  voice_interpreter/voice_interpreter_cohere.mdsl
  voice_interpreter/voice_interpreter_openai.mdsl
  web_insight/web_insight_claude.mdsl
  web_insight/web_insight_gemini.mdsl
  web_insight/web_insight_grok.mdsl
  web_insight/web_insight_openai.mdsl
].freeze

NEITHER_MDSLS = %w[
  auto_forge/auto_forge_claude.mdsl
  auto_forge/auto_forge_grok.mdsl
  auto_forge/auto_forge_openai.mdsl
  concept_visualizer/concept_visualizer_claude.mdsl
  concept_visualizer/concept_visualizer_openai.mdsl
  document_generator/document_generator_claude.mdsl
  drawio_grapher/drawio_grapher_claude.mdsl
  drawio_grapher/drawio_grapher_gemini.mdsl
  drawio_grapher/drawio_grapher_grok.mdsl
  drawio_grapher/drawio_grapher_openai.mdsl
  image_generator/image_generator_gemini.mdsl
  image_generator/image_generator_grok.mdsl
  image_generator/image_generator_openai.mdsl
  mermaid_grapher/mermaid_grapher_claude.mdsl
  mermaid_grapher/mermaid_grapher_gemini.mdsl
  mermaid_grapher/mermaid_grapher_grok.mdsl
  mermaid_grapher/mermaid_grapher_openai.mdsl
  music_analyst/music_analyst_gemini.mdsl
  music_lab/music_lab_claude.mdsl
  music_lab/music_lab_gemini.mdsl
  music_lab/music_lab_grok.mdsl
  music_lab/music_lab_openai.mdsl
  syntax_tree/syntax_tree_claude.mdsl
  syntax_tree/syntax_tree_openai.mdsl
  video_generator/video_generator_gemini.mdsl
  video_generator/video_generator_grok.mdsl
  video_generator/video_generator_openai.mdsl
].freeze

ALL_EXPECTED_MDSLS = (
  PF_ONLY_MDSLS + KB_SEARCH_MDSLS + KB_SAVE_ONLY_MDSLS + NEITHER_MDSLS
).freeze

RSpec.describe 'MonadicDSL capability consistency (Phase 5)' do
  before(:all) do
    @states = {}
    @load_errors = {}
    ALL_MDSL_FILES.each do |path|
      begin
        state = MonadicDSL::Loader.load(path)
        if state.respond_to?(:settings)
          @states[path] = state.settings
        else
          @load_errors[path] = 'no settings on returned object'
        end
      rescue Exception => e # rubocop:disable Lint/RescueException
        @load_errors[path] = "#{e.class}: #{e.message[0, 120]}"
      end
    end
  end

  describe 'load coverage' do
    it 'every MDSL in apps/ loads cleanly (constants/tools pre-required)' do
      next_steps = @load_errors.map { |path, err| "  #{path.sub("#{APPS_DIR}/", '')} — #{err}" }.join("\n")
      expect(@load_errors).to be_empty,
                              "Some MDSLs failed to load. The capability spec cannot validate them; fix the load error first.\n#{next_steps}"
    end
  end

  describe 'allocation list coverage' do
    it 'every MDSL on disk is allocated to exactly one expected group' do
      on_disk = ALL_MDSL_FILES.map { |p| p.sub("#{APPS_DIR}/", '') }.sort
      expected = ALL_EXPECTED_MDSLS.sort
      uncategorized = on_disk - expected
      stale = expected - on_disk
      duplicates = ALL_EXPECTED_MDSLS.tally.select { |_, n| n > 1 }.keys

      expect(uncategorized).to be_empty,
                               "New MDSL(s) found on disk but not in any expected group list. " \
                               "Add them to PF_ONLY_MDSLS / KB_SEARCH_MDSLS / KB_SAVE_ONLY_MDSLS / NEITHER_MDSLS:\n#{uncategorized.map { |s| "  #{s}" }.join("\n")}"
      expect(stale).to be_empty,
                       "Expected MDSL(s) no longer present on disk. Remove them from the list:\n#{stale.map { |s| "  #{s}" }.join("\n")}"
      expect(duplicates).to be_empty,
                            "MDSL(s) appear in more than one expected group:\n#{duplicates.map { |s| "  #{s}" }.join("\n")}"
    end
  end

  describe 'per-MDSL invariants (mirror finalize_capabilities!)' do
    ALL_MDSL_FILES.each do |path|
      rel = path.sub("#{APPS_DIR}/", '')

      it "#{rel}: privacy_enabled=true ⇒ library_save=false AND library_search=false" do
        s = @states[path]
        skip "load error: #{@load_errors[path]}" if s.nil?
        next unless s[:privacy_enabled] == true
        expect(s[:library_save]).to eq(false),   "#{rel}: privacy on but library_save is #{s[:library_save].inspect}"
        expect(s[:library_search]).to eq(false), "#{rel}: privacy on but library_search is #{s[:library_search].inspect}"
      end

      it "#{rel}: library_search=true ⇒ library_save=true" do
        s = @states[path]
        skip "load error: #{@load_errors[path]}" if s.nil?
        next unless s[:library_search] == true
        expect(s[:library_save]).to eq(true),
                                    "#{rel}: search-without-save is meaningless; library_save is #{s[:library_save].inspect}"
      end
    end
  end

  describe 'group allocation matches resolved capability flags' do
    # Each group implies a specific (privacy_enabled, library_save,
    # library_search) triple. This per-group sweep catches "wrong list"
    # mistakes — e.g., adding an artifact app to KB_SEARCH_MDSLS by
    # mistake would surface here as a triple mismatch.
    expected_triples = {
      pf_only:      { privacy_enabled: true,  library_save: false, library_search: false, list: PF_ONLY_MDSLS },
      kb_search:    { privacy_enabled: false, library_save: true,  library_search: true,  list: KB_SEARCH_MDSLS },
      kb_save_only: { privacy_enabled: false, library_save: true,  library_search: false, list: KB_SAVE_ONLY_MDSLS },
      neither:      { privacy_enabled: false, library_save: false, library_search: false, list: NEITHER_MDSLS }
    }

    expected_triples.each do |group, expected|
      describe "group: #{group}" do
        expected[:list].each do |rel|
          it "#{rel}: matches the #{group} triple (pe=#{expected[:privacy_enabled]}, save=#{expected[:library_save]}, search=#{expected[:library_search]})" do
            path = File.join(APPS_DIR, rel)
            s = @states[path]
            skip "load error: #{@load_errors[path]}" if s.nil?

            # privacy_enabled is absent (nil) for non-PF apps, set to true
            # for PF apps. Compare the resolved boolean explicitly so nil
            # is treated as "not enabled".
            expect(s[:privacy_enabled] == true).to eq(expected[:privacy_enabled]),
                                                   "#{rel}: privacy_enabled is #{s[:privacy_enabled].inspect}, expected #{expected[:privacy_enabled]}"
            expect(s[:library_save]).to eq(expected[:library_save])
            expect(s[:library_search]).to eq(expected[:library_search])
          end
        end
      end
    end
  end

  describe 'group sizes (sanity counters)' do
    # Pinned counts drift only when groups change, which is exactly the
    # situation we want to surface in code review. Update these when
    # consciously moving an app between groups.
    {
      'PF only'      => [PF_ONLY_MDSLS, 24],
      'KB search'    => [KB_SEARCH_MDSLS, 52],
      'KB save only' => [KB_SAVE_ONLY_MDSLS, 27],
      'Neither'      => [NEITHER_MDSLS, 27]
    }.each do |label, (list, expected_size)|
      it "#{label}: list size is #{expected_size}" do
        expect(list.size).to eq(expected_size),
                             "#{label} list has #{list.size} entries; expected #{expected_size}. " \
                             'If the change is intentional, update the count here too.'
      end
    end

    it 'allocation totals 129 (matches all *.mdsl on disk)' do
      expect(ALL_EXPECTED_MDSLS.size).to eq(ALL_MDSL_FILES.size)
    end
  end
end
