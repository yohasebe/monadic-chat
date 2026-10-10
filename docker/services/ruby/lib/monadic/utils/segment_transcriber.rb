# frozen_string_literal: true

require 'async'
require 'base64'
require 'json'

module Monadic
  module Utils
    # Transcribes the speech segments written by speech_segments.py (Python
    # container) through a Realtime transcription session, one segment at a
    # time, and returns a timed transcript whose times are the segments' own
    # sample positions on the video's clock.
    #
    # The session runs without server-side turn detection: each segment's
    # audio is appended and then committed by us, so one segment becomes one
    # item. Only one commit is ever outstanding, which is how the item that
    # `input_audio_buffer.committed` names is tied to its segment (the event
    # does not echo our commit's event_id). The next segment is sent after
    # the previous one has completed or failed.
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
          new(Async::WebSocket::Client.connect(endpoint, headers: { 'Authorization' => "Bearer #{api_key}" }))
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

      def initialize(segments:, pcm_path:, model:, connect:, segment_timeout: 90, session_timeout: 20,
                     max_attempts: 3, max_connections: 6, cancelled: -> { false }, on_progress: nil)
        @doc = segments
        @pcm_path = pcm_path
        @model = model
        @connect = connect
        @segment_timeout = segment_timeout
        @session_timeout = session_timeout
        @max_attempts = max_attempts
        @max_connections = max_connections
        @cancelled = cancelled
        @on_progress = on_progress
      end

      def run
        segments = Array(@doc['segments'])
        results = segments.to_h { |s| [s['segment_id'], { 'status' => 'pending', 'attempts' => 0 }] }
        status = nil
        connections = 0
        while status.nil?
          pending = segments.select { |s| results[s['segment_id']]['status'] == 'pending' }
          break if pending.empty?
          if @cancelled.call
            status = 'cancelled'
            break
          end
          if connections >= @max_connections
            pending.each { |s| fail_segment(results[s['segment_id']], 'connection_limit') }
            break
          end
          connections += 1
          status = transcribe_on_connection(pending, results, "conn#{format('%04d', connections)}")
        end
        document(segments, results, status)
      end

      private

      # Returns 'cancelled' to stop, or nil to go on (on this or a new connection).
      def transcribe_on_connection(pending, results, connection_id)
        conn = @connect.call
        start_session(conn)
        pending.each do |seg|
          return 'cancelled' if @cancelled.call

          result = results[seg['segment_id']]
          loop do
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
              if result['attempts'] >= @max_attempts
                fail_segment(result, e.message)
                break
              end
            rescue ProtocolError, Timeout, IOError, SystemCallError => e
              fail_segment(result, error_reason(e)) if result['attempts'] >= @max_attempts
              return nil
            end
          end
        end
        nil
      rescue ProtocolError, Timeout, IOError, SystemCallError => e
        # The session never started (or the transport failed outside a segment).
        pending.each { |s| results[s['segment_id']]['last_error'] = error_reason(e) }
        nil
      ensure
        begin
          conn&.close
        rescue StandardError
          nil
        end
      end

      def fail_segment(result, reason)
        result.merge!('status' => 'failed', 'error' => reason)
      end

      def error_reason(error)
        case error
        when Timeout then 'timeout'
        when ProtocolError then "protocol: #{error.message}"
        else 'connection'
        end
      end

      def start_session(conn)
        conn.write({ type: 'session.update', session: {
                     type: 'transcription',
                     audio: { input: { format: { type: 'audio/pcm', rate: RATE },
                                       transcription: { model: @model }, turn_detection: nil } }
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
            raise ProtocolError, "session rejected (#{event.dig('error', 'code') || 'unknown'})"
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

      def segment_audio(seg)
        start = Integer(seg['start_sample'])
        length = Integer(seg['end_sample']) - start
        raise ProtocolError, 'segment out of order' if start.negative? || length <= 0

        data = File.binread(@pcm_path, length * BYTES_PER_SAMPLE, start * BYTES_PER_SAMPLE)
        raise ProtocolError, 'audio shorter than the segment' if data.nil? || data.bytesize != length * BYTES_PER_SAMPLE

        data
      end

      def document(segments, results, status)
        out = segments.map do |seg|
          r = results[seg['segment_id']]
          seg.merge(r.slice('status', 'text', 'error', 'usage_seconds', 'accepted_attempt_id', 'provenance', 'attempts'))
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
          'status' => status, 'model' => @model,
          'detector' => @doc['detector'], 'segmentation' => @doc['segmentation'],
          'segments' => out,
          'coverage' => { 'segment_count' => segments.size,
                          'completed_segment_count' => segments.size - failed.size,
                          'unresolved_segment_ids' => failed }
        }
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
