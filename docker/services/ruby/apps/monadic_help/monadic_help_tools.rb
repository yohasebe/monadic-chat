# frozen_string_literal: true

# Tools for Monadic Help application
module MonadicHelpTools
  def help_embeddings_db
    return @help_embeddings_db if defined?(@help_embeddings_db)
    
    if defined?(HELP_EMBEDDINGS_DB) && HELP_EMBEDDINGS_DB
      @help_embeddings_db = HELP_EMBEDDINGS_DB
    else
      puts "[MonadicHelpTools] Warning: HELP_EMBEDDINGS_DB not available"
      @help_embeddings_db = nil
    end
  end

  def find_help_topics(text:, top_n: 10, chunks_per_result: nil, include_internal: nil)
    unless help_embeddings_db
      puts "[MonadicHelpTools] Error: Help database not available in find_help_topics"
      return { error: "Help database not available. Please ensure the help database has been built with 'rake help:build'." }
    end

    # Auto-detect DEBUG_MODE if include_internal not explicitly specified
    include_internal = (ENV['DEBUG_MODE'] == 'true') if include_internal.nil?

    # Get chunks per result from environment or use default
    chunks_per_result ||= (ENV['HELP_CHUNKS_PER_RESULT'] || '3').to_i

    # Use multi-chunk search for better context
    results = help_embeddings_db.find_closest_text_multi(text,
                                                        chunks_per_result: chunks_per_result,
                                                        top_n: top_n,
                                                        include_internal: include_internal)

    # Group results by document for better presentation
    grouped_results = {}
    results.each do |result|
      doc_key = "#{result[:doc_id]}_#{result[:title]}"
      grouped_results[doc_key] ||= {
        doc_id: result[:doc_id],
        title: result[:title],
        file_path: result[:file_path],
        section: result[:section],
        language: result[:language],
        chunks: []
      }

      grouped_results[doc_key][:chunks] << {
        text: result[:text],
        heading: result[:heading],
        position: result[:position],
        similarity: result[:similarity]
      }
    end

    # Format for output
    formatted_results = grouped_results.values.map do |doc|
      {
        doc_id: doc[:doc_id],
        title: doc[:title],
        file_path: doc[:file_path],
        section: doc[:section],
        language: doc[:language],
        chunks: doc[:chunks].sort_by { |c| c[:position] },
        avg_similarity: doc[:chunks].map { |c| c[:similarity] }.sum.to_f / doc[:chunks].size
      }
    end.sort_by { |doc| -doc[:avg_similarity] }

    { results: formatted_results }
  rescue => e
    { error: "Error searching help database: #{e.message}" }
  end

  def get_help_document(doc_id:)
    return { error: "Help database not available" } unless help_embeddings_db
    
    snippets = help_embeddings_db.get_text_snippets(doc_id)
    
    # Combine snippets into full document
    full_text = snippets.map { |s| s[:text] }.join("\n\n")
    
    { 
      doc_id: doc_id,
      content: full_text,
      snippets_count: snippets.length
    }
  rescue => e
    { error: "Error retrieving document: #{e.message}" }
  end

  def list_help_sections(language: nil)
    return { error: "Help database not available" } unless help_embeddings_db
    
    begin
      titles = help_embeddings_db.list_titles(language: language)
    rescue NoMethodError => e
      return { error: "Help database not properly initialized. Please restart the server." }
    end
    
    # Group by section
    sections = titles.group_by { |t| t[:section] }
    
    formatted_sections = sections.map do |section, docs|
      {
        section: section,
        documents: docs.map { |d| 
          {
            title: d[:title],
            file_path: d[:file_path],
            doc_id: d[:doc_id]
          }
        }
      }
    end
    
    { sections: formatted_sections }
  rescue => e
    { error: "Error listing sections: #{e.message}" }
  end

  def search_help_by_section(text:, section:, top_n: 3, chunks_per_result: nil, include_internal: nil)
    return { error: "Help database not available" } unless help_embeddings_db

    # Auto-detect DEBUG_MODE if include_internal not explicitly specified
    include_internal = (ENV['DEBUG_MODE'] == 'true') if include_internal.nil?

    # Get chunks per result from environment or use default
    chunks_per_result ||= (ENV['HELP_CHUNKS_PER_RESULT'] || '3').to_i

    # First get more results to ensure we have enough from the target section
    all_results = help_embeddings_db.find_closest_text(text, top_n: top_n * 10, include_internal: include_internal)

    # Filter by section and group by document
    section_docs = {}
    all_results.each do |result|
      next unless result[:section].downcase == section.downcase

      doc_key = "#{result[:doc_id]}_#{result[:title]}"
      section_docs[doc_key] ||= {
        doc_id: result[:doc_id],
        title: result[:title],
        file_path: result[:file_path],
        chunks: []
      }

      if section_docs[doc_key][:chunks].length < chunks_per_result
        section_docs[doc_key][:chunks] << {
          text: result[:text],
          heading: result[:heading],
          position: result[:position],
          similarity: result[:similarity]
        }
      end
    end

    # Take top N documents and format results
    formatted_results = section_docs.values.take(top_n).map do |doc|
      {
        doc_id: doc[:doc_id],
        title: doc[:title],
        file_path: doc[:file_path],
        chunks: doc[:chunks].sort_by { |c| c[:position] },
        avg_similarity: doc[:chunks].map { |c| c[:similarity] }.sum.to_f / doc[:chunks].size
      }
    end.sort_by { |doc| -doc[:avg_similarity] }

    {
      section: section,
      results: formatted_results
    }
  rescue => e
    { error: "Error searching by section: #{e.message}" }
  end
end