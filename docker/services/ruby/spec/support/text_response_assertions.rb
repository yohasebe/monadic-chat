# frozen_string_literal: true

module TextResponseAssertions
  def assert_valid_text_response(response, min_len: 3, banned_patterns: [/\bapi\s+error\b/i])
    expect(response).to be_a(Hash)
    text = response[:text] || response['text']
    expect(text).to be_a(String)
    expect(text.strip.length).to be >= min_len
    banned_patterns.each do |pat|
      expect(text).not_to match(pat)
    end
    text
  end
end
