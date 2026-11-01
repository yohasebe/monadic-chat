# frozen_string_literal: true

require_relative 'policy'

module Monadic
  module History
    # What the server prints (its log is the standard output and error of
    # the process) is not written for the work of a Private chat: a line
    # cannot be told to hold none of the chat. Installed on STDOUT and STDERR
    # themselves, so loggers made earlier on them and every thread are
    # covered alike.
    module PrivateOutput
      def write(*args)
        return args.sum { |a| a.to_s.bytesize } if Policy.current_work_private?

        super
      end

      module_function

      def install!(streams = [STDOUT, STDERR])
        streams.each { |io| guard(io) }
        # While $stderr is STDERR itself, Ruby writes warnings and the report
        # of a thread that died of an exception (its message can hold the
        # chat) straight to the file, past the write method. Through a copy
        # of STDERR they go by write.
        $stderr = guard(STDERR.dup.tap { |io| io.sync = true }) if streams.include?(STDERR) && $stderr.equal?(STDERR)
      end

      def guard(io)
        io.singleton_class.prepend(PrivateOutput) unless io.singleton_class.include?(PrivateOutput)
        io
      end
    end
  end
end
