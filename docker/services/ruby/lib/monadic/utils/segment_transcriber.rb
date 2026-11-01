# frozen_string_literal: true

require 'async'
require 'async/semaphore'
require 'base64'
require 'json'
require_relative 'error_formatter'
require_relative 'shared_path_guard'

module Monadic
  module Utils
    # Transcribes the speech segments written by speech_segments.py (Python
    # container) through a Realtime transcription session, one segment at a
    # time, and returns a timed transcript whose times are the segments' own
    # sample positions on the video's clock.
    #
    # The session runs without server-side turn detection: each segment's
    # audio is appended and then committed by us, so one segment becomes one
    # item. On a connection only one commit is ever outstanding, which is how
    # the item that `input_audio_buffer.committed` names is tied to its
    # segment (the event does not echo our commit's event_id); the next
    # segment is sent on it after the previous one has completed or failed.
    # A few connections work at once (`concurrency`). The segments are cut
    # into that many runs of consecutive segments of about the same length of
    # audio, and each connection sends its own run in order: the model reads
    # a segment with the ones before it on the same connection as context,
    # so a connection keeps to a stretch of the recording rather than taking
    # whichever segment is next.
    #
    # The transport is injected: `connect` returns an object with
    # `write(hash)`, `read(timeout_seconds)` (a parsed event, or nil when the
    # time runs out) and `close`. A lost or confused connection is replaced
    # and the unfinished segments are sent again; a segment that keeps
    # failing is recorded as failed and the rest go on.
    class SegmentTranscriber
      RATE = 24_000
      BYTES_PER_SAMPLE = 2
      APPEND_SAMPLES = RATE / 2 # 0.5 s of audio per append event
      # The wait after a rate limit: doubled each time, at most the cap.
      RATE_LIMIT_WAIT = 2.0
      RATE_LIMIT_WAIT_CAP = 30.0
      # Session errors that no new connection would get past.
      REFUSED_CODES = %w[invalid_api_key insufficient_quota].freeze
      COMPLETED = 'conversation.item.input_audio_transcription.completed'
      FAILED = 'conversation.item.input_audio_transcription.failed'

      class ProtocolError < StandardError; end

      # The Realtime transcription endpoint over a WebSocket, for use inside
      # an Async reactor. `read` returns nil when the time runs out and raises
      # IOError when the server has closed the connection.
      class WebSocketConnection
        URL = 'wss://api.openai.com/v1/realtime?intent=transcription'

        def self.open(api_key)
          require 'async/http/endpoint'
          require 'async/websocket/client'
          endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: ['http/1.1'])
          new(connect_any(endpoint) { |address| Async::WebSocket::Client.connect(address, headers: { 'Authorization' => "Bearer #{api_key}" }) })
        rescue Async::WebSocket::ConnectionError => e
          status = e.response.respond_to?(:status) ? e.response.status : nil
          raise RateLimited, 'the connection was refused (429)' if status == 429
          raise Refused, "the connection was refused (#{status})" if [401, 403].include?(status)

          raise IOError, "the connection was refused (#{status || 'unknown'})"
        end

        # Each of the host's addresses in turn until one connects. The
        # endpoint's own connect gives up at an unreachable address (only a
        # refused one or an unreachable network moves it on), so a host with
        # no working IPv6 route would never reach the IPv4 address after it.
        def self.connect_any(endpoint)
          last_error = nil
          endpoint.each do |address|
            return yield(address)
          rescue SystemCallError => e
            last_error = e
          end
          raise last_error || IOError.new('the host has no address')
        end

        def initialize(connection)
          @connection = connection
        end

        def write(event)
          @connection.write(JSON.generate(event))
          @connection.flush
        end

        def read(timeout)
          message = Async::Task.current.with_timeout(timeout) { @connection.read }
          raise IOError, 'connection closed' if message.nil?

          JSON.parse(message.respond_to?(:buffer) ? message.buffer : message.to_s)
        rescue Async::TimeoutError
          nil
        rescue JSON::ParserError
          {}
        end

        def close
          @connection.close
        end
      end
      class Timeout < StandardError; end
      class SegmentFailed < StandardError; end
      # Too many requests: wait, then connect again.
      class RateLimited < StandardError; end
      # Refused for good (the key or the account): connecting again would be
      # refused too.
      class Refused < StandardError; end

      # What both ways of sending have in common: reading a segment's audio
      # from the PCM file and writing the timed transcript document.
      module Shared
        # The document as far as it has got, for a run stopped before it
        # returned (Reset or Cancel kill the thread running it): the segments
        # done so far, the rest still pending. nil before the run began.
        def snapshot(status = 'stopped')
          segments, results = @progress
          segments && document(segments, results, status)
        end

        private

        def segment_audio(seg)
          start = Integer(seg['start_sample'])
          length = Integer(seg['end_sample']) - start
          raise ProtocolError, 'segment out of order' if start.negative? || length <= 0

          # Read from the decoded audio as a plain file of the run folder (never
          # through a link swapped in while the segments are sent).
          data = SharedPathGuard.read_file!(@pcm_path) do |file|
            file.seek(start * BYTES_PER_SAMPLE)
            file.read(length * BYTES_PER_SAMPLE)
          end
          raise ProtocolError, 'audio shorter than the segment' if data.nil? || data.bytesize != length * BYTES_PER_SAMPLE

          data
        end

        def document(segments, results, status)
          out = segments.map do |seg|
            r = results[seg['segment_id']]
            seg.merge(r.slice('status', 'text', 'error', 'last_error', 'usage_seconds', 'accepted_attempt_id',
                              'provenance', 'attempts'))
          end
          failed = out.select { |s| s['status'] != 'complete' }.map { |s| s['segment_id'] }
          status ||= if segments.empty? then @doc['status']
                     elsif failed.empty? then 'complete'
                     elsif failed.size == segments.size then 'failed'
                     else 'partial'
                     end
          {
            'schema' => 'timed-transcript', 'schema_version' => 2,
            'timebase' => @doc['timebase'], 'sample_rate_hz' => @doc['sample_rate_hz'],
            'interval_convention' => @doc['interval_convention'],
            'timeline_origin_ms' => @doc['timeline_origin_ms'],
            # where the audio came from (an audio file: its clock, track, codec)
            **(@doc['source'] ? { 'source' => @doc['source'] } : {}),
            'status' => status, 'model' => @model,
            'detector' => @doc['detector'], 'segmentation' => @doc['segmentation'],
            'segments' => out,
            'coverage' => { 'segment_count' => segments.size,
                            'completed_segment_count' => segments.size - failed.size,
                            'unresolved_segment_ids' => failed }
          }
        end

        # Told before each attempt is sent, with the seconds of audio it sends
        # (what the caller charges for: an attempt is sent whether or not an
        # answer comes back). The caller answers false when the attempt must
        # not be sent (its budget is spent); false is returned then.
        def attempt_allowed?(seg)
          return true unless @on_attempt

          @on_attempt.call((Integer(seg['end_sample']) - Integer(seg['start_sample'])).to_f / RATE) != false
        end

        # The reason is saved in transcript.json in the chat's folder, which the
        # model can read and which travels with exports.
        def fail_segment(result, reason)
          result.merge!('status' => 'failed', 'error' => Monadic::Utils::ErrorFormatter.scrub_identifiers(reason.to_s))
        end

        def now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end

      include Shared

      def initialize(segments:, pcm_path:, model:, connect:, segment_timeout: 90, session_timeout: 20,
                     max_attempts: 3, max_connections: 10, concurrency: 4, cancelled: -> { false },
                     on_progress: nil, language: nil, on_attempt: nil)
        @on_attempt = on_attempt
        @language = language.to_s.empty? || language.to_s == 'auto' ? nil : language.to_s
        @doc = segments
        @pcm_path = pcm_path
        @model = model
        @connect = connect
        @segment_timeout = segment_timeout
        @session_timeout = session_timeout
        @max_attempts = max_attempts
        @max_connections = max_connections
        @concurrency = [concurrency.to_i, 1].max
        @cancelled = cancelled
        @on_progress = on_progress
      end

      def run
        segments = Array(@doc['segments'])
        results = segments.to_h { |s| [s['segment_id'], { 'status' => 'pending', 'attempts' => 0 }] }
        @progress = [segments, results].freeze # one assignment: snapshot sees both or neither
        @results = results
        @connections = 0
        @cancelled_run = false
        @refused = nil
        @rate_limited = 0
        @wait_until = 0.0
        # The workers are fibers of one reactor, so the counters above and
        # each worker's run of segments need no lock.
        blocks = runs_of_segments(segments, [@concurrency, segments.size].min)
        Sync { blocks.map { |block| Async { work(block) } }.each(&:wait) } unless blocks.empty?
        unless @cancelled_run
          blocks.flatten.each do |s|
            result = results[s['segment_id']]
            fail_segment(result, @refused || 'connection_limit') if result['status'] == 'pending'
          end
        end
        document(segments, results, @cancelled_run ? 'cancelled' : nil)
      end

      private

      # The segments in `count` runs of consecutive segments, each with about
      # the same length of audio.
      def runs_of_segments(segments, count)
        return [] if count.zero?

        lengths = segments.map { |s| Integer(s['end_sample']) - Integer(s['start_sample']) }
        target = lengths.sum.to_f / count
        runs = [[]]
        done = 0
        segments.each_with_index do |seg, i|
          left_after = segments.size - i - 1
          runs.last << seg
          done += lengths[i]
          runs << [] if runs.size < count && left_after >= count - runs.size && done >= target * runs.size
        end
        runs.reject(&:empty?)
      end

      # One worker: its run of segments, a connection at a time, until the
      # run is done, the chat is cancelled, the connections run out or the
      # service refuses for good.
      def work(block)
        until block.empty?
          return if @refused
          return @cancelled_run = true if @cancelled.call
          return if @connections >= @max_connections
          return @cancelled_run = true unless wait_out_rate_limit
          return if @refused # refused while this worker waited

          @connections += 1
          transcribe_on_connection(block, "conn#{format('%04d', @connections)}")
        end
      end

      # Waits until the shared wait after a rate limit is over; false when
      # the chat is cancelled meanwhile.
      def wait_out_rate_limit
        while (left = @wait_until - now).positive?
          return false if @cancelled.call

          sleep [left, 0.5].min
        end
        true
      end

      # Too many requests: every worker waits before connecting again, a
      # little longer each time (with some jitter), at most 30 seconds.
      def rate_limited!
        @rate_limited += 1
        delay = [RATE_LIMIT_WAIT * (2**(@rate_limited - 1)), RATE_LIMIT_WAIT_CAP].min * (0.75 + (rand * 0.5))
        @wait_until = [@wait_until, now + delay].max
      end

      # Sends the worker's segments on one connection until they are done or
      # the connection is lost (the segment it was sending goes back first).
      def transcribe_on_connection(block, connection_id)
        conn = @connect.call
        start_session(conn)
        until block.empty?
          if @cancelled.call
            @cancelled_run = true
            return
          end

          seg = block.first
          result = @results[seg['segment_id']]
          loop do
            if @cancelled.call # before an attempt is sent (and charged) again
              @cancelled_run = true
              return
            end

            # Another worker may have been refused meanwhile: nothing more is sent.
            return if @refused

            unless attempt_allowed?(seg)
              @refused = 'budget' # every other worker stops too
              return
            end
            result['attempts'] += 1
            attempt_id = "attempt#{format('%04d', result['attempts'])}"
            begin
              outcome = transcribe_segment(conn, seg, "#{seg['segment_id']}_#{connection_id}_#{attempt_id}")
              result.merge!('status' => 'complete', 'text' => outcome.delete(:text),
                            'usage_seconds' => outcome.delete(:usage_seconds), 'accepted_attempt_id' => attempt_id,
                            'provenance' => outcome.merge(connection_id: connection_id).transform_keys(&:to_s))
              @on_progress&.call(seg, result)
              break
            rescue SegmentFailed => e
              # The connection is still usable, so the segment is tried again on it.
              result['last_error'] = e.message
              if result['attempts'] >= @max_attempts
                fail_segment(result, e.message)
                break
              end
            rescue RateLimited, ProtocolError, Timeout, IOError, SystemCallError => e
              result['last_error'] = error_reason(e)
              rate_limited! if e.is_a?(RateLimited)
              fail_segment(result, error_reason(e)) if result['attempts'] >= @max_attempts
              block.shift unless result['status'] == 'pending' # sent again on a fresh connection otherwise
              return
            end
          end
          block.shift
        end
      rescue Refused => e
        @refused = error_reason(e)
      rescue RateLimited, ProtocolError, Timeout, IOError, SystemCallError => e
        # The session never started (or the transport failed outside a
        # segment): the segment waiting next carries the reason.
        rate_limited! if e.is_a?(RateLimited)
        @results[block.first['segment_id']]['last_error'] = error_reason(e) unless block.empty?
      ensure
        begin
          conn&.close
        rescue StandardError
          nil
        end
      end

      def error_reason(error)
        case error
        when RateLimited then 'rate_limited'
        when Refused then 'refused'
        when Timeout then 'timeout'
        when ProtocolError then "protocol: #{error.message}"
        else 'connection'
        end
      end

      def start_session(conn)
        conn.write({ type: 'session.update', session: {
                     type: 'transcription',
                     audio: { input: { format: { type: 'audio/pcm', rate: RATE },
                                       transcription: { model: @model, language: @language }.compact,
                                       turn_detection: nil } }
                   } })
        deadline = now + @session_timeout
        loop do
          event = read(conn, deadline)
          case event['type']
          when 'session.updated'
            input = event.dig('session', 'audio', 'input') || {}
            raise ProtocolError, 'server turn detection is on' unless input['turn_detection'].nil?

            return
          when 'error'
            code = event.dig('error', 'code')
            raise RateLimited, 'rate limited' if code.to_s.include?('rate_limit')
            # The key itself is refused: every other connection would be too.
            raise Refused, "session rejected (#{code})" if REFUSED_CODES.include?(code.to_s)

            raise ProtocolError, "session rejected (#{code || 'unknown'})"
          end
        end
      end

      def transcribe_segment(conn, seg, commit_event_id)
        audio = segment_audio(seg)
        raise ProtocolError, 'empty segment' if audio.empty?

        audio.bytes.each_slice(APPEND_SAMPLES * BYTES_PER_SAMPLE).each do |chunk|
          conn.write({ type: 'input_audio_buffer.append', audio: Base64.strict_encode64(chunk.pack('C*')) })
        end
        conn.write({ type: 'input_audio_buffer.commit', event_id: commit_event_id })
        await_transcript(conn, commit_event_id)
      end

      def await_transcript(conn, commit_event_id)
        deadline = now + @segment_timeout
        item_id = nil
        provenance = nil
        early = {}
        loop do
          event = read(conn, deadline)
          case event['type']
          when 'input_audio_buffer.committed'
            next if event['item_id'] == item_id # repeated event
            raise ProtocolError, 'committed without a pending commit' if item_id

            item_id = event['item_id']
            raise ProtocolError, 'committed without an item' if item_id.to_s.empty?

            provenance = { commit_event_id: commit_event_id, committed_event_id: event['event_id'],
                           item_id: item_id, previous_item_id: event['previous_item_id'] }
            event = early.delete(item_id)
            return finish(event, provenance) if event
          when COMPLETED, FAILED
            if item_id.nil? || event['item_id'] != item_id
              early[event['item_id']] = event # an item we have not been told about yet
              next
            end
            return finish(event, provenance)
          when 'input_audio_buffer.speech_started', 'input_audio_buffer.speech_stopped'
            raise ProtocolError, 'server turn detection is on'
          when 'error'
            code = event.dig('error', 'code')
            raise ProtocolError, 'commit of a segment arrived empty' if code == 'input_audio_buffer_commit_empty'
            raise RateLimited, 'rate limited' if code.to_s.include?('rate_limit')

            raise ProtocolError, "error (#{code || 'unknown'})"
          end
        end
      end

      def finish(event, provenance)
        raise SegmentFailed, "transcription failed (#{event.dig('error', 'code') || 'unknown'})" if event['type'] == FAILED

        usage = event['usage']
        seconds = usage['seconds'] if usage.is_a?(Hash) && usage['type'] == 'duration'
        provenance.merge(text: event['transcript'].to_s, usage_seconds: seconds)
      end

      def read(conn, deadline)
        loop do
          left = deadline - now
          raise Timeout, 'no reply in time' if left <= 0

          event = conn.read(left)
          raise Timeout, 'no reply in time' if event.nil?
          return event if event.is_a?(Hash) && event['type']
        end
      end


      # The same segments through a provider's file transcription instead of a
      # realtime session: each segment goes out as its own WAV request, a few
      # at a time. `transcribe` takes the WAV bytes and returns the text, or a
      # string starting with "ERROR:". The times are the segments' own, as
      # with the realtime way.
      class Batch
        include Shared

        def initialize(segments:, pcm_path:, model:, transcribe:, concurrency: 4, max_attempts: 3,
                       cancelled: -> { false }, on_attempt: nil)
          @on_attempt = on_attempt
          @doc = segments
          @pcm_path = pcm_path
          @model = model
          @transcribe = transcribe
          @concurrency = concurrency
          @max_attempts = max_attempts
          @cancelled = cancelled
        end

        def run
          segments = Array(@doc['segments'])
          results = segments.to_h { |s| [s['segment_id'], { 'status' => 'pending', 'attempts' => 0 }] }
          @progress = [segments, results].freeze # one assignment: snapshot sees both or neither
          Sync do
            semaphore = Async::Semaphore.new(@concurrency)
            segments.map { |seg| semaphore.async { transcribe_segment(seg, results[seg['segment_id']]) } }
                    .each(&:wait)
          end
          cancelled = results.values.any? { |r| r['status'] == 'pending' }
          document(segments, results, cancelled ? 'cancelled' : nil)
        end

        private

        def transcribe_segment(seg, result)
          wav = wav_bytes(segment_audio(seg))
          reason = nil
          while result['attempts'] < @max_attempts
            return if @cancelled.call

            return fail_segment(result, 'budget') unless attempt_allowed?(seg)

            result['attempts'] += 1
            text = begin
              @transcribe.call(wav).to_s
            rescue StandardError => e
              "ERROR: #{e.class.name.split('::').last}"
            end
            if text.start_with?('ERROR:')
              reason = text.delete_prefix('ERROR:').strip
              next
            end
            result.merge!('status' => 'complete', 'text' => text.strip,
                          'accepted_attempt_id' => "attempt#{format('%04d', result['attempts'])}")
            return
          end
          fail_segment(result, reason || 'transcription failed')
        rescue ProtocolError => e
          fail_segment(result, "protocol: #{e.message}")
        end

        def wav_bytes(pcm)
          header = ['RIFF', 36 + pcm.bytesize, 'WAVE', 'fmt ', 16, 1, 1, RATE, RATE * BYTES_PER_SAMPLE,
                    BYTES_PER_SAMPLE, 16, 'data', pcm.bytesize].pack('a4Va4a4VvvVVvva4V')
          header + pcm
        end
      end
    end
  end
end
