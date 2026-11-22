# frozen_string_literal: true

require 'json'
require 'securerandom'
require_relative '../shell'

module Monadic
  module Workbench
    # The text of pages of a PDF on the work screen, for a look: the bytes
    # the server checked are given to pdf2txt.py in the Python container on
    # its stdin (never a path), and its pages come back as JSON lines. The
    # container is not started for it: without it there is no text.
    #
    # At most SLOTS run at once. A run that was stopped holds its slot
    # until what it started in the container is known to be gone; one that
    # could not be told so is checked again when a slot is next asked for.
    module PdfText
      SCRIPT = '/monadic/scripts/converters/pdf2txt.py'
      SLOTS = 2
      QUEUE = 8
      # Seconds a run may take, and its memory (the Python process's
      # address space), at most.
      RUN = 15
      MEMORY_MB = 768
      # The exit status of the watchdog (timeout) in the container when the
      # run was out of time; it sends TERM, then KILL GRACE seconds after.
      WATCHDOG = 124
      GRACE = 2
      STDOUT_LIMIT = 1024 * 1024
      STDERR_LIMIT = 16 * 1024
      # Characters of text at most in all the pages given.
      CHARS = 64_000

      class Unavailable < StandardError
        attr_reader :reason

        def initialize(reason, message)
          @reason = reason
          super(message)
        end
      end

      # pages: [{ page:, text:, cut: }] in order; total_pages: the PDF's;
      # stopped_at: the first page not given (nil when every page asked for
      # was given), because the characters ran out or, timed_out, because
      # the time did.
      Pages = Struct.new(:pages, :total_pages, :stopped_at, :timed_out, keyword_init: true)

      @running = 0
      @unconfirmed = {}
      # Unconfirmed runs being checked now (by one caller each).
      @checking = {}
      @waiting = 0
      @lock = Mutex.new
      @freed = ConditionVariable.new

      class << self
        # The text of pages first..last (last stops at the PDF's last page)
        # of the PDF bytes, at most chars characters, before deadline
        # (monotonic seconds; a run takes RUN at most). Raises Unavailable.
        def extract(bytes, first:, last:, deadline:, chars: CHARS)
          slot = {}
          release = lambda do |gone|
            Thread.handle_interrupt(Object => :never) do
              next if slot[:released]

              slot[:released] = true
              finish(slot[:run_id], gone)
            end
          end
          acquire(deadline, slot)
          run_id = slot[:run_id]
          run_until = [deadline, clock + RUN].min
          result = Shell.exec_stream(
            container: :python, run_id: run_id, stdin: bytes, deadline: run_until,
            stdout_limit: STDOUT_LIMIT, stderr_limit: STDERR_LIMIT, stopped: release,
            argv: ['timeout', '-k', GRACE.to_s, RUN.to_s, 'python3', SCRIPT, '--stdin', '--first-page', first.to_s,
                   '--last-page', last.to_s, '--max-chars', chars.to_s, '--max-memory-mb', MEMORY_MB.to_s]
          )
          parse(result, first: first, last: last, chars: chars)
        ensure
          # Not told how the run ended (the thread was stopped before it
          # started, or exec_stream did not say): its slot waits to be
          # checked.
          release.call(false) if slot[:run_id]
        end

        def reset!
          @lock.synchronize do
            @running = 0
            @unconfirmed.clear
            @checking.clear
            @waiting = 0
          end
        end

        def busy
          @lock.synchronize { [@running, @unconfirmed.size] }
        end

        private

        def clock
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        # A slot, waited for until deadline: its run's id is put in slot
        # as the slot is taken (not stopped in between). Runs not known to
        # be gone are checked again first, as time allows. Nothing is
        # started past deadline.
        def acquire(deadline, slot)
          raise Unavailable.new('busy', 'no time is left to read the PDF text') unless deadline > clock

          check_unconfirmed(deadline)
          @lock.synchronize do
            raise Unavailable.new('busy', 'too many PDFs are being read now') if @waiting >= QUEUE

            @waiting += 1
            begin
              while @running + @unconfirmed.size >= SLOTS
                left = deadline - clock
                raise Unavailable.new('busy', 'the PDF text could not be read in time') unless left.positive?

                @freed.wait(@lock, left)
              end
              raise Unavailable.new('busy', 'no time is left to read the PDF text') unless deadline > clock

              Thread.handle_interrupt(Object => :never) do
                @running += 1
                slot[:run_id] = SecureRandom.hex(16)
              end
            ensure
              @waiting -= 1
            end
          end
        end

        # A run ended: gone, its slot is free; otherwise it waits to be
        # checked again.
        def finish(run_id, gone)
          @lock.synchronize do
            @running -= 1
            @unconfirmed[run_id] = true unless gone
            @freed.broadcast
          end
        end

        # Checks the runs not known to be gone that no one else is checking,
        # while time is left before deadline; one found gone frees its slot.
        # One run is taken to check at a time, and given back however the
        # check ends (stopped included).
        def check_unconfirmed(deadline)
          tried = []
          loop do
            checked = Thread.handle_interrupt(Object => :never) do
              run_id = @lock.synchronize do
                (@unconfirmed.keys - @checking.keys - tried).first.tap { |id| @checking[id] = true if id }
              end
              next false unless run_id

              tried << run_id
              gone = false
              begin
                Thread.handle_interrupt(Object => :immediate) do
                  left = [deadline - clock, Shell::STOP_TIMEOUT].min
                  gone = left > 0.5 && Shell.stop_and_confirm(Shell.resolve_container(:python), run_id,
                                                              timeout: left)
                end
              ensure
                @lock.synchronize do
                  @checking.delete(run_id)
                  @unconfirmed.delete(run_id) if gone
                  @freed.broadcast
                end
              end
              true
            end
            break unless checked
          end
        end

        # The pages the run wrote, checked line by line: a first line with
        # the PDF's number of pages, each page in order from first, and a
        # last line saying it was done. How the run ended is decided first:
        # a run that ran out of time (the deadline here, or the watchdog in
        # the container, exit status WATCHDOG) gives the whole pages it
        # wrote before; any other failure gives nothing, whatever it wrote.
        def parse(result, first:, last:, chars:)
          raise Unavailable.new('pdf_text_unavailable', 'the PDF text was too large') if result.failure == :too_large

          timed_out = result.failure == :deadline || result.status&.exitstatus == WATCHDOG
          unless timed_out || result.status&.success?
            down = Shell.not_running?(result.stderr, Shell.resolve_container(:python))
            reason = down ? 'the Python container is not running' : 'the PDF text could not be read'
            raise Unavailable.new('pdf_text_unavailable', reason)
          end

          out = result.stdout.to_s.b
          # Out of time, the last line may be cut short (in a character too).
          out = out[0, (out.rindex("\n") || -1) + 1] if timed_out
          out.force_encoding(Encoding::UTF_8)
          raise JSON::ParserError unless out.valid_encoding?

          lines = out.split("\n").map { |line| JSON.parse(line) }
          raise Unavailable.new('pdf_text_unavailable', 'reading the PDF text took too long') if timed_out && lines.empty?

          header = lines.shift
          raise JSON::ParserError unless header.is_a?(Hash) && header.keys == ['total_pages']

          total = header['total_pages']
          raise JSON::ParserError unless total.is_a?(Integer) && total >= first

          done = lines.last.is_a?(Hash) && lines.last.key?('done') ? lines.pop : nil
          raise JSON::ParserError if done.nil? && !timed_out

          pages = checked_pages(lines, first: first, upto: [last, total].min, chars: chars)
          if done
            stopped_at = checked_done(done, total, first: first, last: last)
            expected = (first..(stopped_at ? stopped_at - 1 : [last, total].min)).to_a
            raise JSON::ParserError unless pages.map { |p| p[:page] } == expected

            return Pages.new(pages: pages, total_pages: total, stopped_at: stopped_at, timed_out: false)
          end
          partial(pages, total, last: last)
        rescue JSON::ParserError, TypeError
          raise Unavailable.new('pdf_text_unavailable', 'the PDF text came back broken')
        end

        # Pages first.. in order, none past upto, at most chars characters,
        # only the last one cut.
        def checked_pages(lines, first:, upto:, chars:)
          raise JSON::ParserError unless lines.all? { |p| p.is_a?(Hash) && p.keys.sort == %w[cut page text] }
          raise JSON::ParserError unless lines.all? { |p| p['page'].is_a?(Integer) }
          raise JSON::ParserError unless lines.map { |p| p['page'] } == (first...(first + lines.size)).to_a
          raise JSON::ParserError if lines.any? && lines.last['page'] > upto
          raise JSON::ParserError unless lines.all? { |p| p['text'].is_a?(String) && [true, false].include?(p['cut']) }
          raise JSON::ParserError if lines.sum { |p| p['text'].length } > chars
          # Only the last page given can be cut, and the characters ran out
          # there: no page is given after a cut one, and none stops after it.
          raise JSON::ParserError if lines[0...-1].any? { |p| p['cut'] }

          lines.map { |p| { page: p['page'], text: p['text'], cut: p['cut'] } }
        end

        def checked_done(done, total, first:, last:)
          stopped_at = done['stopped_at']
          unless done.keys.sort == %w[done stopped_at total_pages] && done['done'] == true && done['total_pages'] == total &&
                 (stopped_at.nil? || (stopped_at.is_a?(Integer) && stopped_at.between?(first, [last, total].min)))
            raise JSON::ParserError
          end

          stopped_at
        end

        # The pages a run out of time wrote: none is no text; up to the last
        # page asked for, or up to a page the characters ran out in, is what
        # a whole run gives; otherwise the text stops at the next page.
        def partial(pages, total, last:)
          raise Unavailable.new('pdf_text_unavailable', 'reading the PDF text took too long') if pages.empty?

          upto = [last, total].min
          after = pages.last[:page] + 1
          return Pages.new(pages: pages, total_pages: total, stopped_at: nil, timed_out: false) if after > upto
          if pages.last[:cut]
            return Pages.new(pages: pages, total_pages: total, stopped_at: after, timed_out: false)
          end

          Pages.new(pages: pages, total_pages: total, stopped_at: after, timed_out: true)
        end
      end
    end
  end
end
