# frozen_string_literal: false

# API endpoints for frontend queries
# Model specs, environment info, capabilities, app graph data, etc.

# AI User: expose defaults per provider for UI (SSOT-based)
get "/api/ai_user_defaults" do
  content_type :json
  begin
    providers = %w[openai anthropic gemini cohere mistral deepseek grok perplexity]
    result = {}
    providers.each do |p|
      has_key = case p
        when 'openai' then !!(CONFIG['OPENAI_API_KEY'] && !CONFIG['OPENAI_API_KEY'].to_s.strip.empty?)
        when 'anthropic' then !!(CONFIG['ANTHROPIC_API_KEY'] && !CONFIG['ANTHROPIC_API_KEY'].to_s.strip.empty?)
        when 'gemini' then !!(CONFIG['GEMINI_API_KEY'] && !CONFIG['GEMINI_API_KEY'].to_s.strip.empty?)
        when 'cohere' then !!(CONFIG['COHERE_API_KEY'] && !CONFIG['COHERE_API_KEY'].to_s.strip.empty?)
        when 'mistral' then !!(CONFIG['MISTRAL_API_KEY'] && !CONFIG['MISTRAL_API_KEY'].to_s.strip.empty?)
        when 'deepseek' then !!(CONFIG['DEEPSEEK_API_KEY'] && !CONFIG['DEEPSEEK_API_KEY'].to_s.strip.empty?)
        when 'grok' then !!(CONFIG['XAI_API_KEY'] && !CONFIG['XAI_API_KEY'].to_s.strip.empty?)
        when 'perplexity' then !!(CONFIG['PERPLEXITY_API_KEY'] && !CONFIG['PERPLEXITY_API_KEY'].to_s.strip.empty?)
        else false
      end
      default_model = SystemDefaults.get_default_model(p)
      result[p] = { has_key: has_key, default_model: default_model }
    end
    { success: true, defaults: result }.to_json
  rescue StandardError => e
    status 500
    error_json(e.message)
  end
end

# Capabilities: return install-option driven availability for frontend gating
get "/api/capabilities" do
  content_type :json
  begin
    latex_enabled = !!(CONFIG && CONFIG['INSTALL_LATEX'])
    latex_available = false
    if latex_enabled
      # Try a quick health check via docker exec (python container); cache in memory for a short time
      @@latex_health ||= { ts: Time.at(0), ok: false }
      if (Time.now - @@latex_health[:ts]) > 120 # 2 minutes TTL
        ok = false
        begin
          # This command should succeed when LaTeX minimal set is installed
          ok = system("docker exec monadic-chat-python-container sh -lc 'pdflatex -version >/dev/null 2>&1'")
        rescue StandardError
          ok = false
        end
        @@latex_health = { ts: Time.now, ok: ok }
      end
      latex_available = @@latex_health[:ok]
    end

    providers = {
      openai: !!(CONFIG && CONFIG['OPENAI_API_KEY'] && !CONFIG['OPENAI_API_KEY'].to_s.strip.empty?),
      anthropic: !!(CONFIG && CONFIG['ANTHROPIC_API_KEY'] && !CONFIG['ANTHROPIC_API_KEY'].to_s.strip.empty?),
      tavily: !!(CONFIG && CONFIG['TAVILY_API_KEY'] && !CONFIG['TAVILY_API_KEY'].to_s.strip.empty?)
    }

    resp = {
      success: true,
      latex: { enabled: latex_enabled, available: latex_available },
      providers: providers,
      selenium: { enabled: true }
    }
    resp.to_json
  rescue StandardError => e
    # Be lenient: never 500 for capabilities; return defaults instead
    {
      success: false,
      error: e.message,
      latex: { enabled: false, available: false },
      providers: { openai: false, anthropic: false, tavily: false },
      selenium: { enabled: true }
    }.to_json
  end
end

# API endpoint to check environment settings
get "/api/environment" do
  content_type :json
  {
    has_tavily_key: !CONFIG["TAVILY_API_KEY"].to_s.empty?,
    max_stored_messages: (CONFIG["MAX_STORED_MESSAGES"] || "1000").to_i
  }.to_json
end

# API endpoint for dynamically loading model specifications
# Merges default model_spec.js with user's custom models.json
get "/api/models" do
  content_type :json

  begin
    default_spec_path = File.join(settings.public_folder, "js/monadic/model_spec.js")
    merged_spec = ModelSpecLoader.load_merged_spec(default_spec_path)
    JSON.generate(merged_spec)
  rescue => e
    STDERR.puts "[Model Spec Error] #{e.message}"
    Monadic::Utils::ExtraLogger.log { e.backtrace.join("\n") }
    status 500
    JSON.generate({ error: "Failed to load model specifications" })
  end
end

# Accept requests from the client to provide language codes and country names
get "/lctags" do
  languages = I18nData.languages
  countries = I18nData.countries
  content_type :json
  return { "languages" => languages, "countries" => countries }.to_json
end

# API: Deduplicated app list for batch SVG export
get "/api/apps/graph_list" do
  content_type :json
  begin
    by_display = {}
    APPS.each do |app_name, app|
      s = app.settings
      dn = (s[:display_name] || s["display_name"] || app_name).to_s
      provider = (s[:provider] || s["provider"] || s[:group] || s["group"]).to_s.downcase
      existing = by_display[dn]
      if existing.nil? || (provider == "openai" && existing[:provider] != "openai")
        by_display[dn] = { app_name: app_name, display_name: dn, provider: provider }
      end
    end
    by_display.values.sort_by { |e| e[:display_name] }.to_json
  rescue StandardError => e
    status 500
    { error: e.message }.to_json
  end
end

# API: Graph data for Workflow Viewer
get "/api/app/:name/graph" do
  content_type :json
  begin
    app_name = params[:name]
    app = defined?(APPS) && APPS[app_name]
    unless app
      status 404
      return { error: "App not found" }.to_json
    end

    s = app.settings

    prompt_text = (s[:initial_prompt] || s["initial_prompt"]).to_s
    output_types = ["text"]
    output_types << "image" if s[:image_generation] || s["image_generation"]
    output_types << "audio" if s[:auto_speech] || s["auto_speech"]

    input_types = ["text"]
    input_types << "image" if s[:image] || s["image"]
    input_types << "pdf" if s[:pdf] || s["pdf"] || s[:pdf_vector_storage] || s["pdf_vector_storage"] || s[:pdf_upload] || s["pdf_upload"]

    {
      app_name: s[:app_name] || s["app_name"],
      display_name: s[:display_name] || s["display_name"] || s[:app_name],
      icon: s[:icon] || s["icon"],
      provider: (s[:provider] || s["provider"] || s[:group] || s["group"]).to_s.downcase,
      models: s[:models] || s["models"] || [s[:model] || s["model"]].compact,
      core: {
        temperature: s[:temperature] || s["temperature"],
        reasoning_effort: s[:reasoning_effort] || s["reasoning_effort"],
        context_size: s[:context_size] || s["context_size"],
        max_tokens: s[:max_tokens] || s["max_tokens"]
      },
      system_prompt: prompt_text.length > 2000 ? prompt_text[0, 2000] + "..." : prompt_text,
      input_types: input_types,
      output_types: output_types,
      tools: wv_extract_tools(s),
      shared_tool_groups: wv_extract_shared_tool_groups(s),
      agents: wv_extract_agents(s),
      features: wv_extract_features(s),
      context_schema: (s[:context_schema] || s["context_schema"] || {})
    }.to_json
  rescue StandardError => e
    status 500
    { error: e.message }.to_json
  end
end
