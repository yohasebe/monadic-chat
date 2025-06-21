# frozen_string_literal: true

# Startup performance profiler for Monadic Chat
class StartupProfiler
  class << self
    attr_accessor :timings

    def initialize
      @timings = {}
      @enabled = ENV['PROFILE_STARTUP'] == 'true'
    end

    def measure(phase_name)
      return yield unless @enabled

      start_time = Time.now
      result = yield
      end_time = Time.now
      
      @timings ||= {}
      @timings[phase_name] = {
        duration: end_time - start_time,
        timestamp: start_time
      }
      
      result
    end

    def report
      return unless @enabled && @timings

      puts "\n=== Startup Performance Report ==="
      total_time = 0
      
      sorted_timings = @timings.sort_by { |_, v| v[:timestamp] }
      
      sorted_timings.each do |phase, data|
        duration_ms = (data[:duration] * 1000).round(2)
        total_time += data[:duration]
        puts "#{phase.ljust(40)} #{duration_ms}ms"
      end
      
      puts "#{'-' * 50}"
      puts "#{'TOTAL'.ljust(40)} #{(total_time * 1000).round(2)}ms"
      puts "=================================\n"
    end
  end
end

# Initialize at require time
StartupProfiler.initialize