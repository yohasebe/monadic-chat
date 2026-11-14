# frozen_string_literal: true

require 'json'
require 'delegate'

require_relative "../utils/http_client"
require_relative "../utils/tool_dispatch_guard"
require_relative "../utils/privacy/words"
require_relative "../workspace/request_context"
require_relative "../workspace/stopped_replies"
require_relative "../workbench/observation"
require_relative "../workbench/look"
require_relative "../workbench/look/availability"

# BaseVendorHelper
# Shared utilities for vendor helpers. Provides macros for common patterns
# (timeouts, model cache) to reduce boilerplate across providers.
# Each vendor helper can adopt these incrementally without changing behavior.

module BaseVendorHelper
  DEFAULT_MAX_RETRIES = 5
  DEFAULT_RETRY_DELAY = 1 # seconds

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    # Generates timeout class methods and instance methods for a vendor.
    # Each method reads from CONFIG with a fallback to the specified default.
    #
    # Usage:
    #   module OpenAIHelper
    #     include BaseVendorHelper
    #     define_timeouts "OPENAI", open: 20, read: 600, write: 120
    #   end
    #
    # This creates:
    #   - OpenAIHelper.open_timeout  (class method, reads CONFIG["OPENAI_OPEN_TIMEOUT"])
    #   - instance.open_timeout      (delegates to class method)
    #   - Same for read_timeout and write_timeout
    def define_timeouts(prefix, open: 10, read: 600, write: 120)
      vendor_mod = self

      { open_timeout: [open, "OPEN"], read_timeout: [read, "READ"], write_timeout: [write, "WRITE"] }.each do |method_name, (default_val, suffix)|
        config_key = "#{prefix}_#{suffix}_TIMEOUT"

        define_singleton_method(method_name) do
          defined?(CONFIG) ? (CONFIG[config_key]&.to_i || default_val) : default_val
        end

        define_method(method_name) do
          vendor_mod.public_send(method_name)
        end
      end
    end

    # Generates a clear_models_cache method for the given cache key.
    #
    # Usage:
    #   module OpenAIHelper
    #     include BaseVendorHelper
    #     define_models_cache :openai
    #   end
    #
    # This creates:
    #   - instance.clear_models_cache  (sets $MODELS[:openai] = nil)
    def define_models_cache(cache_key)
      define_method(:clear_models_cache) do
        $MODELS[cache_key] = nil
      end
    end

    # Generates list_models (instance + class) and clear_models_cache methods.
    # Replaces the boilerplate cache-check → auth → HTTP GET → parse → cache pattern.
    #
    # The block receives the parsed JSON response body and must return an Array of
    # model ID strings. If omitted, defaults to `json["data"].map { |m| m["id"] }`.
    #
    # Usage:
    #   define_model_lister :deepseek,
    #     api_key_config: "DEEPSEEK_API_KEY",
    #     endpoint_path: "/models" do |json|
    #       json["data"].sort_by { |m| m["created"] }.reverse.map { |m| m["id"] }
    #         .reject { |id| id.include?("embed") }
    #     end
    #
    # Options:
    #   cache_key        - Symbol for $MODELS cache (e.g. :deepseek)
    #   api_key_config:  - CONFIG key for the API key (e.g. "DEEPSEEK_API_KEY")
    #   endpoint_path:   - Path appended to API_ENDPOINT (e.g. "/models")
    #   endpoint:        - Alternative to endpoint_path: lambda receiving api_key,
    #                      returns the path. Authentication belongs in headers,
    #                      never in the returned URL.
    #   headers:         - Lambda receiving api_key, returns headers hash.
    #                      Default: Bearer token + Content-Type JSON.
    #   fallback_provider: - Provider name for ModelSpec fallback on failure (e.g. "anthropic").
    #                        nil means return [] on failure (original behavior for most providers).
    def define_model_lister(cache_key, api_key_config:, endpoint_path: nil, endpoint: nil, headers: nil, fallback_provider: nil, &parser)
      vendor_mod = self
      path_builder = endpoint || ->(_api_key) { endpoint_path }

      default_headers = ->(api_key) {
        { "Content-Type" => "application/json", "Authorization" => "Bearer #{api_key}" }
      }
      headers_builder = headers || default_headers

      default_parser = ->(json) {
        (json["data"] || []).map { |m| m["id"] }
      }
      model_parser = parser || default_parser

      fallback_proc = if fallback_provider
        -> {
          models = Monadic::Utils::ModelSpec.get_provider_models(fallback_provider, "chat") rescue []
          $MODELS[cache_key] = models
          models
        }
      else
        -> { [] }
      end

      # Instance method: list_models
      define_method(:list_models) do
        return $MODELS[cache_key] if $MODELS[cache_key]

        api_key = CONFIG[api_key_config]
        return fallback_proc.call if api_key.nil? || api_key.to_s.strip.empty?

        target_uri = "#{vendor_mod.const_get(:API_ENDPOINT)}#{path_builder.call(api_key)}"
        http = Monadic::Utils::HttpClient.rest.headers(headers_builder.call(api_key))

        begin
          res = http.get(target_uri)
          if res.status.success?
            json = JSON.parse(res.body)
            $MODELS[cache_key] = model_parser.call(json)
            $MODELS[cache_key]
          else
            fallback_proc.call
          end
        rescue HTTP::Error, HTTP::TimeoutError, StandardError
          fallback_proc.call
        end
      end

      # Class method: list_models (for DSL access)
      define_singleton_method(:list_models) do
        # Delegate to instance method via a temporary instance
        allocator = Class.new { include vendor_mod }
        allocator.new.list_models
      end

      # clear_models_cache (unless already defined by define_models_cache)
      unless method_defined?(:clear_models_cache)
        define_method(:clear_models_cache) do
          $MODELS[cache_key] = nil
        end
      end
    end
  end

  # Strip base64 image data from inactive session messages to prevent
  # unbounded session growth.  Keeps filenames/titles so the files can
  # still be found on disk.
  # Idempotent — safe to call on every request.
  def strip_inactive_image_data(session)
    return unless session[:messages].is_a?(Array)

    session[:messages].each do |msg|
      next if msg.nil? || msg["active"]

      # "images" array (Gemini image gen, user uploads)
      if msg["images"].is_a?(Array)
        msg["images"].each do |img|
          next unless img.is_a?(Hash)
          if img["data"].is_a?(String) && img["data"].start_with?("data:")
            img["data"] = "[stripped]"
          end
        end
      end

      # "content" array — OpenAI multimodal format
      if msg["content"].is_a?(Array)
        msg["content"].each do |part|
          next unless part.is_a?(Hash)
          if part["type"] == "image_url" && part.dig("image_url", "url")&.start_with?("data:")
            part["image_url"]["url"] = "[stripped]"
          end
        end
      end
    end
  end

  # Shows the user message of this turn on the page and adds what the
  # provider knows of it (html, language, images) to the message the server
  # recorded when it accepted the send. That message is found by the
  # request the answer runs under, not by its text: the same text may have
  # been sent before. The page gets the message's attachments with it, and
  # only once the message holds what it is shown with (an edit or delete of
  # the shown card finds it). A message added here under a request carries
  # that request, so the next call for it finds this one. Without a request
  # the last message stands in when it has the same text.
  def record_user_turn!(session, res, &block)
    content = res["content"]
    request_id = Monadic::Workspace::RequestContext.current&.request_id
    existing = if request_id
                 session[:messages].reverse_each.find { |m| m["role"] == "user" && m["request_id"] == request_id }
               else
                 last = session[:messages].last
                 last if last && last["role"] == "user" && last["text"] == content["text"]
               end
    if existing
      # What the server fixed when it accepted the send stays as it was.
      existing.merge!(content.except(*USER_TURN_SERVER_FIELDS))
      content["attachments"] = existing["attachments"] if existing["attachments"]
    else
      content["request_id"] = request_id if request_id
      session[:messages] << content
    end
    block&.call res
  end

  USER_TURN_SERVER_FIELDS = %w[request_id attachments request_snapshot].freeze

  # Whether this send has a user turn to record and show: typed text, or
  # files attached to the message of the current request with no text.
  def user_turn_to_record?(role, message, session)
    return false unless role == "user"
    return true if message.to_s != ""

    request_id = Monadic::Workspace::RequestContext.current&.request_id
    return false unless request_id

    # The server recorded this request's message when it was sent: a
    # message of attached files only (video or audio, or images and PDFs).
    Array(session[:messages]).reverse_each.any? do |m|
      m["role"] == "user" && m["request_id"] == request_id
    end
  end

  # What the model is told of the work screen with msg, when msg is the
  # user message the current request was made for (Workbench::Observation),
  # or nil. A helper adds it to its own copy of that message as it converts
  # the context (a text element of its own, or after the text), so every
  # payload it builds, a tool's continuation too, has it once.
  def observation_for(session, msg)
    Monadic::Workbench::Observation.text_for(session, msg)
  end

  # The tools of the request about to be sent, as the model is offered
  # them: look_at_workbench only where its image can reach this model
  # (Look::Availability). Recorded for ToolDispatchGuard after the filter,
  # so a call of a tool that was left out is refused.
  def offer_tools!(body, session, app, provider:, model:)
    if body["tools"]
      body["tools"] = Monadic::Workbench::Look::Availability.filter(body["tools"], session: session,
                                                                     provider: provider, model: model)
      # Nothing is left to offer: no tools and no choice among them.
      if body["tools"].is_a?(Array) && body["tools"].empty?
        body.delete("tools")
        body.delete("tool_choice")
      end
    end
    Monadic::Utils::ToolDispatchGuard.record!(session, app, body["tools"])
  end

  # A tool's result that is a look (Look::Result) answers tool_call_id: its
  # image goes after that call's result in each request of the reply.
  def bind_workbench_look(function_return, tool_call_id)
    return unless function_return.is_a?(Monadic::Workbench::Look::Result)

    ledger = workbench_look_ledger
    ledger&.bind(function_return.observation_id, tool_call_id)
  end

  # The request's looks (Look::Ledger), made at any epoch: a request
  # being built or sent after a Reset still names what it holds, and its
  # post refuses it (post_with_workbench_looks).
  def workbench_look_ledger
    request = Monadic::Workspace::RequestContext.current
    request && Monadic::Workbench::Look::Ledger.of_request(request.chat_id, request.request_id)
  end

  # messages (a request's copy) with, after each run of tool results, one
  # user message holding the images of the looks those results answer, and
  # after the last run one holding the looks whose results are not in
  # messages (a helper that sends only the last round's results); the
  # block makes such a message in the provider's shape from the
  # observations (workbench_look_parts). tool_id gives a message's tool
  # call id, or nil for any other message. The request then holds every
  # look it names (workbench_looks_prepared).
  def with_workbench_looks(messages, session, tool_id:)
    ledger = workbench_look_ledger
    return messages unless ledger

    out = []
    run = []
    all = []
    flush = lambda do
      looks = ledger.images_for(run)
      out << yield(looks) if looks.any?
      run = []
    end
    messages.each do |message|
      id = tool_id.call(message)
      flush.call if id.nil? && run.any?
      out << message
      if id
        run << id.to_s
        all << id.to_s
      end
    end
    flush.call if run.any?
    left = ledger.left_out(all)
    out << yield(left.map { |look| EarlierLook.new(look) }) if left.any?
    workbench_looks_prepared(ledger.answering(all) + left)
    out
  end

  # The looks with an image that answer tool_call_ids, to be placed in the
  # request being built.
  def workbench_looks_to_place(session, tool_call_ids)
    ledger = workbench_look_ledger
    ledger && tool_call_ids.any? ? ledger.images_for(tool_call_ids) : []
  end

  # The request being built holds looks (their text results, their
  # images): each post of the request from now on is checked with them and
  # settles them (post_with_workbench_looks). This thread keeps the ledger
  # for those posts.
  def workbench_looks_prepared(looks)
    ledger = workbench_look_ledger
    return unless ledger

    ledger.prepare(looks.map(&:id).uniq)
    Monadic::Workbench::Look::Ledger.hold_here(ledger)
  end

  # A look whose result the request being built does not hold (an
  # earlier round's, left out by a helper that sends only the last
  # round's results): its message gives the result too.
  class EarlierLook < SimpleDelegator
    def earlier?
      true
    end
  end

  # What a request holds of a look in a message of its own: the caption
  # and the image, and for a look whose result the request does not hold
  # (EarlierLook) its result as text, also with an image when the look
  # read text too (a PDF's page). All of it passed the chat's Privacy
  # Filter when the look was made.
  def workbench_look_parts(look)
    earlier = look.respond_to?(:earlier?) && look.earlier?
    result = "A result of #{Monadic::Workbench::Look::TOOL} from an earlier step of this reply: #{look.result}"
    if look.image
      text = look.caption.to_s
      text += "\n#{result}" if earlier && look.text_chars.to_i.positive?
      return { text: text, image: look.image }
    end

    { text: result, image: nil }
  end

  # Posts one request (the block: one HTTP post of body) after checking
  # the looks the request holds: every look a helper put in a request of
  # this reply (Ledger#held), not what the body's text names (a Privacy
  # Filter may have masked that), so that a copy of a body, a retry or a
  # body sent again is checked each time it is posted: the looks were not
  # let go, the session is still in the chat of the request, at its epoch,
  # not Private, and the model takes images when one is held. Otherwise
  # nothing is sent (Look::Withheld) and they are unsent. Then how far they
  # went is recorded (Look::Attempt).
  def post_with_workbench_looks(session, provider:, model:, &)
    ledger = workbench_look_ledger || workbench_look_ledger_held_here
    ids = ledger ? ledger.held : []
    return yield if ids.empty?

    Monadic::Workbench::Look::Attempt.new(ledger, ids).send!(session, provider: provider, model: model, &)
  end

  # The ledger this thread kept for the request (one that was let go
  # since), or nil.
  def workbench_look_ledger_held_here
    request = Monadic::Workspace::RequestContext.current
    request && Monadic::Workbench::Look::Ledger.held_here(request.chat_id, request.request_id)
  end

  # value as a log may show it: what a look of the work screen read is
  # named, not written. Found by its shape, so that it is named in a later
  # request too: a tool result of a look (it says "status":"looked"), and
  # an image's data (a data URL, or the base64 data of Claude's, Gemini's
  # and Ollama's image parts). Anything else is left as it is.
  LOOK_RESULT = /\\?"status\\?"\s*:\s*\\?"looked\\?"/
  IMAGE_DATA_URL = %r{data:image/[a-z0-9.+-]+;base64,[A-Za-z0-9+/=]+}i
  IMAGE_DATA_KEYS = %w[data images].freeze

  def workbench_loggable(value, key = nil)
    case value
    when Monadic::Workbench::Look::Result
      "[#{Monadic::Workbench::Look::TOOL} result #{value.observation_id}]"
    when String
      if value.match?(LOOK_RESULT)
        id = value[Monadic::Workbench::Look::Ledger::ID]
        "[#{Monadic::Workbench::Look::TOOL} result #{id}]"
      elsif IMAGE_DATA_KEYS.include?(key.to_s) && value.length >= 64 && value.match?(%r{\A[A-Za-z0-9+/=\s]+\z})
        "[image data, #{value.length} characters]"
      else
        value.gsub(IMAGE_DATA_URL) { |url| "[image data URL, #{url.length} characters]" }
      end
    when Hash then value.to_h { |k, v| [k, workbench_loggable(v, k)] }
    when Array then value.map { |v| workbench_loggable(v, key) }
    else value
    end
  end

  # A tool result's call id in the Chat Completions shape (role "tool"),
  # or nil for any other message.
  def chat_tool_call_id(message)
    role = message[:role] || message["role"]
    role.to_s == "tool" ? (message[:tool_call_id] || message["tool_call_id"]) : nil
  end

  # A user message, in the Chat Completions shape, of looks
  # (workbench_look_parts): each image after the text that says which
  # observation it is.
  def chat_look_message(looks)
    { "role" => "user",
      "content" => looks.flat_map do |look|
        parts = workbench_look_parts(look)
        [{ "type" => "text", "text" => parts[:text] },
         (parts[:image] && { "type" => "image_url", "image_url" => { "url" => parts[:image].data_url } })].compact
      end }
  end

  # The messages as the model reads them: a user message's attachments are
  # described after its text. The described messages are copies; the
  # session keeps what the user typed. Helpers call it on the finished
  # context before converting it, so the chat's words are hidden there too.
  def model_facing_context(context)
    context.map { |msg| model_facing_message(msg) }
  end

  def model_facing_message(msg)
    return msg unless msg.is_a?(Hash) && msg["role"] == "user"

    described = model_facing_attachments(msg)
    return described unless Monadic::Workspace::StoppedReplies.note_for(msg)

    # A message whose reply was stopped says so after all of it.
    described.merge("text" => Monadic::Workspace::StoppedReplies.with_note(msg, described["text"]))
  end

  def model_facing_attachments(msg)
    text = msg["text"].to_s
    lines = Array(msg["attachments"]).filter_map do |ref|
      next unless ref.is_a?(Hash)

      id = model_facing_value(ref["attachment_id"], 64)
      # A message recorded with the line in its text already (sent while the
      # page still added the lines).
      next if id.empty? || text.match?(/^Attached (?:video|audio): .+ \(attachment_id: #{Regexp.escape(id)}\)$/)

      kind = ref["purpose"] == "audio" ? "audio" : "video"
      name = model_facing_value(ref["display_name"], 200)
      "Attached #{kind}: #{name.empty? ? "file" : name} (attachment_id: #{id})"
    end
    return msg if lines.empty?

    msg.merge("text" => [text, lines.join("\n")].reject(&:empty?).join("\n\n"))
  end

  # One line of plain text: no control or format characters, no line breaks.
  def model_facing_value(value, limit)
    value.to_s.scrub("?").gsub(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/, " ").squeeze(" ").strip[0, limit]
  end

  # Substitution Pipeline integration (Vocabulary provider only).
  #
  # Vocabulary lets the user and assistant share `${TOKEN}` variables (e.g.
  # ${SHARED} for the synced data folder). The default tokens
  # (Vocabulary::DEFAULT_TOKENS) are on for every app; `vocabulary do; use ...; end`
  # adds tokens and `vocabulary false` turns it off.
  #
  # @return [Monadic::Substitution::Pipeline, nil] nil when the app exposes no
  #   vocabulary tokens (the common case).
  def substitution_pipeline_for(session, app_settings)
    require_relative '../substitution/vocabulary'
    # Default-on policy: ${SHARED} is available to every app unless it opts out
    # with `vocabulary false`. Vocabulary.build_pipeline is the single source of
    # truth for both token selection (shared with the system-prompt injector)
    # and pipeline construction (shared with the streaming handler attach site).
    Monadic::Substitution::Vocabulary.build_pipeline(session, app_settings)
  end

  # Expand owned `${TOKEN}`s in a tool-call argument structure just before the
  # tool runs, so tools operate on real (mode-aware) paths. Deep over
  # Hash/Array/String; non-string values (incl. the injected :session) pass
  # through. Non-fatal: Vocabulary is :open, so the Pipeline swallows provider
  # errors and returns the value-so-far. No-op (returns args) when the app has
  # no vocabulary.
  def expand_tool_args_for_vocabulary(args, session, app_settings)
    pipeline = substitution_pipeline_for(session, app_settings)
    return args unless pipeline
    pipeline.process_tool_invoke(nil, args)
  end

  # Replies made from what tools gave, or put together from parts each put
  # back already: in a chat with a word table, shown as they are
  # (Privacy::Words.as_is).
  def replies_as_is(replies)
    Monadic::Utils::Privacy::Words.as_is(replies)
  end

  # A reply's text and the text a model wrote before it in an earlier
  # request of the turn, each put back with the snapshot of the request it
  # came from, joined: the reply is then shown as it is.
  def join_put_back(earlier, reply, text, separator: "\n\n")
    words = Monadic::Utils::Privacy::Words
    joined = words.put_back(earlier) + separator + words.restore_reply(reply, text)
    replies_as_is(reply)
    joined
  end

  # A tool call's arguments as the tool is given them: owned `${TOKEN}`s
  # expanded, then, in a chat with a word table, the chat's words put back
  # in the places the tool reads (Privacy::Words.tool_arguments); every
  # other argument stays as the model wrote it.
  def tool_arguments_given(function_name, args, session, app_settings)
    Monadic::Utils::Privacy::Words.tool_arguments(function_name, expand_tool_args_for_vocabulary(args, session, app_settings))
  end

  # Decorate owned `${TOKEN}`s in finalized display text (keeps the symbol,
  # wraps it in <code> with a hover title of the resolved value). Display-only —
  # never apply to the TTS buffer.
  def decorate_response_text(text, session, app_settings)
    return text unless text.is_a?(String) && !text.empty?
    pipeline = substitution_pipeline_for(session, app_settings)
    return text unless pipeline
    pipeline.process_output(text)
  end

  # A chat that hides its words with a word table (Privacy::Words): the
  # conversation of an OpenAI-shaped request (body["messages"], or
  # body["input"] of the Responses API) changed with one snapshot of the
  # table, made again once if the table changed meanwhile, then the whole
  # body checked. What the user and the app wrote, and replies as the chat
  # keeps them (put back), are raw text. What a model wrote in a round of
  # tool calls (an assistant message with tool_calls, or a Responses item
  # of type "message"; the stored conversation has neither) and the tool
  # calls themselves are the model's; a tool's result is data. System and developer messages, and
  # attachments, are left as they are (a word in them stops the request).
  # A vendor whose conversation has another shape gives its own keys and
  # the method that changes one of its messages (item).
  # [table, snapshot] for Words.sending, or nil for a chat without a table.
  def hide_words_in_request!(body, session, keys: %w[messages input], item: method(:hide_words_in_item))
    privacy = Monadic::Utils::Privacy
    table = privacy::Words.table(session)
    return nil unless table

    original = keys.select { |key| body[key].is_a?(Array) }.to_h { |key| [key, body[key]] }
    2.times do
      snapshot = table.snapshot
      budget = privacy::WordTable::Budget.new
      hidden = original.transform_values { |items| items.map { |entry| item.call(entry, snapshot, budget) } }
      next unless table.revision == snapshot.revision

      body.merge!(hidden)
      privacy::Outbound.check_no_marked_words!(session, body)
      privacy::Words.sent_with(snapshot)
      return [table, snapshot]
    end
    raise privacy::Outbound::Refused, 'the words to hide kept changing; nothing was sent'
  end

  # One message or item of an OpenAI-shaped conversation, as sent.
  def hide_words_in_item(item, snapshot, budget)
    return item unless item.is_a?(Hash)

    key = ->(name) { item.key?(name.to_sym) ? name.to_sym : name }
    role = (item[:role] || item["role"]).to_s
    type = (item[:type] || item["type"]).to_s
    case type
    when "function_call"
      return item.merge(key.("arguments") => snapshot.data(item[key.("arguments")], origin: :model, budget: budget))
    when "function_call_output"
      return item.merge(key.("output") => snapshot.data(item[key.("output")], budget: budget))
    when "message"
      return item unless role == "assistant"

      return item.merge(key.("content") => hide_words_in_content(item[key.("content")], snapshot, budget, :model))
    end
    case role
    when "tool"
      item.merge(key.("content") => snapshot.data(item[key.("content")], budget: budget))
    when "user", "assistant"
      calls = item[key.("tool_calls")]
      origin = role == "assistant" && calls.is_a?(Array) ? :model : :raw
      out = item.merge(key.("content") => hide_words_in_content(item[key.("content")], snapshot, budget, origin))
      # A model's reasoning, kept as the model wrote it (DeepSeek's).
      reasoning = item[key.("reasoning_content")]
      out[key.("reasoning_content")] = snapshot.from_model(reasoning, budget) if reasoning.is_a?(String)
      if calls.is_a?(Array)
        out[key.("tool_calls")] = calls.map do |call|
          function = call.is_a?(Hash) ? (call[:function] || call["function"]) : nil
          next call unless function.is_a?(Hash)

          fkey = function.key?(:arguments) ? :arguments : "arguments"
          call.merge((call.key?(:function) ? :function : "function") =>
                       function.merge(fkey => snapshot.data(function[fkey], origin: :model, budget: budget)))
        end
      end
      out
    else
      item
    end
  end

  # A message's content: a string, or parts whose text parts are changed
  # (images and files are left as they are). origin: :raw or :model. A
  # thinking part (Mistral's) holds text parts of the model's reasoning,
  # kept as the model wrote it.
  def hide_words_in_content(content, snapshot, budget, origin = :raw)
    change = ->(text) { origin == :model ? snapshot.from_model(text, budget) : snapshot.raw(text, budget) }
    return change.(content) if content.is_a?(String)
    return content unless content.is_a?(Array)

    content.map do |part|
      if part.is_a?(Hash) && (part[:type] || part["type"]).to_s == "thinking"
        thinking_key = part.key?(:thinking) ? :thinking : "thinking"
        next part unless part[thinking_key].is_a?(Array)

        next part.merge(thinking_key => hide_words_in_content(part[thinking_key], snapshot, budget, :model))
      end
      next part unless part.is_a?(Hash) && %w[text input_text output_text].include?((part[:type] || part["type"]).to_s)

      text_key = part.key?(:text) ? :text : "text"
      part[text_key].is_a?(String) ? part.merge(text_key => change.(part[text_key])) : part
    end
  end

  # Shared non-streaming POST with retries. Mirrors the inline retry loop
  # vendor helpers use for plain JSON requests: POST, stop as soon as an
  # HTTP-success response arrives, otherwise sleep and try again, and hand
  # the last response (or nil) back to the caller for status handling.
  #
  # Timeouts come from the helper's define_timeouts methods. rescue_errors
  # controls which exceptions count as "retry" (default: none — exceptions
  # propagate, matching the majority of call sites). Pass e.g.
  # [HTTP::Error, HTTP::TimeoutError] where the original loop swallowed them.
  # looks: { session:, provider:, model: } when the body may hold looks of
  # the work screen: each post of it is checked (post_with_workbench_looks).
  def post_json_with_retries(http, target_uri, body, max_retries:, retry_delay:, rescue_errors: [], looks: nil)
    response = nil
    max_retries.times do
      begin
        post = -> { http.timeout(connect: open_timeout, write: write_timeout, read: read_timeout).post(target_uri, json: body) }
        response = if looks
                     post_with_workbench_looks(looks[:session], provider: looks[:provider], model: looks[:model], &post)
                   else
                     post.call
                   end
        break if response && response.status && response.status.success?
      rescue Monadic::Utils::Privacy::Outbound::Refused, Monadic::Workbench::Look::Withheld
        raise # nothing was sent, and trying again would not change that
      rescue *rescue_errors
        # Transient request failure — retry after the delay below.
      end
      sleep retry_delay
    end
    response
  end
end
