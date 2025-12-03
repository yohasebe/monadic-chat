# frozen_string_literal: true

# Novel Writer tools using Monadic Session State mechanism.
# Manages story context (plot, characters, progress) without embedding JSON in responses.

module NovelWriterTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include Monadic::SharedTools::MonadicSessionState

  STATE_KEY = "novel_context"

  # Count number of words in text
  def count_num_of_words(text: "")
    text.split.size
  end

  # Count number of characters in text
  def count_num_of_chars(text: "")
    text.size
  end

  # Save novel context to session state.
  # Called by LLM when story elements change.
  #
  # @param grand_plot [String] Brief description of the overarching plot
  # @param total_text_amount [Integer] Target word/character count
  # @param text_amount_so_far [Integer] Current word/character count
  # @param language [String] Language used in the novel
  # @param summary_so_far [String] Summary of the story up to current point
  # @param progress [String] Current progress (e.g., "25%")
  # @param characters [Hash] Dictionary of characters with their specifications
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def save_novel_context(grand_plot: nil, total_text_amount: nil, text_amount_so_far: nil,
                         language: nil, summary_so_far: nil, progress: nil,
                         characters: nil, session: nil)
    existing = load_novel_context_internal(session)

    context = {
      grand_plot: grand_plot || existing[:grand_plot],
      total_text_amount: total_text_amount || existing[:total_text_amount],
      text_amount_so_far: text_amount_so_far || existing[:text_amount_so_far],
      language: language || existing[:language],
      summary_so_far: summary_so_far || existing[:summary_so_far],
      progress: progress || existing[:progress],
      characters: characters || existing[:characters] || {}
    }

    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Load novel context from session state.
  # Called by LLM when it needs to reference story state.
  #
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with context data
  def load_novel_context(session: nil)
    default_context = {
      grand_plot: nil,
      total_text_amount: nil,
      text_amount_so_far: 0,
      language: nil,
      summary_so_far: nil,
      progress: "0%",
      characters: {}
    }
    monadic_load_state(key: STATE_KEY, default: default_context, session: session)
  end

  # Add or update a character in the novel.
  # Accumulates characters without overwriting existing ones.
  #
  # @param name [String] Character name
  # @param specification [String] Character description and traits
  # @param role [String] Character's role in the story
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with updated characters
  def add_character(name:, specification:, role:, session: nil)
    existing = load_novel_context_internal(session)
    characters = existing[:characters] || {}

    characters[name] = {
      specification: specification,
      role: role
    }

    save_novel_context(
      grand_plot: existing[:grand_plot],
      total_text_amount: existing[:total_text_amount],
      text_amount_so_far: existing[:text_amount_so_far],
      language: existing[:language],
      summary_so_far: existing[:summary_so_far],
      progress: existing[:progress],
      characters: characters,
      session: session
    )
  end

  # Update story progress after writing a new section.
  # Automatically updates text_amount_so_far and progress percentage.
  #
  # @param new_text [String] The newly written text to add to the count
  # @param use_chars [Boolean] Use character count instead of word count (for CJK languages)
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with updated progress
  def update_progress(new_text:, use_chars: false, session: nil)
    existing = load_novel_context_internal(session)

    # Calculate new amount
    new_amount = use_chars ? count_num_of_chars(text: new_text) : count_num_of_words(text: new_text)
    current_amount = (existing[:text_amount_so_far] || 0) + new_amount
    total = existing[:total_text_amount] || 1

    # Calculate progress percentage
    progress_percent = [(current_amount.to_f / total * 100).round, 100].min
    progress_str = "#{progress_percent}%"

    save_novel_context(
      grand_plot: existing[:grand_plot],
      total_text_amount: existing[:total_text_amount],
      text_amount_so_far: current_amount,
      language: existing[:language],
      summary_so_far: existing[:summary_so_far],
      progress: progress_str,
      characters: existing[:characters],
      session: session
    )
  end

  # Update the story summary.
  # Called when significant plot developments occur.
  #
  # @param summary [String] Updated summary of the story
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def update_summary(summary:, session: nil)
    existing = load_novel_context_internal(session)

    save_novel_context(
      grand_plot: existing[:grand_plot],
      total_text_amount: existing[:total_text_amount],
      text_amount_so_far: existing[:text_amount_so_far],
      language: existing[:language],
      summary_so_far: summary,
      progress: existing[:progress],
      characters: existing[:characters],
      session: session
    )
  end

  private

  # Internal helper to load context as Ruby hash (not JSON string)
  def load_novel_context_internal(session)
    result = JSON.parse(monadic_load_state(key: STATE_KEY, default: {}, session: session))
    data = result["data"] || {}
    {
      grand_plot: data["grand_plot"],
      total_text_amount: data["total_text_amount"],
      text_amount_so_far: data["text_amount_so_far"] || 0,
      language: data["language"],
      summary_so_far: data["summary_so_far"],
      progress: data["progress"] || "0%",
      characters: (data["characters"] || {}).transform_keys(&:to_s)
    }
  rescue StandardError
    {
      grand_plot: nil,
      total_text_amount: nil,
      text_amount_so_far: 0,
      language: nil,
      summary_so_far: nil,
      progress: "0%",
      characters: {}
    }
  end
end

# Class definition for Novel Writer app with OpenAI
class NovelWriterOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include NovelWriterTools
end
