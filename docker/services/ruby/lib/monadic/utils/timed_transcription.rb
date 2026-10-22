# frozen_string_literal: true

require 'json'
require_relative 'segment_transcriber'
require_relative 'subtitles'
require_relative 'public_copy'
require_relative 'shared_path_guard'
require_relative '../shell'
require_relative '../workspace'

module Monadic
  module Utils
    # A transcript whose lines carry the media time of the speech they hold,
    # made the same way wherever it is asked for: speech_segments.py (Python
    # container) finds the speech and cuts it into segments of at most 30
    # seconds, and each segment is transcribed on its own with the provider's
    # own speech-to-text, so the times are the segments' positions, never the
    # model's guesses. OpenAI takes the segments over a realtime transcription
    # session; Google and xAI one file request per segment, through
    # `transcribe_bytes` (WAV bytes in, text or "ERROR: ..." out), which the
    # caller supplies from its own provider's agent.
    #
    # Everything is kept in the run folder (`job`): segments.json,
    # transcript.json and the subtitle files; the subtitles also get public
    # copies the page can load. The decoded audio is removed however the run
    # ends. A run stopped while its segments are being transcribed (Reset or
    # Cancel kill the thread running it) still leaves transcript.json with the
    # segments transcribed so far, marked "stopped"; one stopped before that
    # (while the speech is still being found) leaves no transcript.
    class TimedTranscription
      SEGMENT_SCRIPT = "/monadic/scripts/converters/speech_segments.py"
      PROVIDERS = %w[openai google xai].freeze
      PCM = /\Aaudio_24k\.pcm\z/

      # input/output: paths as the Python container sees them; job: the run
      # folder record (Workspace::Jobs). cancelled: true once the chat this
      # run belongs to has ended. timeline: :video (sample 0 is the first
      # video frame, as the frames are timed) or :audio (the first sample the
      # audio track plays; audio_stream picks the track, else the default one).
      def initialize(provider:, model:, api_key:, input:, job:, output:, cancelled:, transcribe_bytes: nil,
                     api_key_name: "the API key", timeout: 900, timeline: :video, audio_stream: nil, language: nil,
                     on_attempt: nil)
        raise ArgumentError, "no timed transcription for #{provider.inspect}" unless PROVIDERS.include?(provider)
        if provider != "openai" && !transcribe_bytes.respond_to?(:call)
          raise ArgumentError, "#{provider} needs transcribe_bytes (its own speech-to-text)"
        end

        @api_key_name = api_key_name
        # Told the seconds of audio of each attempt as it is sent.
        @on_attempt = on_attempt
        @language = language
        @timeline = timeline.to_sym
        @audio_stream = audio_stream
        @provider = provider
        @model = model
        @api_key = api_key.to_s.strip
        @input = input
        @job = job
        @output = output
        @cancelled = cancelled
        @transcribe_bytes = transcribe_bytes
        @timeout = timeout
      end

      # { fallback: true } when the Python container is too old for this (the
      # caller decides what to do instead); otherwise { text:, subtitles:,
      # document: }, text being the lines to show (or what went wrong).
      def run
        _stdout, stderr, status = Monadic::Shell.exec(container: :python, argv: segmenter_argv, timeout: @timeout)
        return { fallback: true } if self.class.old_python_image?(stderr)

        segments_path = Monadic::Workspace::Jobs.outputs(@job, /\Asegments\.json\z/).first
        unless status.success? && segments_path
          detail = stderr.to_s.lines.last.to_s.strip
          return { text: "Audio transcription failed: could not find speech in the audio.#{" #{detail}" unless detail.empty?}" }
        end

        doc = JSON.parse(SharedPathGuard.read_bytes!(segments_path))
        return { text: "(The video has no audio track.)" } if doc["status"] == "absent"
        return { text: "(No speech was detected in the audio.)" } if doc["status"] == "no_speech_detected"
        return { text: "Audio transcription failed: #{@api_key_name} is not set." } if @api_key.empty?

        @transcriber = transcriber(doc, Monadic::Workspace::Jobs.outputs(@job, PCM).first)
        result = @provider == "openai" ? Sync { @transcriber.run } : @transcriber.run
        # Kept until it is saved: stopped while saving, it is saved in ensure.
        @result = result
        unless save(result)
          return { text: "Audio transcription failed: the transcript could not be saved in the run folder (#{@save_error}).",
                   document: result, saved: false }
        end
        { text: self.class.format_transcript(result), subtitles: write_subtitles(result), document: result, saved: true }
      rescue Monadic::Shell::TimedOut
        { text: "Audio transcription failed: finding speech took longer than #{@timeout / 60} minutes." }
      rescue JSON::ParserError, SystemCallError => e
        { text: "Audio transcription failed: #{e.class.name.split('::').last}" }
      ensure
        begin
          # Stopped before the transcript was saved: keep what was done, the
          # whole result when the segments were all sent, else the segments
          # transcribed so far. Not after a save that failed (it would fail
          # again, and the run already says so).
          unless @saved || @save_error
            done = @result || (@transcriber.respond_to?(:snapshot) && @transcriber.snapshot)
            save(done) if done
          end
        ensure
          remove_decoded_audio
        end
      end

      def self.old_python_image?(stderr)
        text = stderr.to_s
        text.include?("can't open file") || text.include?("No module named 'onnxruntime'") ||
          text.include?("Speech detection model not found") || text.include?("unrecognized arguments: --timeline")
      end

      # One line per segment: "[start–end] text", in whole seconds.
      def self.format_transcript(result)
        if result["status"] == "failed"
          reason = result["segments"].filter_map { |seg| seg["error"] }.first
          # A run that ran out of connections says why the connections failed.
          cause = result["segments"].filter_map { |seg| seg["last_error"] }.first
          reason = "#{reason} (last error: #{cause})" if reason && cause && cause != reason
          return "Audio transcription failed#{": #{reason}" if reason}."
        end

        rate = result["sample_rate_hz"].to_f
        shown = result["segments"].reject do |seg|
          seg["status"] == "pending" || (seg["status"] == "complete" && seg["text"].to_s.strip.empty?)
        end
        lines = shown.map do |seg|
          # Rounded outward, so the span never cuts into the speech it holds.
          span = "[#{clock((seg['start_sample'] / rate).floor)}–#{clock((seg['end_sample'] / rate).ceil)}]"
          text = seg["status"] == "complete" ? seg["text"].to_s.strip : "(transcription failed)"
          "#{span} #{text}"
        end
        case result["status"]
        when "partial" then lines << "(Some segments could not be transcribed.)"
        when "cancelled" then lines << "(Stopped because the chat changed.)"
        end
        # The lines count from the first frame; a player counts from the file's
        # zero, which differ when the picture starts later (the subtitles follow
        # the player).
        origin = Subtitles.player_offset_ms(result) / 1000
        if origin >= 1
          start = result["timebase"] == "audio_relative_samples" ? "the start of the audio track" : "the first video frame"
          lines << "(These times count from #{start}, which a player shows at " \
                   "#{clock(origin.floor)}; the subtitles follow the player's time.)"
        end
        lines.join("\n")
      end

      # MM:SS, or H:MM:SS from an hour on.
      def self.clock(seconds)
        seconds = seconds.to_i
        hours, rest = seconds.divmod(3600)
        minutes, secs = rest.divmod(60)
        hours.positive? ? format("%d:%02d:%02d", hours, minutes, secs) : format("%02d:%02d", minutes, secs)
      end

      private

      # The video way keeps the command it always had; the audio way names its
      # clock (and track), which an older script refuses (old_python_image?).
      def segmenter_argv
        argv = ["python", SEGMENT_SCRIPT, @input, @output]
        return argv unless @timeline == :audio

        argv += ["--timeline", "audio"]
        @audio_stream.nil? ? argv : argv + ["--audio-stream", @audio_stream.to_i.to_s]
      end

      def transcriber(doc, pcm_path)
        if @provider == "openai"
          api_key = @api_key
          SegmentTranscriber.new(segments: doc, pcm_path: pcm_path, model: @model, cancelled: @cancelled,
                                 language: @language, on_attempt: @on_attempt,
                                 connect: -> { SegmentTranscriber::WebSocketConnection.open(api_key) })
        else
          SegmentTranscriber::Batch.new(segments: doc, pcm_path: pcm_path, model: @model, cancelled: @cancelled,
                                        transcribe: @transcribe_bytes, on_attempt: @on_attempt)
        end
      end

      # Written new under a temporary name and put in place (SharedPathGuard,
      # never through a link), so a reader never finds a half-written
      # transcript. Returns whether it was saved.
      def save(result)
        SharedPathGuard.write_file!(File.join(@job[:path], "transcript.json"), JSON.pretty_generate(result))
        @saved = true
      rescue SharedPathGuard::InvalidPath, SystemCallError, IOError => e
        @save_error = e.class.name.split("::").last
        false
      end

      # The decoded audio (about 144 MB for 50 minutes) is only needed while
      # the segments are sent.
      def remove_decoded_audio
        Monadic::Workspace::Jobs.outputs(@job, PCM).each { |path| SharedPathGuard.delete_file!(path) }
      rescue SystemCallError, SharedPathGuard::InvalidPath, Monadic::Workspace::Jobs::Unavailable
        nil
      end

      # Subtitle files for the transcript (WebVTT for the player, SRT for
      # other programs): kept as artifacts of the run (Workspace::Artifacts),
      # with a copy in the run folder, and given public copies made from the
      # kept bytes, never from the run folder's copy. Returns { vtt:, srt: }
      # addresses, or nil when there is nothing to show.
      def write_subtitles(result)
        return nil if Subtitles.cues(result).empty?

        { vtt: Subtitles.vtt(result), srt: Subtitles.srt(result) }.to_h do |kind, body|
          # Kept first: when it cannot be kept, no copy is left in the run
          # folder and nothing is published.
          next [kind, nil] unless keep_subtitles(kind, body)

          SharedPathGuard.write_file!(File.join(@job[:path], "transcript.#{kind}"), body)
          [kind, PublicCopy.publish_bytes(body, "pub_#{@job[:job_id]}.#{kind}")]
        end.compact.then { |links| links.empty? ? nil : links }
      rescue SharedPathGuard::InvalidPath, SystemCallError, IOError
        nil
      end

      # The artifact, or nil when it could not be kept (then it is not
      # published).
      def keep_subtitles(kind, body)
        Monadic::Workspace::Artifacts.store!(job: @job, kind: "subtitle_#{kind}", body: body)
      rescue Monadic::Workspace::Ledger::Unreadable, Monadic::Workspace::Ledger::Conflict,
             Monadic::Workspace::ServerOwner::Refused, SystemCallError, IOError, KeyError, ArgumentError => e
        warn "[Workspace] Subtitles not kept: #{e.class.name.split('::').last}"
        nil
      end
    end
  end
end
