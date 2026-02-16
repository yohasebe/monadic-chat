# frozen_string_literal: true

module MonadicSharedTools
  module Verification
    include MonadicHelper

    MAX_VERIFICATION_RETRIES = 3

    # Record the outcome of verifying work before presenting it to the user.
    # The model calls this tool after using verification tools (run_code,
    # preview_mermaid, etc.) or after self-reviewing outputs.
    def report_verification(result_summary:, checks_performed:, status:, issues: nil, fixes_applied: nil, session: nil)
      if session
        session[:verification_history] ||= []
        session[:verification_history] << {
          result_summary: result_summary,
          checks_performed: checks_performed,
          status: status,
          issues: issues,
          fixes_applied: fixes_applied,
          verified_at: Time.now.to_f,
          attempt: session[:verification_history].length + 1
        }
      end

      # Emit a wait message so the temp card UI shows verification status
      if session
        attempts = session[:verification_history]&.length || 0
        label = case status
                when "passed"
                  "Verification: Passed"
                when "issues_found"
                  "Verification: Issues Found (attempt #{attempts}/#{MAX_VERIFICATION_RETRIES})"
                when "fixed"
                  "Verification: Fixed"
                else
                  "Verification: Limit Reached"
                end
        session[:verification_wait_message] = "<i class='fas fa-clipboard-check'></i> #{label}"
      end

      # Force-stop the tool call loop when verification passes or issues are fixed.
      # This prevents models from ignoring the text instruction and continuing to call tools.
      # Works for all providers that use session[:call_depth_per_turn] (OpenAI, Claude, Gemini, etc.)
      if session && (status == "passed" || status == "fixed")
        session[:call_depth_per_turn] = 9999
      end

      # Force-stop when consecutive failures exceed retry limit.
      # Models may ignore the MDSL text instruction ("Maximum 3 verification attempts")
      # and loop indefinitely on issues_found. This enforces the limit in code.
      if session && status == "issues_found"
        consecutive_issues = 0
        session[:verification_history].reverse_each do |v|
          break unless v[:status] == "issues_found"
          consecutive_issues += 1
        end

        if consecutive_issues >= MAX_VERIFICATION_RETRIES
          session[:call_depth_per_turn] = 9999
          session[:verification_wait_message] = "<i class='fas fa-clipboard-check'></i> Verification: Limit Reached"

          notebook_url_line = if session[:last_notebook_url]
                                "\nNotebook URL: #{session[:last_notebook_url]}"
                              else
                                ""
                              end

          return <<~RESULT
            VERIFICATION LIMIT REACHED (#{consecutive_issues} consecutive attempts failed).
            Present your best results to the user as-is.#{notebook_url_line}
            Mention which issues remain unresolved: #{Array(issues).join('; ')}
            Do NOT call any more tools.
          RESULT
        end
      end

      # Include notebook URL from session if available, to prevent model hallucination of URLs
      notebook_url_line = if session && session[:last_notebook_url]
                            "\nNotebook URL: #{session[:last_notebook_url]}"
                          else
                            ""
                          end

      case status
      when "passed"
        <<~RESULT
          VERIFICATION PASSED. Now present your results to the user.
          You may briefly mention that you verified the output.#{notebook_url_line}
          Do NOT call any more tools.
        RESULT
      when "issues_found"
        <<~RESULT
          ISSUES FOUND. You MUST:
          1. Fix the issues listed below using the appropriate tools
          2. Re-verify by calling report_verification again
          3. Do NOT present results to the user until verification passes

          Issues: #{Array(issues).join('; ')}
        RESULT
      when "fixed"
        <<~RESULT
          ISSUES FIXED. Present the corrected results to the user.
          Briefly mention what was fixed: #{Array(fixes_applied).join('; ')}#{notebook_url_line}
          Do NOT call any more tools.
        RESULT
      end
    end
  end
end
