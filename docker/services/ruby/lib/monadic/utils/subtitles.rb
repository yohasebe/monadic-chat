# frozen_string_literal: true

module Monadic
  module Utils
    # Subtitle files from a timed transcript (the document SegmentTranscriber
    # returns). One cue per transcribed segment, timed by the segment's own
    # sample positions, to the millisecond. The samples count from the first
    # video frame; a player's clock counts from the file's own zero, where a
    # video whose picture starts after its audio shows its first frame at a
    # later time (timeline_origin_ms). That time is added, so the subtitles
    # keep to the picture. A first frame before the file's zero (a negative
    # time, as WebM and MKV can have) is shown at zero, so nothing is added.
    module Subtitles
      module_function

      # SRT has no escapes; "-->" in the words would read as timing.
      def srt(result)
        cues(result).each_with_index.map do |(start, stop, text), i|
          "#{i + 1}\n#{clock(start, ',')} --> #{clock(stop, ',')}\n#{text.gsub('-->', '->')}\n"
        end.join("\n")
      end

      # WebVTT cue text has tags and character references, so the words are
      # escaped to show as said ("<b>" stays "<b>", "-->" becomes "--&gt;").
      def vtt(result)
        body = cues(result).map do |start, stop, text|
          "#{clock(start, '.')} --> #{clock(stop, '.')}\n#{vtt_escape(text)}\n"
        end
        (["WEBVTT\n"] + body).join("\n")
      end

      def vtt_escape(text)
        text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      end

      # [start_seconds, end_seconds, text] for each segment with words. A blank
      # line would end a cue early, so none is kept inside the text.
      def cues(result)
        rate = result["sample_rate_hz"].to_f
        return [] unless rate.positive?

        origin = [result["timeline_origin_ms"].to_f / 1000, 0].max
        Array(result["segments"]).filter_map do |seg|
          text = seg["text"].to_s.gsub(/\r\n?/, "\n").gsub(/\n{2,}/, "\n").strip
          next if seg["status"] != "complete" || text.empty?

          start = origin + (seg["start_sample"].to_f / rate)
          stop = origin + (seg["end_sample"].to_f / rate)
          [start, stop, text] if start >= 0 && stop > start
        end
      end

      def clock(seconds, separator)
        millis = (seconds * 1000).round
        hours, rest = millis.divmod(3_600_000)
        minutes, rest = rest.divmod(60_000)
        secs, ms = rest.divmod(1000)
        format("%02d:%02d:%02d%s%03d", hours, minutes, secs, separator, ms)
      end
    end
  end
end
