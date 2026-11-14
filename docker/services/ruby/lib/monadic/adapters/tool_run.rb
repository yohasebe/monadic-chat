# frozen_string_literal: true

require 'json'
require_relative '../utils/tool_dispatch_guard'
require_relative '../utils/progressive_tool_manager'
require_relative '../utils/error_formatter'
require_relative '../utils/tts_text_extractor'
require_relative '../workbench/caller'

# One run of a tool the model called, the same for every provider. The
# provider's helper reads the call from its API's response (name and
# arguments) and writes the result in its API's format; what lies between
# is here: the arguments as the tool takes them, the check that the tool
# was offered, the call, its failure as a result, the reply's speech, the
# count of repeated errors, the look, the HTML for the chat, the images
# for the model.
#
# Tools run one after another, where the request runs: the guard and the
# caller of the work screen belong to that place.
module ToolRun
  # value: what the tool returned (a refusal or an error's text when it did
  # not run to its end); images: the names of the images it made for the
  # model, nil without one; stop: the same error came back too often to ask
  # the model again.
  Result = Struct.new(:name, :value, :images, :stop, keyword_init: true) do
    # The result as the model is given it when its images go apart: without
    # the keys kept from the model (those that begin with "_").
    def without_private_keys
      return value unless value.is_a?(Hash)

      value.reject { |key, _| key.to_s.start_with?('_') }
    end
  end

  # Runs function_name of app with arguments (a Hash by Symbol, as the
  # provider read them; it is not changed).
  #
  # call_id: the provider's id of the call, for a look's image to follow it.
  # error_text: the result an exception becomes (the exception is given).
  # refuse: a refusal of the provider's own (a String), asked once the tool
  #   is known to have been offered and before the arguments are read; nil
  #   runs the tool.
  # amend: what the provider makes of the result before it is counted and
  #   returned (the result is given).
  # speech: the reply's text is taken from the tool that takes it
  #   (tts_target); a failure there leaves the tool's result as it is.
  def run_tool_call(app, session, function_name, arguments, call_id:, error_text:, refuse: nil, amend: nil, speech: false, &block)
    settings = APPS[app]&.settings
    given = arguments
    value = Monadic::Utils::ToolDispatchGuard.refusal(session, app, function_name) || refuse&.call
    value ||= begin
      given = tool_arguments_as_taken(app, session, function_name, arguments, settings)
      if function_name == 'request_tool'
        Monadic::Utils::ProgressiveToolManager.handle_request_tool(
          session: session, app_name: app, app_settings: settings || {}, argument_hash: given
        )
      else
        APPS[app].public_send(function_name.to_sym, **given)
      end
    rescue StandardError => e
      error_text.call(e)
    end
    if function_name == 'report_verification' && respond_to?(:send_verification_notification, true)
      send_verification_notification(session, &block)
    end
    value = amend.call(value) if amend

    speech_of(app, session, function_name, given, value) if speech
    bind_workbench_look(value, call_id)
    images = nil
    if value.is_a?(Hash)
      (session[:tool_html_fragments] ||= []) << value[:gallery_html] if value[:gallery_html]
      images = Array(value[:_image]) if value[:_image]
    end

    Result.new(name: function_name, value: value, images: images,
               stop: handle_function_error(session, value, function_name, &block))
  end

  private

  # The arguments as the tool takes them: the app's own words and the
  # chat's hidden words put back, then the session and the work screen's
  # caller from the server, whatever the model wrote in their places.
  def tool_arguments_as_taken(app, session, function_name, arguments, settings)
    given = tool_arguments_given(function_name, arguments, session, settings).dup
    method_obj = begin
      APPS[app].method(function_name.to_sym)
    rescue StandardError
      nil
    end
    given[:session] = session if method_obj&.parameters&.any? { |_type, name| name == :session }
    Monadic::Workbench::Caller.inject!(given, method_obj, session)
  end

  def speech_of(app, session, function_name, given, value)
    Monadic::Utils::TtsTextExtractor.extract_tts_text(
      app: app, function_name: function_name, argument_hash: given, session: session, function_return: value
    )
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[ToolRun] The reply's speech was not taken from #{function_name}: #{e.message}" }
  end
end
