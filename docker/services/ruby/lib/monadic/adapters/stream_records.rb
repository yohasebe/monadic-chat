# frozen_string_literal: true

require_relative '../utils/error_formatter'

# The records of a streamed reply, read whole whatever the chunks of the
# transport. A chunk can end anywhere: inside a character, inside a JSON
# object, between "\r" and "\n"; and one chunk can hold several records.
# The bytes of a line are kept until the line has arrived, and the last
# record may end without a newline.
#
# :ndjson gives each line (Ollama). :sse gives the data of each "data:" line
# with the name of the event it belongs to: the providers send one JSON
# object (or "[DONE]") per data line.
class StreamRecords
  FORMATS = %i[ndjson sse].freeze

  # The reply of a stream that reported an error inside it (the HTTP status
  # was a success): the error alone. Text that came before it is not kept as
  # an answer, and tool calls that came before it are not run.
  def self.error_reply(provider, message, &block)
    res = { "type" => "error",
            "content" => Monadic::Utils::ErrorFormatter.api_error(provider: provider, message: message.to_s) }
    block&.call res
    [res]
  end

  def initialize(format)
    raise ArgumentError, "unknown stream format: #{format.inspect}" unless FORMATS.include?(format)

    @format = format
    @buffer = String.new(encoding: Encoding::BINARY)
    @event = nil
  end

  # Gives the records this chunk completes.
  def feed(chunk, &block)
    @buffer << chunk.to_s.b
    while (newline = @buffer.index("\n"))
      read_line(@buffer.slice!(0..newline), &block)
    end
  end

  # Gives the record left after the last chunk, if one is left.
  def finish(&block)
    rest = @buffer
    @buffer = String.new(encoding: Encoding::BINARY)
    read_line(rest, &block) unless rest.empty?
  end

  private

  def read_line(bytes)
    line = bytes.force_encoding(Encoding::UTF_8)
    line = line.scrub unless line.valid_encoding?
    line = line.chomp

    if @format == :ndjson
      line = line.strip
      yield line unless line.empty?
    elsif line.empty?
      @event = nil
    elsif line.start_with?("data:")
      yield line.delete_prefix("data:").delete_prefix(" "), @event
    elsif line.start_with?("event:")
      @event = line.delete_prefix("event:").strip
    end
  end
end
