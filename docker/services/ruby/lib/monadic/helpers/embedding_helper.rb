module MonadicHelper
  def cosine_similarity(a, b)
    raise ArgumentError, "a and b must be of the same size" if a.size != b.size

    dot_product = a.zip(b).map { |x, y| x * y }.sum
    magnitude_a = Math.sqrt(a.map { |x| x**2 }.sum)
    magnitude_b = Math.sqrt(b.map { |x| x**2 }.sum)
    dot_product / (magnitude_a * magnitude_b)
  end

  def most_similar_text_index(topic, texts)
    embeddings = get_embeddings(topic)
    texts_embeddings = texts.map { |t| get_embeddings(t) }.compact
    cosine_similarities = texts_embeddings.map { |e| cosine_similarity(embeddings, e) }
    cosine_similarities.each_with_index.max[1]
  end

  def split_text(text)
    tokenized = MonadicApp::TOKENIZER.get_tokens_sequence(text)
    segments = []
    while tokenized.size < MAX_TOKENS_WIKI.to_i
      segment = tokenized[0..MAX_TOKENS_WIKI.to_i]
      segments << MonadicApp::TOKENIZER.decode_tokens(segment)
      tokenized = tokenized[MAX_TOKENS_WIKI.to_i..]
    end
    segments << flask_app_client.decode_tokens(tokenized)
    segments
  rescue StandardError
    [text]
  end

  def get_embeddings(text, retries: 3)
    raise ArgumentError, "text cannot be empty" if text.empty?

    uri = URI("https://api.openai.com/v1/embeddings")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"

    api_key = ENV["OPENAI_API_KEY"]

    request["Authorization"] = "Bearer #{api_key}"
    request.body = {
      model: "text-embedding-3-small",
      input: text
    }.to_json

    response = nil
    retries.times do |i|
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
      break if response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      puts "Error: #{e.message}. Retrying in #{i + 1} seconds..."
      sleep(i + 1)
    end

    begin
      JSON.parse(response.body)["data"][0]["embedding"]
    rescue StandardError
      nil
    end
  end

  def list_titles
    if embeddings_db.nil?
      return "Error: The database connection is not available."
    end

    res = embeddings_db.list_titles
    if res.empty?
      "Error: No titles found."
    else
      res.to_json
    end
  end

  def get_text_snippets(doc_id:)
    if embeddings_db.nil?
      return "Error: The database connection is not available."
    end

    res = embeddings_db.get_text_snippets(doc_id)
    if res.empty?
      "Error: No text snippets found."
    else
      res.to_json
    end
  end

  def find_closest_text(text: "", top_n: 1)
    if embeddings_db.nil?
      return "Error: The database connection is not available."
    end

    res = embeddings_db.find_closest_text(text, top_n: top_n)
    if res.empty?
      "Error: The text could not be found."
    else
      res.to_json
    end
  rescue StandardError
    "Error: The text could not be found."
  end

  def find_closest_doc(text: "", top_n: 1)
    if embeddings_db.nil?
      return "Error: The database connection is not available."
    end

    res = embeddings_db.find_closest_doc(text, top_n: top_n)
    if res.empty?
      "Error: The document could not be found."
    else
      res.to_json
    end
  rescue StandardError
    "Error: The document could not be found."
  end

  def get_text_snippet(doc_id:, position:)
    if embeddings_db.nil?
      return "Error: The database connection is not available."
    end

    res = embeddings_db.get_text_snippet(doc_id, position)
    if res.empty?
      "Error: The text could not be found."
    else
      res.to_json
    end
  rescue StandardError
    "Error: The text could not be found."
  end
end
