# frozen_string_literal: true

require 'monadic/library'

# Shared tool implementations for the Knowledge Base app. All variants
# (KnowledgeBaseOpenAI, KnowledgeBaseClaude, ...) include this module so
# the same tool surface works across providers.
#
# Each tool returns a String — the Monadic Chat tool-result convention.
# Errors are caught and returned with a leading ❌ so the LLM can surface
# them to the user without crashing the conversation.
module KnowledgeBaseTools
  # ─── List / inspect ────────────────────────────────────────────────────

  def list_conversations(limit: 100)
    rows = with_kb_store { |store|
      Monadic::Library::Manager.list_conversations(
        store: store, limit: limit.to_i.clamp(1, 500)
      )
    }
    return 'The Knowledge Base is empty.' if rows.empty?
    format_list(rows)
  rescue StandardError => e
    "❌ list_conversations failed: #{e.message}"
  end

  def search_library(query:, top_n: 3)
    hits = with_kb_store { |store|
      Monadic::Library::Retriever.cascade_search(
        query, store: store, top_n: top_n.to_i.clamp(1, 10)
      )
    }
    format_search_results(query, hits)
  rescue StandardError => e
    "❌ search_library failed: #{e.message}"
  end

  def get_conversation_details(conversation_id:)
    row = with_kb_store { |store|
      Monadic::Library::Manager.get_conversation_details(
        store: store, conversation_id: conversation_id
      )
    }
    return "❌ No conversation found with id #{conversation_id}." if row.nil?
    format_details(row)
  rescue StandardError => e
    "❌ get_conversation_details failed: #{e.message}"
  end

  def library_stats
    stats = with_kb_store { |store| Monadic::Library::Manager.library_stats(store: store) }
    by_scope = stats[:conversations_by_scope] || {}
    lines = ["Knowledge Base contents: #{stats[:conversations_total]} entries"]
    by_scope.sort_by { |scope, count| [scope == KB_SCOPE_GLOBAL ? 0 : 1, -count, scope] }.each do |scope, count|
      lines << "- #{kb_scope_label(scope)}: #{count}"
    end
    lines.join("\n")
  rescue StandardError => e
    "❌ library_stats failed: #{e.message}"
  end

  # ─── Mutate ────────────────────────────────────────────────────────────

  def update_conversation_scope(conversation_id:, scope:)
    scope_app = kb_resolve_scope(scope)
    with_kb_store { |store|
      Monadic::Library::Manager.update_scope_app(
        store: store, conversation_id: conversation_id, scope_app: scope_app
      )
    }
    "✓ #{conversation_id} now belongs to #{kb_scope_label(scope_app)}."
  rescue ArgumentError => e
    "❌ #{e.message}"
  rescue StandardError => e
    "❌ update_conversation_scope failed: #{e.message}"
  end

  def delete_conversation_from_library(conversation_id:)
    with_kb_store { |store|
      Monadic::Library::Manager.delete_conversation(store: store, conversation_id: conversation_id)
    }
    "✓ Conversation #{conversation_id} permanently removed from the Knowledge Base."
  rescue StandardError => e
    "❌ delete_conversation_from_library failed: #{e.message}"
  end

  # ─── Import ───────────────────────────────────────────────────────────

  def import_conversation_from_text(input:, title: nil, license: nil, scope: nil)
    scope_app = scope.to_s.strip.empty? ? KB_SCOPE_GLOBAL : kb_resolve_scope(scope)
    options = {}
    options[:title] = title unless title.to_s.empty?
    options[:license] = license unless license.to_s.empty?

    result = with_kb_store { |store|
      Monadic::Library::Manager.import_from_text(
        store: store, input: input, options: options, scope_app: scope_app
      )
    }
    counts = result[:counts]
    "✓ Imported via #{result[:importer]} as #{result[:conversation_id]} (scope: #{kb_scope_label(scope_app)})\n" \
      "  - turns: #{counts[:turns]}\n" \
      "  - summary: #{counts[:summary] == 1 ? 'created (placeholder)' : 'skipped'}"
  rescue ArgumentError => e
    "❌ #{e.message}"
  rescue StandardError => e
    "❌ import_conversation_from_text failed: #{e.message}"
  end

  # ─── Internals ─────────────────────────────────────────────────────────

  private

  KB_SCOPE_GLOBAL = 'Global'
  KB_SCOPE_PROVIDERS = %w[OpenAI Claude Gemini Grok Cohere Mistral DeepSeek Ollama].freeze

  # Turn a stored scope_app value into the label the Knowledge Base UI
  # shows: "ChatOpenAI" -> "Chat (OpenAI)", "Global" stays "Global".
  def kb_scope_label(scope_app)
    value = scope_app.to_s
    return KB_SCOPE_GLOBAL if value.empty? || value == KB_SCOPE_GLOBAL
    provider = KB_SCOPE_PROVIDERS.find { |p| value.length > p.length && value.end_with?(p) }
    return value unless provider
    base = value[0, value.length - provider.length].gsub(/([a-z0-9])([A-Z])/, '\\1 \\2')
    "#{base} (#{provider})"
  end

  # Accept "Global", an app class name ("ChatOpenAI"), or the UI label
  # ("Chat (OpenAI)") and return the value stored in scope_app. App
  # names are checked against the registered apps when they are loaded.
  def kb_resolve_scope(scope)
    value = scope.to_s.strip
    raise ArgumentError, "scope must be 'Global' or an app, such as 'Chat (OpenAI)'" if value.empty?
    return KB_SCOPE_GLOBAL if value.casecmp?(KB_SCOPE_GLOBAL)

    if (m = value.match(/\A(.+?)\s*\(([^()]+)\)\z/))
      provider = KB_SCOPE_PROVIDERS.find { |p| p.casecmp?(m[2].strip) }
      value = "#{m[1].delete(' ')}#{provider}" if provider
    end

    apps = kb_registered_app_names
    return value if apps.nil? || apps.include?(value)

    match = apps.find { |name| name.casecmp?(value) }
    return match if match

    raise ArgumentError, "No app named '#{scope}'. Use 'Global' or an app with its provider, such as 'Chat (OpenAI)'."
  end

  def kb_registered_app_names
    return nil unless defined?(::APPS) && ::APPS.respond_to?(:keys)
    ::APPS.keys.map(&:to_s)
  end

  # Yields a Library Store and ensures collections exist. Override-able
  # for tests via stubbing.
  def with_kb_store
    store = Monadic::Library::Store.new
    store.bootstrap_collections!
    yield(store)
  end

  def format_list(rows)
    lines = ["#{rows.size} conversation#{'s' if rows.size != 1} in the Knowledge Base:", '']
    rows.each_with_index do |r, i|
      title = r[:title].to_s.empty? ? '(untitled)' : r[:title]
      lines << "[#{i + 1}] #{title}"
      lines << "    id=#{r[:conversation_id]} source=#{r[:source]} language=#{r[:language]} " \
               "scope=#{kb_scope_label(r[:scope_app])} turns=#{r[:turns_count]} created_at=#{r[:created_at]}"
    end
    lines.join("\n")
  end

  def format_details(r)
    fields = [
      ['conversation_id', r[:conversation_id]],
      ['title', r[:title]],
      ['source', r[:source]],
      ['language', r[:language]],
      ['license', r[:license]],
      ['scope', kb_scope_label(r[:scope_app])],
      ['messages', r[:messages_count]],
      ['turns', r[:turns_count]],
      ['duration_seconds', r[:duration_seconds]],
      ['created_at', r[:created_at]]
    ]
    out = ['Conversation details:']
    fields.each { |k, v| out << "  #{k}: #{v}" unless v.nil? }
    out.join("\n")
  end

  def format_search_results(query, hits)
    return "No matching passages were found in the Knowledge Base for query: #{query.inspect}" if hits.empty?
    lines = ["Found #{hits.size} relevant passage#{'s' if hits.size != 1} (all entries, every scope):", '']
    hits.each_with_index do |h, i|
      title = h[:conversation_title].to_s.empty? ? '(untitled)' : h[:conversation_title]
      snippet = h[:text].to_s.gsub(/\s+/, ' ').strip
      snippet = snippet[0, 480] + (snippet.length > 480 ? '…' : '')
      lines << "[#{i + 1}] \"#{title}\" (id=#{h[:conversation_id]}, source=#{h[:conversation_source]}, " \
               "turn=#{h[:turn_idx]}, score=#{format('%.3f', h[:score])})"
      lines << "    > #{snippet}"
      lines << ''
    end
    lines.join("\n").strip
  end
end
