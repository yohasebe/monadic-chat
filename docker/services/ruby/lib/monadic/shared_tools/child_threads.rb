# frozen_string_literal: true

module MonadicSharedTools
  # Threads a tool starts for its sub-tasks. They are stopped when the tool
  # is done waiting for them, and also when the reply running the tool is
  # itself stopped (Reset or Cancel kill its thread; the tool's ensure runs).
  module ChildThreads
    module_function

    WAIT = 5 # seconds for the stopped threads' own clean-up

    # Starts a sub-task thread and adds it to `threads` with no gap between
    # the two in which the caller could be stopped (the kill waits until the
    # thread is in the list). The new thread would inherit that deferral, so
    # it takes interrupts again for its own work.
    def spawn(threads, *args, &work)
      Thread.handle_interrupt(Object => :never) do
        threads << Thread.new(*args) do |*inner|
          Thread.handle_interrupt(Object => :immediate) { work.call(*inner) }
        end
      end
    end

    # quiet: true when the reply itself was stopped (the page has moved on,
    # so the stopped threads report nothing); false for ones that only ran
    # past the tool's own wait, which still report as they end.
    def stop(threads, quiet: true)
      running = Array(threads).select(&:alive?)
      running.each do |t|
        t[:stopped_with_reply] = true if quiet
        t.kill
      end
      running.each { |t| t.join(WAIT) }
    end
  end
end
