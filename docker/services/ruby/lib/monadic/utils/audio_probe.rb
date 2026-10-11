# frozen_string_literal: true

require 'json'
require_relative '../shell'

module Monadic
  module Utils
    # Checks an audio file before it is decoded, with ffprobe in the Python
    # container (the same container that decodes it): the format must match
    # the extension, the file must have an audio track, and it must last at
    # most MAX_SECONDS (the same limit as videos). A file that does not pass
    # raises Rejected, whose message says why.
    module AudioProbe
      MAX_SECONDS = 3000 # 50 minutes
      PROBE_TIMEOUT = 60

      # Extension => format names ffprobe reports for it.
      FORMATS = {
        '.mp3' => %w[mp3], '.mpga' => %w[mp3], '.mpeg' => %w[mp3 mpeg],
        '.m4a' => %w[mov mp4], '.mp4' => %w[mov mp4], '.aac' => %w[aac],
        '.wav' => %w[wav], '.flac' => %w[flac],
        '.ogg' => %w[ogg], '.opus' => %w[ogg],
        '.webm' => %w[webm matroska]
      }.freeze

      class Rejected < StandardError
        attr_reader :reason

        def initialize(reason, message)
          @reason = reason
          super(message)
        end
      end

      module_function

      # Returns { duration:, tracks: } for a file that passes.
      def check!(container_path)
        ext = container_path.to_s.b[/\.[A-Za-z0-9]{1,10}\z/].to_s.downcase
        formats = FORMATS[ext] or raise Rejected.new(:extension, "Audio files of type #{ext.empty? ? '(none)' : ext} are not supported. Use #{FORMATS.keys.join(', ')}.")

        argv = ['ffprobe', '-v', 'error', '-print_format', 'json',
                '-show_entries', 'format=format_name,duration:stream=codec_type', container_path]
        stdout, _stderr, status = Monadic::Shell.exec(container: :python, argv: argv, timeout: PROBE_TIMEOUT)
        info = status.success? ? parse(stdout) : nil
        raise Rejected.new(:unreadable, 'The file could not be read as audio.') unless info

        evaluate(info, formats)
      rescue Monadic::Shell::TimedOut
        raise Rejected.new(:unreadable, 'Reading the audio took too long; the file may be damaged.')
      end

      def evaluate(info, formats)
        format = info['format'] || {}
        reported = format['format_name'].to_s.split(',')
        raise Rejected.new(:format, "The file's format (#{reported.first || 'unknown'}) does not match its extension.") if (reported & formats).empty?

        tracks = Array(info['streams']).count { |s| s['codec_type'] == 'audio' }
        raise Rejected.new(:no_audio, 'The file has no audio track.') if tracks.zero?

        duration = Float(format['duration'], exception: false)
        raise Rejected.new(:duration, 'The length of the audio could not be read.') unless duration&.finite? && duration.positive?
        if duration > MAX_SECONDS
          raise Rejected.new(:too_long, "The audio is #{(duration / 60).ceil} minutes long; recordings up to #{MAX_SECONDS / 60} minutes can be transcribed.")
        end

        { duration: duration, tracks: tracks }
      end

      def parse(stdout)
        data = JSON.parse(stdout.to_s)
        data.is_a?(Hash) && data['format'].is_a?(Hash) ? data : nil
      rescue JSON::ParserError
        nil
      end
    end
  end
end
