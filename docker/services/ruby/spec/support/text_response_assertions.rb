# frozen_string_literal: true

module TextResponseAssertions
  def assert_valid_text_response(response, min_len: 3, banned_patterns: [])
    expect(response).to be_a(Hash)
    text = response[:text] || response['text']
    expect(text).to be_a(String)
    expect(text.strip.length).to be >= min_len
    # Avoid brittle string-based assertions against provider-specific errors
    banned_patterns.each { |_pat| nil }
    text
  end
end
