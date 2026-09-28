# frozen_string_literal: true

module Monadic
  module Utils
    module TtsAudio
      class InvalidWav < StandardError; end

      module_function

      # Detect the container from bytes: Gemini can return PCM or a complete
      # WAV, regardless of the MIME spelling. Preserve WAV headers and rate.
      def to_wav(audio, mime_type: nil)
        if audio.start_with?("RIFF") || audio.byteslice(8, 4) == "WAVE"
          validate_wav!(audio)
          return audio
        end
        raise InvalidWav, "Empty or truncated audio" if audio.bytesize < 2 || "RIFF".start_with?(audio)

        sample_rate = mime_type.to_s[/rate\s*=\s*(\d+)/i, 1]&.to_i || 24000
        pcm_to_wav(audio, sample_rate: sample_rate)
      end

      def pcm_to_wav(pcm, sample_rate: 24000, channels: 1, bits_per_sample: 16)
        block_align = channels * bits_per_sample / 8
        ["RIFF", pcm.bytesize + 36, "WAVE", "fmt ", 16, 1, channels,
         sample_rate, sample_rate * block_align, block_align, bits_per_sample,
         "data", pcm.bytesize].pack("A4VA4A4VvvVVvvA4V") + pcm
      end

      # Walk chunks rather than assuming a 44-byte header; WAV may contain
      # metadata or an extended fmt chunk. Never rewrap a broken container.
      def validate_wav!(audio)
        unless audio.bytesize >= 12 && audio.start_with?("RIFF") && audio.byteslice(8, 4) == "WAVE"
          raise InvalidWav, "Invalid WAV signature"
        end
        limit = audio.byteslice(4, 4).unpack1("V") + 8
        raise InvalidWav, "Invalid WAV size" unless limit == audio.bytesize

        offset = 12
        format_found = false
        data_found = false
        while offset < limit
          raise InvalidWav, "Truncated WAV chunk header" if offset + 8 > limit
          id = audio.byteslice(offset, 4)
          size = audio.byteslice(offset + 4, 4).unpack1("V")
          offset += 8
          raise InvalidWav, "Truncated WAV chunk" if offset + size > limit
          if id == "fmt "
            raise InvalidWav, "Invalid WAV format chunk" if size < 16
            format, channels, rate = audio.byteslice(offset, 8).unpack("vvV")
            raise InvalidWav, "Invalid WAV format" if format.zero? || channels.zero? || rate.zero?
            format_found = true
          elsif id == "data"
            data_found = true
          end
          offset += size + (size.odd? ? 1 : 0)
        end
        unless offset == limit && format_found && data_found
          raise InvalidWav, "Incomplete WAV container"
        end
      end
    end
  end
end
