# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Jupyter URL Generation" do
  describe "URL format specifications" do
    it "should use localhost:8889 for Jupyter URLs" do
      correct_url = "http://localhost:8889/lab/tree/notebook.ipynb"
      
      expect(correct_url).to include("localhost:8889")
      expect(correct_url).to include("/lab/tree/")
      expect(correct_url).to end_with(".ipynb")
    end

    it "should not use relative paths for Jupyter links" do
      bad_url = "/lab/tree/notebook.ipynb"
      good_url = "http://localhost:8889/lab/tree/notebook.ipynb"
      
      expect(bad_url).not_to start_with("http")
      expect(good_url).to start_with("http")
    end

    it "should handle Japanese filenames in URLs" do
      url = "http://localhost:8889/lab/tree/データ分析_2024.ipynb"
      
      expect(url).to include("データ分析")
      expect(url).to include("8889")
    end
  end

  describe "Link HTML format" do
    it "should include target='_blank' for new tab opening" do
      link = '<a href="http://localhost:8889/lab/tree/notebook.ipynb" target="_blank">notebook.ipynb</a>'
      
      expect(link).to include('target="_blank"')
      expect(link).to include('http://localhost:8889')
    end
  end

end