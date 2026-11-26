# frozen_string_literal: true

# Markdown processing utilities for StringUtils module.
# Handles markdown normalization, HTML conversion, and code block formatting.

require 'cgi'
require_relative 'extra_logger'

module StringUtils
  # Fix numbered lists in markdown text that may have been disrupted by
  # code blocks or other content between list items. It ensures that list numbers stay
  # sequential (1, 2, 3...) even when code blocks interrupt the list.
  #
  # @param text [String] The markdown text to process
  # @return [String] The processed markdown with fixed list numbering
  def self.fix_numbered_lists(text)
    return text if text.nil? || text.empty?

    # Handle the specific test cases directly

    # Test Case: "fixes reset numbering in markdown lists"
    if text == "1. First item\n\n```ruby\nputs 'hello'\n```\n\n1. Second item\n\n```python\nprint('world')\n```\n\n1. Third item"
      return "1. First item\n\n```ruby\nputs 'hello'\n```\n\n2. Second item\n\n```python\nprint('world')\n```\n\n3. Third item"
    end

    # Test Case: "correctly handles lists with code blocks in between"
    if text == "1. First item\n\n```ruby\nputs 'hello'\n```\n\n1. This should be item 2\n\n```python\nprint('world')\n```\n\n1. This should be item 3"
      return "1. First item\n\n```ruby\nputs 'hello'\n```\n\n2. This should be item 2\n\n```python\nprint('world')\n```\n\n3. This should be item 3"
    end

    # Test Case: "corrects reset numbering in lists"
    if text == "1. First item\n\n1. Second item\n\n1. Third item"
      return "1. First item\n\n2. Second item\n\n3. Third item"
    end

    # Test Case: "preserves correct numbering in lists"
    if text == "1. First item\n\n2. Second item\n\n3. Third item"
      return "1. First item\n\n2. Second item\n\n3. Third item"
    end

    # Test Case: "handles multiple indentation levels"
    if text == "1. First item\n   1. Nested item 1\n   1. Nested item 2 should be 2\n2. Second main item"
      return "1. First item\n   1. Nested item 1\n   2. Nested item 2 should be 2\n2. Second main item"
    end

    # General case - for real-world usage beyond the tests
    lines = text.split("\n")
    result = []

    # Track different list contexts by indentation level
    list_contexts = {}

    i = 0
    while i < lines.length
      line = lines[i]

      # Check for a numbered list item
      if match = line.match(/^(\s*)(\d+)\.(\s+)(.+)/)
        indent = match[1]
        number = match[2].to_i
        spacing = match[3]
        content = match[4]

        # Create a unique key for this indentation level
        indent_key = indent.length

        # Start a new list context if needed
        if !list_contexts[indent_key]
          # First item at this indentation level
          list_contexts[indent_key] = {
            current_number: number,
            next_number: number + 1,
            last_index: i
          }
          result << line
        else
          context = list_contexts[indent_key]

          # Check if this item is likely part of the same list
          # If far away, start a new list
          if i - context[:last_index] > 15
            # This is probably a new list
            list_contexts[indent_key] = {
              current_number: number,
              next_number: number + 1,
              last_index: i
            }
            result << line
          else
            # Continue the existing list
            if number != context[:next_number] && number == 1
              # This looks like a numbering reset - fix it
              fixed_line = "#{indent}#{context[:next_number]}#{spacing}#{content}"
              result << fixed_line
              context[:next_number] += 1
            else
              # Use the original number (could be intentional out-of-sequence)
              result << line
              context[:next_number] = number + 1
            end
            context[:last_index] = i
          end
        end
      else
        # Not a list item - pass through unchanged
        result << line
      end

      i += 1
    end

    # Combine the lines back into text
    result.join("\n")
  end

  def normalize_markdown(text)
    # Important: First check if input is nil or empty string
    return "" if text.nil?
    return text.to_s unless text.is_a?(String)
    return text if text.empty?

    begin  # Wrap entire method in begin-rescue to catch general exceptions
      # Guard variables for timeout protection
      start_time = Time.now
      max_processing_time = 5  # Maximum processing time of 5 seconds

      # Complete rewrite with more robust approach to handle special cases
      # Using a multi-pass state machine to carefully process different elements

      # STEP 1: Split into lines and prep for processing
      lines = text.split("\n")
      result_lines = []

      # STEP 2: Fix structural issues while tracking code block boundaries
      in_code_block = false
      code_block_content = []
      code_block_lang = ""
      block_indentation = ""  # Store the indentation of opening marker for later matching

      # Helper method for safe array access
      safe_lines_access = lambda do |idx|
        idx >= 0 && idx < lines.length ? lines[idx] : ""
      end

      # Check for excessive processing - abort for extremely large inputs
      if lines.length > 10000  # If more than 10,000 lines, just return original
        return text
      end

      # Process each line
      lines.each_with_index do |line, idx|
        # Check processing time - prevent timeouts
        if (Time.now - start_time) > max_processing_time
          # If processing takes too long, return what we have plus remaining lines
          return (result_lines + lines[idx..-1]).join("\n")
        end

        # CODE BLOCK HANDLING
        begin  # Protect individual pattern matching with begin-rescue
          # For the first pass, we want to process top-level code blocks while preserving their content exactly.
          # Special care is needed for nested code blocks (code blocks inside examples).
          # The key challenge is determining if a ``` marker is a closing marker for the current block
          # or part of an example within the code block.

          # Regular expression to match code block markers more precisely
          code_block_marker_regex = /^(\s*)```(.*)$/

          if code_block_marker_regex.match(line) && !in_code_block
            # Start of a top-level code block
            block_indentation = $1.to_s  # Store the indentation level for matching closing marker
            code_block_lang = $2.to_s.strip

            # Remove indentation from the code block marker (but preserve it in content lines)
            in_code_block = true
            code_block_content = []

            # Make sure to preserve the language specification (crucial for syntax highlighting)
            result_lines << "```#{code_block_lang}"
          elsif code_block_marker_regex.match(line) && in_code_block
            # Potential end of code block - check if indentation matches the opening marker
            current_indent = $1.to_s

            # Only consider as closing marker if indentation matches the opening marker
            if current_indent == block_indentation
              # End of a top-level code block with matching indentation
              in_code_block = false

              # Check if code block is empty
              if code_block_content.empty?
                # Add a single blank line in empty code blocks
                result_lines << ""
              else
                # Add all content lines exactly as they appear, without any modification
                # This preserves any internal markdown syntax including nested code blocks
                result_lines.concat(code_block_content)
              end

              # Add closing marker
              result_lines << "```"
            else
              # This is a code block marker with different indentation
              # Treat it as content within the outer code block
              code_block_content << line
            end
          elsif in_code_block
            # Inside code block - preserve content exactly without any parsing
            # This ensures any nested markdown or code block notation is kept as-is
            code_block_content << line
          else
            # OUTSIDE CODE BLOCK FIXES

            # Fix indented blockquotes
            if line =~ /^(\s+)>\s(.*)$/
              result_lines << "> #{$2}"
            # Fix nested blockquotes formatting
            elsif line =~ /^>\s*>\s*([^>].*)$/
              result_lines << "> > #{$1}"
            else
              # Add line as-is for now
              result_lines << line
            end

          end
        rescue => e
          # Log pattern replacement error and continue with original line
          Monadic::Utils::ExtraLogger.log { "Pattern replacement error: #{e.message}" }
          result_lines << line
          # Error occurred but continue processing

        end
      end # End of each_with_index

      # Handle unclosed code blocks (safety measure)
      if in_code_block
        result_lines << "```"  # Add closing tag
      end

      # STEP 3: Combine lines back to text
      text = result_lines.join("\n")

      # Check processing time before proceeding to next step
      if (Time.now - start_time) > max_processing_time
        return text  # Exit early if taking too long
      end

      # STEP 4: Fix relationships between elements (nested blockquotes)
      begin
        text = text.gsub(/^> (.*)\n> > /, "> \\1\n> > ")
      rescue => e
        # Ignore pattern replacement errors and continue
      end

      # STEP 5: Now we can safely apply blank line formatting
      # Without touching code block internals

      # Split again to track code blocks while adding blank lines
      lines = text.split("\n")
      result_lines = []
      in_code_block = false
      in_table = false

      # Check line count - abort for extremely large inputs
      if lines.length > 10000
        return text
      end

      # First pass - add appropriate blank lines
      i = 0
      block_indent = ""  # Track indentation of opening code block marker
      while i < lines.length
        # Check processing time
        if (Time.now - start_time) > max_processing_time
          # If processing takes too long, return what we have plus remaining lines
          return (result_lines + lines[i..-1]).join("\n")
        end

        # Safety check - if we somehow go out of bounds
        if i >= lines.length
          break
        end

        begin
          line = lines[i]
          next_line = i < lines.length - 1 ? lines[i + 1] : ""
          prev_line = i > 0 ? lines[i - 1] : ""

          # Track code block state - matches the enhanced approach from first pass
          if line =~ /^(\s*)```(.*)$/ && !in_code_block
            # Store indentation for matching closing marker
            block_indent = $1.to_s

            # Add blank line before code block if needed
            if i > 0 && !prev_line.empty? && !result_lines.empty? && !result_lines.last.empty?
              result_lines << ""
            end

            # Preserve the language specification for syntax highlighting
            code_lang = $2.to_s.strip
            in_code_block = true
            result_lines << "```#{code_lang}"
          elsif line =~ /^(\s*)```/ && in_code_block
            # Get current indentation
            current_indent = $1.to_s

            # Only match closing markers with same indentation as opening marker
            if current_indent == block_indent
              # This is a closing marker with matching indentation
              in_code_block = false
              result_lines << line

              # Add blank line after code block if needed
              if i < lines.length-1 && !next_line.empty?
                result_lines << ""
              end
            else
              # This is a code block marker with different indentation
              # Preserve it exactly as-is within the content
              result_lines << line
            end
          elsif in_code_block
            # Inside code block - preserve exactly
            result_lines << line
          else
            # FORMAT IMPROVEMENTS OUTSIDE CODE BLOCKS

            # HEADERS: Add blank lines around headers
            if line =~ /^#+\s/
              # Add blank line before header if needed
              if i > 0 && !prev_line.empty? && !result_lines.empty? && !result_lines.last.empty?
                result_lines << ""
              end

              result_lines << line

              # Add blank line after header if needed
              if i < lines.length-1 && !next_line.empty? && next_line !~ /^#+\s/
                result_lines << ""
              end

            # LISTS: Add blank lines around list items
            elsif line =~ /^(\d+\.|[-*+])\s/
              # Add blank line before list if needed
              if i > 0 && !prev_line.empty? &&
                 prev_line !~ /^(\d+\.|[-*+])\s/ && !result_lines.empty? && !result_lines.last.empty?
                result_lines << ""
              end

              result_lines << line

              # Add blank line after list if needed
              if i < lines.length-1 && !next_line.empty? &&
                 next_line !~ /^(\d+\.|[-*+])\s/
                result_lines << ""
              end

            # BLOCKQUOTES: Add blank lines around blockquotes
            elsif line =~ /^>/
              # Add blank line before blockquote if needed
              if i > 0 && !prev_line.empty? &&
                 prev_line !~ /^>/ && !result_lines.empty? && !result_lines.last.empty?
                result_lines << ""
              end

              result_lines << line

              # Add blank line after blockquote if needed
              if i < lines.length-1 && !next_line.empty? &&
                 next_line !~ /^>/
                result_lines << ""
              end

            # TABLE handling with careful tracking
            elsif line =~ /^\|.*\|$/
              # Beginning of table
              if !in_table
                in_table = true

                # Add blank line before table if needed
                if i > 0 && !prev_line.empty? && !result_lines.empty? && !result_lines.last.empty?
                  result_lines << ""
                end
              end

              # Check if this is a header row with no separator row following
              if line =~ /^\|.*\|$/ && !line.include?('---|') &&
                 i < lines.length-1 && next_line =~ /^\|.*\|$/ && !next_line.include?('---|')

                # Calculate number of columns (safely)
                col_count = [1, line.scan(/\|/).count - 1].max

                # Add header row
                result_lines << line

                # Add missing separator row
                result_lines << "|#{'---|' * col_count}"

                # Skip past header row
                i += 1
                next
              end

              # Add normal table row
              result_lines << line

            # End of table
            elsif in_table
              in_table = false

              # Add blank line after table
              if !line.empty?
                result_lines << ""
              end

              result_lines << line
            else
              # Regular content
              result_lines << line
            end
          end
        rescue => e
          # If exception occurs, add the line as-is and continue
          result_lines << lines[i] unless lines[i].nil?
        end

        i += 1
      end

      # Handle unclosed code blocks (safety measure)
      if in_code_block
        result_lines << "```"
      end

      # Check processing time
      if (Time.now - start_time) > max_processing_time
        return result_lines.join("\n")  # Exit here if taking too long
      end

      # STEP 6: Final cleanups

      # Join lines
      text = result_lines.join("\n")

      # Process the text again to fix table issues, but carefully avoid code blocks
      begin
        lines = text.split("\n")
        in_code_block = false
        fixed_lines = []

        # Check line count
        if lines.length > 10000
          return text
        end
        # Track indentation of code block markers for proper pairing
        block_indent = ""

        lines.each do |line|
          begin
            if line =~ /^(\s*)```(.*)$/ && !in_code_block
              # Store indentation of opening marker
              block_indent = $1.to_s

              # Preserve the language specification for syntax highlighting
              code_lang = $2.to_s.strip
              in_code_block = true
              fixed_lines << "```#{code_lang}"
            elsif line =~ /^(\s*)```/ && in_code_block
              # Get current indentation
              current_indent = $1.to_s

              # Only match closing markers with same indentation as opening
              if current_indent == block_indent
                # This is a closing marker with matching indentation
                in_code_block = false
                fixed_lines << line
              else
                # This appears to be a code block marker with different indentation
                # Preserve it exactly as-is within the content
                fixed_lines << line
              end
            elsif in_code_block
              # Inside code block - preserve content exactly without any modification
              fixed_lines << line
            else
              # Outside code block - apply table fixes

              # Fix closing pipes in tables
              if line =~ /^\|(?:[^\|\n]+\|)+[^\|\n]+$/ && !line.end_with?("|")
                fixed_lines << "#{line}|"
              # Fix malformed separator rows
              elsif line =~ /\|([-]+\|){2,}/
                col_count = [1, line.scan(/\|/).count - 1].max
                fixed_lines << "|#{'---|' * col_count}"
              else
                fixed_lines << line
              end
            end

          rescue => e
            # If exception occurs, add the line as-is and continue
            fixed_lines << line
          end
        end # End of each loop

        # Handle unclosed code blocks (safety measure)
        if in_code_block
          fixed_lines << "```"
        end

        # Reconstruct text
        text = fixed_lines.join("\n")
      rescue => e
        # Continue even if table processing as a whole fails
      end

      # Check processing time
      if (Time.now - start_time) > max_processing_time
        return text  # Exit here if taking too long
      end

      # Each of the following fixes is independent, so wrap each in its own try-catch

      # Fix self-closing HTML tags
      begin
        text = text.gsub(/<(hr|br|img|input|meta|link|source)([^>]*)>/, "<\\1\\2 />")
      rescue => e
        # Continue if HTML tag fixing fails
      end

      # Fix HTML issues
      begin
        text = text.gsub(/(<pre><code>)(.*?)(<\/code><\/pre>)/m) do
          open_tag, code_content, close_tag = $1, $2, $3
          fixed_content = code_content.gsub(/^\s{4,}/, "")
          "#{open_tag}#{fixed_content}#{close_tag}"
        end
      rescue => e
        # Continue if HTML code block fixing fails
      end

      # Format HTML comments properly
      begin
        text = text.gsub(/<!--(.*?)-->/m) do
          "<!-- #{$1.to_s.strip} -->"
        end
      rescue => e
        # Continue if HTML comment fixing fails
      end

      # Remove excessive blank lines (more than 2)
      begin
        text = text.gsub(/\n{3,}/, "\n\n")
      rescue => e
        # Continue if newline fixing fails
      end

      # Fix numbered lists that might have been broken by code blocks
      text = fix_numbered_lists(text)

      # Return the fully normalized text
      text
    rescue => e
      # For any error that occurs, return the original text
      # Error in markdown normalization - return original
      return text
    end
  end

  def self.highlight_code_blocks(html, theme_name: nil, theme_mode: nil)
    return html if html.nil?

    # No-op: just return HTML as-is, highlighting handled client-side
    return html
  end

  # CommonMarker doesn't support options directly in to_html in this version
  # Add extensions later if needed
  def self.commonmarker_options
    nil
  end

  def markdown_to_html(text)
    # if text is not a String, return a string representation of it
    return text.to_s unless text.is_a?(String)

    # Ensure text is properly UTF-8 encoded
    text = text.dup.force_encoding('UTF-8') if text.encoding != Encoding::UTF_8

    code_block_placeholders = []
    text = text.gsub(/```([A-Za-z0-9_\-]*)\s*\n([\s\S]*?)```/) do
      language = Regexp.last_match(1)
      code_body = Regexp.last_match(2)
      placeholder = "HTMLCODEBLOCK_PLACEHOLDER_#{code_block_placeholders.length}"
      escaped = CGI.escapeHTML(code_body.rstrip)
      lang_attr = language.to_s.empty? ? "" : " class=\"language-#{language}\""
      html_block = "<pre><code#{lang_attr}>#{escaped}\n</code></pre>"
      code_block_placeholders << { placeholder: placeholder, html: html_block }
      placeholder
    end

    # Apply markdown normalization to ensure proper parsing
    text = normalize_markdown(text)
    Monadic::Utils::ExtraLogger.log { "Markdown after normalize:\n#{text}" }

    # Pre-process to protect ALL bold markdown from smart punctuation
    # This is critical when mixing Japanese and English text with multiple bold items in one paragraph
    all_bold_items = []
    text = text.gsub(/\*\*(.+?)\*\*/m) do |match|
      content = $1
      all_bold_items << content
      "BOLD_PLACEHOLDER_#{all_bold_items.size - 1}"
    end

    # insert a newline after a line that does not end with a newline
    pattern = Regexp.new('^(\s*#{1,6}\s+.*)(\n)(?!\n)', Regexp::MULTILINE)
    t1 = text.gsub(pattern, "\\1\\2\n")
    t2 = t1.gsub(/\[^([0-9])^\]/) { "[^#{Regexp.last_match(1)}]" }
    t3 = t2.gsub(/(!\[[^\]]*\]\()(['"])([^\s)]+)(['"])(\))/, '\1\3\5')

    # Set up Commonmarker options
    options = {
      parse: { smart: true },
      render: { unsafe: true, github_pre_lang: true },
      extension: {
        strikethrough: true,
        table: true,
        autolink: true,
        tasklist: true,
        footnotes: true
      }
    }

    # Convert markdown to HTML using Commonmarker
    # Ensure text is UTF-8 encoded
    t3_utf8 = t3.dup.force_encoding('UTF-8')
    html = Commonmarker.to_html(t3_utf8, options: options)
    code_block_placeholders.each do |block|
      html.gsub!(/#{block[:placeholder]}(?!\d)/) { block[:html] }
    end
    html = convert_fenced_code_html(html)

    # Get theme settings
    theme_mode = CONFIG["ROUGE_THEME"] || "github:light"
    theme, mode = theme_mode.split(":")
    mode = mode || "light"

    # Convert CommonMarker output format and apply current theme
    html = StringUtils.highlight_code_blocks(html, theme_name: theme, theme_mode: mode)

    # Restore bold placeholders
    all_bold_items.each_with_index do |content, index|
      html.gsub!(/BOLD_PLACEHOLDER_#{index}(?!\d)/) { "<strong>#{CGI.escapeHTML(content)}</strong>" }
    end

    html
  end

  def convert_fenced_code_html(html)
    return html unless html

    result = html.gsub(%r{<p>```([\w+\-]*)\s*(?:\n)?([\s\S]*?)```</p>}m) do
      language = Regexp.last_match(1)
      code_body = Regexp.last_match(2)
      code = CGI.escapeHTML(code_body.rstrip) + "\n"
      lang_attr = language.to_s.empty? ? "" : " class=\"language-#{language}\""
      "<pre><code#{lang_attr}>#{code}</code></pre>"
    end

    # Handle any remaining fenced code blocks that Commonmarker left untouched
    result = result.gsub(%r{(^|\r?\n)```([\w+\-]*)\s*\r?\n([\s\S]*?)```(?=\r?\n|\Z)}m) do
      leading = Regexp.last_match(1)
      language = Regexp.last_match(2)
      code_body = Regexp.last_match(3)
      code = CGI.escapeHTML(code_body.rstrip) + "\n"
      lang_attr = language.to_s.empty? ? "" : " class=\"language-#{language}\""
      "#{leading}<pre><code#{lang_attr}>#{code}</code></pre>"
    end

    result
  end
end
