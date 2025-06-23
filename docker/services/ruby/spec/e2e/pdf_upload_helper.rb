# frozen_string_literal: true

require 'net/http'
require 'net/http/post/multipart'
require 'tempfile'
require 'prawn'

module PDFUploadHelper
  # Upload a PDF file via HTTP POST
  def upload_pdf_via_http(filename, title, content_blocks)
    # Create a temporary PDF file
    pdf_file = create_temp_pdf(content_blocks)
    
    begin
      uri = URI('http://localhost:4567/pdf')
      
      # Create multipart form data
      req = Net::HTTP::Post::Multipart.new uri.path,
        "pdfFile" => UploadIO.new(pdf_file, "application/pdf", filename),
        "pdfTitle" => title
      
      # Add headers
      req['X-Requested-With'] = 'XMLHttpRequest'  # Make it an AJAX request
      
      # Send request
      response = Net::HTTP.start(uri.hostname, uri.port) do |http|
        http.request(req)
      end
      
      if response.code == '200'
        JSON.parse(response.body)
      else
        { success: false, error: "HTTP #{response.code}: #{response.body}" }
      end
    ensure
      # Clean up temp file
      pdf_file.close
      pdf_file.unlink
    end
  end
  
  private
  
  # Create a temporary PDF file with content
  def create_temp_pdf(content_blocks)
    pdf_file = Tempfile.new(['test_pdf', '.pdf'])
    
    Prawn::Document.generate(pdf_file.path) do |pdf|
      content_blocks.each_with_index do |block, index|
        pdf.text block[:title], size: 16, style: :bold if block[:title]
        pdf.move_down 10
        pdf.text block[:content], size: 12
        pdf.start_new_page unless index == content_blocks.length - 1
      end
    end
    
    pdf_file.rewind
    pdf_file
  end
end

# For multipart form data support
begin
  require 'multipart-post'
rescue LoadError
  puts "WARNING: multipart-post gem not found. PDF upload tests will fail."
  puts "Add 'gem \"multipart-post\"' to your Gemfile"
end