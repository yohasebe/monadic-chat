# frozen_string_literal: true

# Novel Writer tools on the app's state kept by turn (Monadic::TurnState):
# the story's settings are a value, each character an item of its own, and
# the amount written is counted from the story's sections on the work
# screen. Deleting a turn takes back what it changed.

module NovelWriterTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include Monadic::SharedTools::MonadicSessionState

  STATE_KEY = "novel_context"
  CHARACTERS = "characters"
  # The settings the story keeps as one value (the characters and the
  # amount written are kept apart).
  SETTINGS = %w[grand_plot total_text_amount language summary_so_far count_by].freeze

  # Count number of words in text
  def count_num_of_words(text: "")
    text.split.size
  end

  # Count number of characters in text
  def count_num_of_chars(text: "")
    text.size
  end

  # Save novel context.
  # Called by LLM when story elements change.
  #
  # @param grand_plot [String] Brief description of the overarching plot
  # @param total_text_amount [Integer] Target word/character count
  # @param text_amount_so_far [Integer] Ignored: counted from the story's sections
  # @param language [String] Language used in the novel
  # @param summary_so_far [String] Summary of the story up to current point
  # @param progress [String] Ignored: counted from the story's sections
  # @param characters [Hash] Dictionary of characters with their specifications
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def save_novel_context(grand_plot: nil, total_text_amount: nil, text_amount_so_far: nil,
                         language: nil, summary_so_far: nil, progress: nil,
                         characters: nil, session: nil)
    _ = [text_amount_so_far, progress]
    given = { "grand_plot" => grand_plot, "total_text_amount" => total_text_amount,
              "language" => language, "summary_so_far" => summary_so_far }.compact
    novel_settings_change(session) { |now| now.merge(given) } unless given.empty?
    novel_characters_replace(session, characters) if characters.is_a?(Hash)
    load_novel_context(session: session)
  rescue Monadic::TurnState::Refused => e
    { success: false, error: e.message }.to_json
  end

  # Load novel context.
  # Called by LLM when it needs to reference story state.
  #
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with context data
  def load_novel_context(session: nil)
    novel_converted_base!(session)
    settings = novel_settings(session)
    amount = novel_amount_written(session, settings["count_by"])
    total = settings["total_text_amount"].to_i
    progress = total.positive? ? "#{[(amount.to_f / total * 100).round, 100].min}%" : "0%"
    data = settings.slice(*SETTINGS - ["count_by"]).merge(
      "text_amount_so_far" => amount, "progress" => progress, "characters" => novel_characters(session)
    )
    { success: true, key: STATE_KEY, data: data }.to_json
  end

  # Add or update a character in the novel.
  #
  # @param name [String] Character name
  # @param specification [String] Character description and traits
  # @param role [String] Character's role in the story
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with updated context
  def add_character(name:, specification:, role:, session: nil)
    novel_converted_base!(session)
    novel_put_character(session, name.to_s, { "specification" => specification, "role" => role })
    load_novel_context(session: session)
  rescue Monadic::TurnState::Refused => e
    { success: false, error: e.message }.to_json
  end

  # Update story progress after writing a new section: the amount written
  # is counted from the story's sections (new_text is the section just
  # written, already among them).
  #
  # @param new_text [String] The newly written text
  # @param use_chars [Boolean] Count characters instead of words (for CJK languages)
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with updated progress
  def update_progress(new_text: "", use_chars: false, session: nil)
    _ = new_text
    count_by = use_chars ? "chars" : "words"
    novel_settings_change(session) { |now| now.merge("count_by" => count_by) } if novel_settings(session)["count_by"] != count_by
    load_novel_context(session: session)
  rescue Monadic::TurnState::Refused => e
    { success: false, error: e.message }.to_json
  end

  # Update the story summary.
  #
  # @param summary [String] Updated summary of the story
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def update_summary(summary:, session: nil)
    novel_settings_change(session) { |now| now.merge("summary_so_far" => summary) }
    load_novel_context(session: session)
  rescue Monadic::TurnState::Refused => e
    { success: false, error: e.message }.to_json
  end

  private

  # The story's notes on the work screen (Monadic::TurnState::Notes): its
  # settings and characters, as the conversation leaves them.
  def state_notes
    { title: "Story notes", key: STATE_KEY,
      values: { "grand_plot" => "Plot", "summary_so_far" => "Summary so far", "language" => "Language",
                "total_text_amount" => "Target length" },
      lists: { CHARACTERS => { label: "Characters", name: "name",
                               fields: { "role" => "Role", "specification" => "Description" } } } }
  end

  # The amount written and the progress, counted from the story.
  def state_notes_extra(session)
    data = JSON.parse(load_novel_context(session: session))["data"] || {}
    { "Written so far" => data["text_amount_so_far"].to_s, "Progress" => data["progress"] }
  end

  # The story's settings now (a Hash with string keys).
  def novel_settings(session)
    data = JSON.parse(monadic_load_state(key: STATE_KEY, default: {}, session: session))["data"]
    (data.is_a?(Hash) ? data : {}).slice(*SETTINGS)
  end

  def novel_settings_change(session)
    monadic_update_state(key: STATE_KEY, default: {}, session: session) do |now|
      yield((now.is_a?(Hash) ? now : {}).slice(*SETTINGS))
    end
  end

  # The characters now: { name => { "specification", "role" } }.
  def novel_characters(session)
    novel_character_items(session).to_h { |item| [item[:data]["name"], item[:data].except("name")] }
  end

  def novel_character_items(session)
    Monadic::TurnState.items(session, CHARACTERS).select { |item| item[:data].is_a?(Hash) && item[:data]["name"] }
  end

  # Puts one character, under the id it has when its name is known; only
  # what changed is kept.
  def novel_put_character(session, name, spec)
    found = novel_character_items(session).find { |item| item[:data]["name"] == name }
    value = { "name" => name }.merge(spec.transform_keys(&:to_s))
    return if found && found[:data] == value

    Monadic::TurnState.put_item(session, CHARACTERS, value, id: found && found[:id])
  end

  # The characters as given in full: those added or changed are put, those
  # left out removed, the others not touched.
  def novel_characters_replace(session, characters)
    given = characters.to_h { |name, spec| [name.to_s, spec.is_a?(Hash) ? spec : { "specification" => spec.to_s }] }
    given.each { |name, spec| novel_put_character(session, name, spec) }
    novel_character_items(session).each do |item|
      Monadic::TurnState.remove_item(session, CHARACTERS, item[:id]) unless given.key?(item[:data]["name"])
    end
  end

  # A chat that began from a file of an earlier version has its characters
  # in the story's settings: they become items of the base once.
  def novel_converted_base!(session)
    monadic_record_base!(session, STATE_KEY, { CHARACTERS => "name" })
  end

  # How much of the story is written: the sections on the work screen
  # (the newest of each), headings left out, in words or characters.
  def novel_amount_written(session, count_by)
    text = Monadic::Workbench::Document.section_texts(session).map do |body|
      body.lines.reject { |line| line.lstrip.start_with?("#") }.join
    end.join("\n")
    count_by == "chars" ? text.gsub(/\s+/, "").size : count_num_of_words(text: text)
  end
end

# Class definition for Novel Writer app with OpenAI
class NovelWriterOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include NovelWriterTools
end

# Class definition for Novel Writer app with Mistral
class NovelWriterMistral < MonadicApp
  include MistralHelper if defined?(MistralHelper)
  include NovelWriterTools
end

# Class definition for Novel Writer app with DeepSeek
class NovelWriterDeepSeek < MonadicApp
  include DeepSeekHelper if defined?(DeepSeekHelper)
  include NovelWriterTools
end
