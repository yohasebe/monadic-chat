# frozen_string_literal: true

module Monadic
  # Whether the AI may search the web in a chat: the setting
  # WEB_SEARCH_IN_CHATS (Settings, Sources the AI can use; on unless
  # "false"), read when the server starts, and the app's MDSL `websearch`
  # (only an app that says `websearch true` searches). Whether a search is
  # made is the model's choice; whether the model and its provider can
  # search (a native search tool, or Tavily with its key) is each
  # adapter's.
  module WebSearchSetting
    KEY = 'WEB_SEARCH_IN_CHATS'

    module_function

    def on?
      value = defined?(CONFIG) && CONFIG.is_a?(Hash) ? CONFIG[KEY] : nil
      value.to_s.strip.downcase != 'false'
    end

    # The app's MDSL says it searches (`websearch true`).
    def app_allows?(app_name)
      return false if app_name.to_s.empty? || !defined?(APPS) || !APPS.is_a?(Hash)

      settings = APPS[app_name.to_s]&.settings
      value = settings && (settings[:websearch] || settings['websearch'])
      value == true || value.to_s == 'true'
    end

    def allowed?(app_name)
      on? && app_allows?(app_name)
    end

    # Whether a model searches at this reasoning effort: a model can say an
    # effort does not go with web search (model_spec.js feature_constraints).
    def effort_allows?(model, effort)
      return true if effort.to_s.empty?

      constraints = Monadic::Utils::ModelSpec.get_model_property(model, 'feature_constraints')
      blocked = constraints.is_a?(Hash) && constraints.dig('reasoning_effort', 'incompatible_with', 'web_search')
      !(blocked.is_a?(Array) && blocked.map(&:to_s).include?(effort.to_s))
    rescue StandardError
      true
    end
  end
end
