# frozen_string_literal: true

require 'json'
require 'base64'

require_relative 'corpus'

module SttNoiseBenchmark
  # Transcription back-ends under test.
  #
  # Each engine takes PCM samples and returns a transcript string (or raises).
  # The engines deliberately differ in transport — that difference is part of
  # what is being measured, since a REST batch endpoint and a realtime socket
  # can behave very differently on the same noisy audio.
  module Engines
    # Every engine answers #name, #native_rate and #transcribe(samples, rate).
    class Base
      attr_reader :name

      def initialize(name:)
        @name = name
      end

      # Rate the engine wants its audio at. The corpus is resampled per engine
      # rather than once globally, because OpenAI Realtime rejects anything
      # below 24000 while the REST endpoints accept the source rate.
      def native_rate
        24_000
      end

      def transcribe(_samples, _rate)
        raise NotImplementedError
      end
    end

    # Batch REST transcription through the application's own STT path.
    #
    # Reusing `InteractionUtils#stt_api_request` rather than re-implementing
    # each vendor's upload means this engine measures the code that actually
    # ships — a benchmark against a private reimplementation would drift away
    # from the product without anyone noticing.
    class Rest < Base
      include InteractionUtils

      def initialize(name:, model:, lang: 'en', rate: 16_000)
        super(name: name)
        @model = model
        @lang = lang
        @rate = rate
      end

      def native_rate
        @rate
      end

      def transcribe(samples, rate)
        wav = Corpus.wav_bytes(samples, rate)
        result = stt_api_request(wav, 'wav', @lang, @model)

        raise "#{@model}: #{result['content']}" if result.is_a?(Hash) && result['type'] == 'error'

        (result.is_a?(Hash) ? result['text'] : result).to_s
      end
    end

    # OpenAI Realtime transcription over a WebSocket.
    #
    # Mirrors lib/monadic/utils/websocket/audio_stream_handler.rb, including
    # the two constraints that cost the most time to find:
    #
    #   * ALPN must be forced to http/1.1 — the upgrade returns 400/405 over
    #     HTTP/2.
    #   * Audio must be held back until `session.updated` arrives. Events are
    #     processed in receive order, so anything appended earlier attaches to
    #     the not-yet-configured session and the commit comes back empty.
    #
    # The GA endpoint also rejects the old `openai-beta: realtime=v1` header,
    # so no beta header is sent.
    class OpenaiRealtime < Base
      URL = 'wss://api.openai.com/v1/realtime?intent=transcription'
      APPEND_CHUNK_BYTES = 32_000 # ~0.66s of 24kHz PCM16 per frame

      def initialize(name:, model: 'gpt-realtime-whisper', lang: 'en', timeout: 60)
        super(name: name)
        @model = model
        @lang = lang
        @timeout = timeout
      end

      def transcribe(samples, rate)
        require 'async'
        require 'async/http/endpoint'
        require 'async/websocket/client'

        api_key = ENV['OPENAI_API_KEY'] || (defined?(CONFIG) && CONFIG['OPENAI_API_KEY'])
        raise 'OPENAI_API_KEY not set' if api_key.nil? || api_key.empty?

        transcript = nil
        Sync do
          endpoint = Async::HTTP::Endpoint.parse(URL, alpn_protocols: ['http/1.1'])
          Async::WebSocket::Client.connect(endpoint, headers: { 'Authorization' => "Bearer #{api_key}" }) do |conn|
            conn.write(session_update_payload(rate).to_json)
            conn.flush

            wait_for(conn, 'session.updated')
            append_audio(conn, samples)
            conn.write({ type: 'input_audio_buffer.commit' }.to_json)
            conn.flush

            transcript = collect_transcript(conn)
          end
        end
        transcript.to_s
      end

      private

      def session_update_payload(rate)
        audio_input = {
          format: { type: 'audio/pcm', rate: rate },
          transcription: { model: @model },
          noise_reduction: { type: 'near_field' }
        }
        audio_input[:transcription][:language] = @lang if @lang

        # gpt-realtime-whisper rejects any turn_detection value; the
        # gpt-4o-transcribe family defaults to server VAD that would
        # auto-commit on every pause, so it needs an explicit null.
        audio_input[:turn_detection] = nil unless @model.to_s.start_with?('gpt-realtime-whisper')

        { type: 'session.update', session: { type: 'transcription', audio: { input: audio_input } } }
      end

      def append_audio(conn, samples)
        bytes = samples.pack('s<*')
        offset = 0
        while offset < bytes.bytesize
          frame = bytes.byteslice(offset, APPEND_CHUNK_BYTES)
          conn.write({ type: 'input_audio_buffer.append', audio: Base64.strict_encode64(frame) }.to_json)
          conn.flush
          offset += APPEND_CHUNK_BYTES
        end
      end

      def wait_for(conn, event_type)
        deadline = now + @timeout
        while now < deadline
          payload = read_event(conn)
          next unless payload

          return payload if payload['type'] == event_type

          raise "realtime error: #{payload['error']}" if payload['type'] == 'error'
        end
        raise "timed out waiting for #{event_type}"
      end

      # Deltas are ignored: the benchmark scores the final transcript, and a
      # partial that never completes should read as "no response" rather than
      # be silently scored as if it had finished.
      def collect_transcript(conn)
        deadline = now + @timeout
        while now < deadline
          payload = read_event(conn)
          next unless payload

          case payload['type']
          when 'conversation.item.input_audio_transcription.completed'
            return payload['transcript'].to_s
          when 'error'
            raise "realtime error: #{payload['error']}"
          end
        end
        '' # no response within the timeout — a real result, not a failure
      end

      def read_event(conn)
        message = conn.read
        return nil unless message

        JSON.parse(message.respond_to?(:buffer) ? message.buffer : message.to_s)
      rescue JSON::ParserError
        nil
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    # The engine set for the reference run. Models are pinned rather than read
    # from providerDefaults on purpose: a benchmark whose subject changes when
    # the product default changes cannot be compared across months.
    #
    # `xai-stt` is the reference line — a batch REST transcriber that stayed
    # accurate in every noise condition, which is what makes the realtime
    # numbers interpretable at all. (The xAI endpoint ignores the model
    # parameter; the id only selects the route in stt_api_request.)
    def self.default_set
      [
        Rest.new(name: 'xai-stt (REST)', model: 'xai-stt'),
        Rest.new(name: 'gpt-4o-mini-transcribe (REST)', model: 'gpt-4o-mini-transcribe-2025-12-15'),
        OpenaiRealtime.new(name: 'openai realtime (WS)', model: 'gpt-realtime-whisper')
      ]
    end
  end
end
