# frozen_string_literal: true

module MonadicSharedTools
  module Planning
    include MonadicHelper

    # Propose a structured execution plan for a complex multi-step task.
    # The model calls this tool BEFORE executing when a task requires
    # 3 or more distinct steps. The tool result instructs the model
    # to present the plan and wait for user approval.
    def propose_plan(plan:, summary:, session: nil)
      if session
        session[:proposed_plan] = {
          summary: summary,
          plan: plan,
          proposed_at: Time.now.to_f,
          status: "pending"
        }
      end

      # Check autonomy level
      autonomy = session&.dig(:parameters, "autonomy") || session&.dig(:parameters, :autonomy)

      if autonomy.to_s == "high"
        session[:proposed_plan][:status] = "auto_approved" if session&.dig(:proposed_plan)
        <<~RESULT
          PLAN AUTO-APPROVED (high autonomy mode).
          Proceed to execute all steps immediately without waiting for user approval.
          Report results after completing the sequence.

          Plan summary: #{summary}

          Plan details:
          #{plan}
        RESULT
      else
        <<~RESULT
          PLAN REGISTERED. Now you MUST:
          1. Present the plan below to the user in a clear, readable format
          2. Ask the user if they would like to proceed, modify, or cancel
          3. Do NOT execute any steps until the user explicitly approves

          Plan summary: #{summary}

          Plan details:
          #{plan}
        RESULT
      end
    end
  end
end
