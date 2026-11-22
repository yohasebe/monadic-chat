# frozen_string_literal: true

require 'timeout'

# An answer's worker stays until its answer is taken to be recorded (the
# HTML handler) or is cancelled, so a spec that wants the answer made waits
# on its handle instead of joining the thread.
module ReplyWait
  def wait_for_answer_made(thread, limit = 10)
    handle = thread && thread[:reply_handle]
    return thread&.join(limit) unless handle

    Timeout.timeout(limit) { handle.wait_answer }
  end
end

RSpec.configure { |config| config.include ReplyWait }
