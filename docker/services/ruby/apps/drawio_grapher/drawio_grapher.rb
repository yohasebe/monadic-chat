require 'nokogiri'

class DrawIOGrapher < MonadicApp
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
    if defined?(IN_CONTAINER) && IN_CONTAINER
      data_dir = SHARED_VOL
    else
      data_dir = LOCAL_SHARED_VOL
    end
    
    filepath = File.join(data_dir, filename)
    
    # Validate and repair XML content
    validated_content = validate_and_repair_drawio_xml(content)
    
    # Write the file
    begin
      File.open(filepath, "w") do |f|
        f.write(validated_content)
      end
      
      # Verify file was written
      success = false
      max_retrial = 20
      max_retrial.times do
        sleep 0.5
        if File.exist?(filepath)
          success = true
          break
        end
      end
      
      # Explicitly wrap the result string in a variable and return it
      # This ensures the function result can be properly processed
      result = if success
        "The file #{filename} has been saved to the shared folder."
      else
        "Error: The file could not be written."
      end
      
      # Force synchronization before returning
      STDOUT.flush
      return result
    rescue StandardError => e
      error_result = "Error: The file could not be written.\n#{e}"
      STDOUT.flush
      return error_result
    end
  end
  
  private
  
  # Validate and repair Draw.io XML content
  def validate_and_repair_drawio_xml(content)
    begin
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
    # If the content appears to be just cells or partial content
    if content.include?('<mxCell') && !content.include?('<mxfile')
      # Extract cells
      cell_pattern = /<mxCell.*?\/mxCell>/m
      cells = content.scan(cell_pattern).join("\n")
      
      # If no cells were found, try to salvage any XML-like content
      if cells.empty?
        # Try to extract anything that looks like XML tags
        tag_pattern = /<[^>]+>.*?<\/[^>]+>/m
        cells = content.scan(tag_pattern).join("\n")
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
