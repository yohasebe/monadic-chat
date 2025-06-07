require 'nokogiri'
require 'fileutils'

module DrawIOGrapher
  # Template for a valid minimal Draw.io diagram
  MINIMAL_TEMPLATE = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <mxfile host="app.diagrams.net" modified="#{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ')}" agent="Mozilla/5.0">
      <diagram id="default-diagram" name="Page-1">
        <mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0">
          <root>
            <mxCell id="0"/>
            <mxCell id="1" parent="0"/>
            <!-- Content goes here -->
          </root>
        </mxGraphModel>
      </diagram>
    </mxfile>
  XML

  def write_drawio_file(content:, filename: "diagram")
    # Handle file extension
    filename = "#{filename}.drawio" unless filename.end_with?(".drawio")
    
    # Use the correct data directory based on whether we're in a container
    # Handle both direct MonadicApp constants and global constants
    in_container = defined?(MonadicApp::IN_CONTAINER) ? MonadicApp::IN_CONTAINER : 
                   defined?(IN_CONTAINER) ? IN_CONTAINER : false
    
    if in_container
      # Try multiple possible paths for container environment
      data_dir = if defined?(MonadicApp::SHARED_VOL)
                   MonadicApp::SHARED_VOL
                 elsif defined?(SHARED_VOL)
                   SHARED_VOL
                 else
                   "/monadic/data"
                 end
    else
      # Try multiple possible paths for local environment
      data_dir = if defined?(MonadicApp::LOCAL_SHARED_VOL)
                   MonadicApp::LOCAL_SHARED_VOL
                 elsif defined?(LOCAL_SHARED_VOL)
                   LOCAL_SHARED_VOL
                 else
                   File.expand_path(File.join(Dir.home, "monadic", "data"))
                 end
    end
    
    # Ensure the data directory exists
    unless File.directory?(data_dir)
      begin
        FileUtils.mkdir_p(data_dir)
      rescue StandardError => e
        return "Error: Could not create directory #{data_dir}: #{e.message}"
      end
    end
    
    filepath = File.join(data_dir, filename)
    
    # Debug information for troubleshooting (enabled via environment variable)
    if ENV['DRAWIO_DEBUG']
      puts "[DEBUG] DrawIOGrapher: in_container=#{in_container}"
      puts "[DEBUG] DrawIOGrapher: data_dir=#{data_dir}"
      puts "[DEBUG] DrawIOGrapher: filepath=#{filepath}"
      puts "[DEBUG] DrawIOGrapher: directory exists=#{File.directory?(data_dir)}"
    end
    
    # Validate and repair XML content
    validated_content = validate_and_repair_drawio_xml(content)
    
    # Write the file synchronously - this keeps the spinner active until completion
    write_file_synchronously(validated_content, filepath, filename, data_dir)
  end
  
  private
  
  def write_file_synchronously(validated_content, filepath, filename, data_dir)
    begin
      puts "[DEBUG] DrawIOGrapher: Attempting to write file..." if ENV['DRAWIO_DEBUG']
      File.open(filepath, "w") do |f|
        f.write(validated_content)
      end
      puts "[DEBUG] DrawIOGrapher: File written successfully" if ENV['DRAWIO_DEBUG']
      
      # Verify file was written with shorter retry intervals for better UX
      success = false
      max_retrial = 10  # Reduced from 20
      max_retrial.times do |i|
        sleep 0.2  # Reduced from 0.5 to 0.2 seconds
        if File.exist?(filepath)
          file_size = File.size(filepath)
          puts "[DEBUG] DrawIOGrapher: File verification success (size: #{file_size} bytes)" if ENV['DRAWIO_DEBUG']
          success = true
          break
        else
          puts "[DEBUG] DrawIOGrapher: File verification attempt #{i+1}/#{max_retrial} failed" if ENV['DRAWIO_DEBUG']
        end
      end
      
      # Final verification - ensure file is readable and has content
      if success && File.size(filepath) > 0
        puts "[DEBUG] DrawIOGrapher: Final verification passed" if ENV['DRAWIO_DEBUG']
        result = "The file #{filename} has been saved successfully to the shared folder (#{data_dir})."
      else
        result = "Error: The file could not be verified at #{filepath}."
      end
      
      # Force synchronization before returning
      STDOUT.flush
      return result
    rescue StandardError => e
      error_result = "Error: The file could not be written to #{filepath}.\nReason: #{e.message}\nBacktrace: #{e.backtrace.first(3).join('\n')}"
      puts "[DEBUG] DrawIOGrapher: #{error_result}" if ENV['DRAWIO_DEBUG']
      STDOUT.flush
      return error_result
    end
  end
  
  # Validate and repair Draw.io XML content
  def validate_and_repair_drawio_xml(content)
    begin
      # Convert literal \n string to actual newlines (common issue with OpenAI models)
      content = content.gsub('\\n', "\n") if content.include?('\\n')
      
      # Parse XML to check validity
      doc = Nokogiri::XML(content) { |config| config.noblanks }
      
      # Check for basic Draw.io structure
      unless has_valid_drawio_structure?(doc)
        return repair_drawio_xml(content)
      end
      
      # If we get here, the XML is valid enough
      return content
    rescue => e
      # If there's any parsing error, try to repair
      return repair_drawio_xml(content)
    end
  end
  
  # Check if the XML has valid Draw.io structure
  def has_valid_drawio_structure?(doc)
    # Check for mxfile root element
    root = doc.root
    return false unless root && root.name == 'mxfile'
    
    # Check for at least one diagram element
    diagram = root.at_xpath('.//diagram')
    return false unless diagram
    return false unless diagram['id'] && diagram['name']
    
    # Check for mxGraphModel element
    graph_model = diagram.at_xpath('.//mxGraphModel')
    return false unless graph_model
    
    # Check for root element in the graph model
    root_cell = graph_model.at_xpath('.//root')
    return false unless root_cell
    
    # All checks passed
    true
  end
  
  # Try to repair the Draw.io XML
  def repair_drawio_xml(content)
    # Convert literal \n string to actual newlines (common issue with OpenAI models)
    content = content.gsub('\\n', "\n") if content.include?('\\n')
    
    # If the content appears to be just cells or partial content
    if content.include?('<mxCell') && !content.include?('<mxfile')
      # Fix common typos/errors in mxCell tags before extraction
      fixed_content = content.gsub(/<mxGeomexCell/, '<mxGeometry></mxCell')
                             .gsub(/<\/mxGeomexCell>/, '</mxGeometry></mxCell>')
      
      # Use Nokogiri to cleanly extract and fix cells when possible
      begin
        fragment = Nokogiri::XML.fragment("<root>#{fixed_content}</root>")
        cells = fragment.xpath(".//mxCell").map(&:to_xml).join("\n")
      rescue => e
        # Fallback to regex if Nokogiri parsing fails
        cell_pattern = /<mxCell.*?<\/mxCell>/m
        cells = fixed_content.scan(cell_pattern).join("\n")
        
        # If still no cells found, try more lenient pattern
        if cells.empty?
          cell_pattern = /<mxCell.*?\/mxCell>/m
          cells = fixed_content.scan(cell_pattern).join("\n")
        end
      end
      
      # If no cells were found, try to salvage any XML-like content
      if cells.empty?
        # Try to extract anything that looks like XML tags
        tag_pattern = /<[^>]+>.*?<\/[^>]+>/m
        cells = fixed_content.scan(tag_pattern).join("\n")
      end
      
      # Insert into template
      template = MINIMAL_TEMPLATE.dup
      insertion_point = template.index('<!-- Content goes here -->')
      if insertion_point
        template.insert(insertion_point, cells)
      else
        # Fallback to simple replacement
        template.gsub!('<!-- Content goes here -->', cells)
      end
      
      return template
    elsif content.include?('<diagram') && !content.include?('<mxfile')
      # Content has diagram but no mxfile wrapper
      template = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<mxfile host=\"app.diagrams.net\" modified=\"#{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ')}\" agent=\"Mozilla/5.0\">\n#{content}\n</mxfile>"
      return template
    elsif !content.include?('<?xml')
      # Missing XML declaration
      return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n#{content}"
    end
    
    # If we can't repair it in a specific way, return the minimal template
    return MINIMAL_TEMPLATE
  end
end
