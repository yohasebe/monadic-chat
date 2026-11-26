# frozen_string_literal: true

require 'time'

module Monadic
  module Library
    # A chat as a document to keep in the Library: its title, app, model and
    # date, then what the user and the AI said, turn by turn (a heading for
    # each, so a passage read from it names the turn). The files of a turn
    # are named, not kept; what a reply read from the Library is said under
    # it. System messages, thinking and tool records are left out.
    module ConversationRecord
      TITLE_CHARS = 60
      ROLES = { 'user' => 'User', 'assistant' => 'Assistant' }.freeze

      module_function

      # { name:, content: } for the chat's messages, or nil when no one has
      # said anything yet.
      def of(messages, app_name: nil, model: nil, at: Time.now)
        turns = Array(messages).select { |m| m.is_a?(Hash) && ROLES.key?(m['role']) && !m['text'].to_s.strip.empty? }
        return nil if turns.empty?

        title = title_of(turns)
        lines = ["# #{title}", '']
        lines << details(app_name, model, at)
        turns.each do |message|
          lines << ''
          lines << "## #{ROLES[message['role']]}"
          lines << ''
          lines << turn_text(message['text'])
          files = file_names(message)
          lines.push('', "_Files: #{files.join(', ')} (not kept in this record)_") unless files.empty?
          read = readings(message)
          lines.push('', *read.map { |r| "_Read from the Library: #{r}_" }) unless read.empty?
        end
        { name: "conversation-#{at.utc.strftime('%Y%m%d-%H%M%S')}.md", content: "#{lines.join("\n")}\n" }
      end

      # A turn's text with its own headings set below the turn's (H4 and
      # under): the Library splits a document at H1–H3, so a turn stays one
      # section. Fenced code is left as it is.
      def turn_text(text)
        fenced = false
        text.to_s.strip.lines.map do |line|
          fenced = !fenced if line.match?(/\A\s{0,3}(```|~~~)/)
          next line if fenced

          line.sub(/\A\s{0,3}(\#{1,6})(?=\s)/) { '#' * [Regexp.last_match(1).length + 3, 6].min }
        end.join
      end

      def title_of(turns)
        first = turns.find { |m| m['role'] == 'user' } || turns.first
        line = first['text'].to_s.strip.lines.first.to_s.strip.gsub(/\s+/, ' ')
        line = line.sub(/\A#+\s*/, '')
        line.length > TITLE_CHARS ? "#{line[0, TITLE_CHARS]}…" : line
      end

      def details(app_name, model, at)
        parts = []
        parts << "App: #{app_name}" unless app_name.to_s.empty?
        parts << "Model: #{model}" unless model.to_s.empty?
        parts << "Recorded: #{at.utc.iso8601}"
        "_#{parts.join(' · ')}_"
      end

      # The names of the files a turn made, showed or looked at on the work
      # screen.
      def file_names(message)
        names = []
        names.concat(Array(message['artifacts']).filter_map { |a| a['name'] if a.is_a?(Hash) })
        names.concat(Array(message['workbench_shown']).filter_map { |s| File.basename(s['path'].to_s) if s.is_a?(Hash) && s['path'] })
        names.concat(Array(message['workbench_looks']).filter_map { |l| l['name'] if l.is_a?(Hash) })
        names.map(&:to_s).reject(&:empty?).uniq
      end

      def readings(message)
        Array(message['library_readings']).filter_map do |r|
          next unless r.is_a?(Hash)

          count = Array(r['excerpts']).size
          "\"#{r['query']}\" (#{count} passage#{'s' unless count == 1})"
        end
      end
    end
  end
end
