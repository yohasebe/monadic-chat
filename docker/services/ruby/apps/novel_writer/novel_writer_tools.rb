class NovelWriter < MonadicApp
  def count_num_of_words(text: "")
    text.split.size
  end

  def count_num_of_chars(text: "")
    text.size
  end
end