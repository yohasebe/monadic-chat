# frozen_string_literal: true

# Math Tutor application tools for learning progress tracking.
# Uses Monadic Session State mechanism for context tracking.

module MathTutorTools
  include MonadicHelper
  include Monadic::SharedTools::MonadicSessionState

  STATE_KEY = "math_tutor_context"

  # Save learning progress and context to session state.
  #
  # @param message [String] Response message to the user
  # @param current_problem [String] The current problem being worked on
  # @param problems_solved [Array<String>] Problems solved with brief descriptions
  # @param concepts_covered [Array<String>] Mathematical concepts covered
  # @param weak_areas [Array<String>] Areas where student needs more practice
  # @param learning_notes [Array<String>] Important notes about the student's progress
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def save_learning_progress(message:, current_problem: nil, problems_solved: nil,
                             concepts_covered: nil, weak_areas: nil, learning_notes: nil, session: nil)
    existing = load_progress_internal(session)

    context = {
      current_problem: current_problem || existing[:current_problem],
      problems_solved: problems_solved || existing[:problems_solved] || [],
      concepts_covered: concepts_covered || existing[:concepts_covered] || [],
      weak_areas: weak_areas || existing[:weak_areas] || [],
      learning_notes: learning_notes || existing[:learning_notes] || [],
      last_message: message
    }

    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Load learning progress from session state.
  # Called by LLM to check current learning state.
  #
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with context data
  def load_learning_progress(session: nil)
    default_context = {
      current_problem: nil,
      problems_solved: [],
      concepts_covered: [],
      weak_areas: [],
      learning_notes: [],
      last_message: nil
    }
    monadic_load_state(key: STATE_KEY, default: default_context, session: session)
  end

  # Add a solved problem to the learning history.
  #
  # @param problem [String] Description of the problem solved
  # @param solution_method [String] Method or approach used to solve it
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def add_solved_problem(problem:, solution_method: nil, session: nil)
    existing = load_progress_internal(session)
    entry = solution_method ? "#{problem} (#{solution_method})" : problem
    all_problems = (existing[:problems_solved] || []) + [entry]
    all_problems = all_problems.uniq

    context = existing.merge(problems_solved: all_problems)
    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Add concepts covered in the tutoring session.
  #
  # @param concepts [Array<String>] Mathematical concepts to add
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def add_concepts(concepts:, session: nil)
    existing = load_progress_internal(session)
    all_concepts = (existing[:concepts_covered] || []) + (concepts || [])
    all_concepts = all_concepts.uniq

    context = existing.merge(concepts_covered: all_concepts)
    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Record weak areas that need more practice.
  #
  # @param areas [Array<String>] Areas where student struggles
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def add_weak_areas(areas:, session: nil)
    existing = load_progress_internal(session)
    all_areas = (existing[:weak_areas] || []) + (areas || [])
    all_areas = all_areas.uniq

    context = existing.merge(weak_areas: all_areas)
    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  # Add learning notes about the student's progress.
  #
  # @param notes [Array<String>] Notes to add
  # @param session [Hash] Session object (automatically provided)
  # @return [String] JSON response with success status
  def add_learning_notes(notes:, session: nil)
    existing = load_progress_internal(session)
    all_notes = (existing[:learning_notes] || []) + (notes || [])
    all_notes = all_notes.uniq

    context = existing.merge(learning_notes: all_notes)
    monadic_save_state(key: STATE_KEY, payload: context, session: session)
  end

  private

  # Internal helper to load progress as Ruby hash (not JSON string)
  def load_progress_internal(session)
    result = JSON.parse(monadic_load_state(key: STATE_KEY, default: {}, session: session))
    data = result["data"] || {}
    {
      current_problem: data["current_problem"],
      problems_solved: data["problems_solved"] || [],
      concepts_covered: data["concepts_covered"] || [],
      weak_areas: data["weak_areas"] || [],
      learning_notes: data["learning_notes"] || [],
      last_message: data["last_message"]
    }
  rescue StandardError
    {
      current_problem: nil,
      problems_solved: [],
      concepts_covered: [],
      weak_areas: [],
      learning_notes: [],
      last_message: nil
    }
  end

  def validate_math_input(expression)
    raise ArgumentError, "Expression cannot be empty" if expression.to_s.strip.empty?
    true
  end
end

# Class definitions for Math Tutor apps
class MathTutorOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include MathTutorTools
end

class MathTutorClaude < MonadicApp
  include ClaudeHelper if defined?(ClaudeHelper)
  include MathTutorTools
end

class MathTutorGemini < MonadicApp
  include GeminiHelper if defined?(GeminiHelper)
  include MathTutorTools
end

class MathTutorGrok < MonadicApp
  include GrokHelper if defined?(GrokHelper)
  include MathTutorTools
end
