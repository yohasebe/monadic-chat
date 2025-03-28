# frozen_string_literal: true

module StringUtils
  # Custom theme wrapper that removes background colors
  class DarkThemeFixer
    # Theme background color mapping
    THEME_BACKGROUNDS = {
      "monokai" => "#272822",
      "monokai_sublime" => "#272822",
      "base16" => "#151515",
      "gruvbox" => "#282828",
      "molokai" => "#1b1d1e",
      "colorful" => "#222222",
      "tulip" => "#2d2d2d",
      "thankful_eyes" => "#2a2a2a"
    }
    
    def initialize(theme, theme_name)
      @theme = theme
      @theme_name = theme_name
    end
    
    def render(scope: "")
      # Get the original CSS
      css = @theme.render(scope: scope)
      
      # Get appropriate background color for this theme (default to a dark gray if unknown)
      bg_color = THEME_BACKGROUNDS[@theme_name] || "#282c34"
      
      # Preserve the theme's background color but make token backgrounds transparent
      css += "\n/* Fix for dark theme backgrounds */\n"
      
      # Only add specific background if we have it in our mapping
      if THEME_BACKGROUNDS.key?(@theme_name)
        css += "\n#{scope} { background-color: #{bg_color} !important; }\n"
      end
      
      # Ensure all tokens and code elements have transparent background while preserving foreground colors
      css += <<~CSS
        #{scope} span, #{scope} pre, #{scope} code, pre#{scope} code { background-color: transparent !important; }
      CSS
      
      css
    end
  end

  module_function

  # language detection using CLD gem
  def detect_language(text)
    CLD.detect_language(text)[:code]
  end

  def normalize_markdown(text)
    # Add blank lines around ordered lists
    t1 = text.gsub(/(\S+)\n(\d+\. )/, "\\1\n\n\\2")
             .gsub(/(\d+\. .*)\n(\S+)/, "\\1\n\n\\2")

    # Add blank lines around code blocks
    t2 = t1.gsub(/(\S+)\n(```\w*)/, "\\1\n\n\\2")
           .gsub(/(\n```)\n(\S+)/, "\\1\n\n\\2")

    # Add blank lines around headers
    t3 = t2.gsub(/(\S+)\n(#+\s)/, "\\1\n\n\\2")

    # Add blank lines around blockquotes
    t4 = t3.gsub(/(\S+)\n(> )/, "\\1\n\n\\2")

    # Remove multiple blank lines (more than 2)
    t4.gsub(/\n{3,}/, "\n\n")
  end

  def markdown_to_html(text, mathjax: false)
    # if text is not a String, return a string representation of it
    return text.to_s unless text.is_a?(String)

    # insert a newline after a line that does not end with a newline
    pattern = Regexp.new('^(\s*#{1,6}\s+.*)(\n)(?!\n)')
    t1 = text.gsub(pattern, "\\1\\2\n")
    t2 = t1.gsub(/\[^([0-9])^\]/) { "[^#{Regexp.last_match(1)}]" }
    t3 = t2.gsub(/(!\[[^\]]*\]\()(['"])([^\s)]+)(['"])(\))/, '\1\3\5')

    if mathjax
      # Arrays to store the mathjax codes
      block_mathjax = []
      inline_mathjax = []

      # Replace $$...$$ with placeholders
      t4 = t3.gsub(/\$\$(.*?)\$\$/m) do
        block_mathjax << Regexp.last_match(1)
        "BLOCK_MATHJAX_PLACEHOLDER_#{block_mathjax.size - 1}"
      end

      # Replace $...$ with placeholders
      t5 = t4.gsub(/\$(.*?)\$/m) do
        inline_mathjax << Regexp.last_match(1)
        "INLINE_MATHJAX_PLACEHOLDER_#{inline_mathjax.size - 1}"
      end

      # Convert markdown to HTML using Kramdown
      html = Kramdown::Document.new(t5,
                                    syntax_highlighter: :rouge,
                                    input: "GFM",
                                    syntax_highlighter_ops: {
                                      guess_lang: true
                                    }).to_html.gsub(/(?:\\)+n/) { "\n" }

      # add an extra backslash to the backslash in the mathjax code in inline_mathjax
      inline_mathjax.map! do |code|
        code.gsub(/(?:\r)+/, "\\r")
            .gsub(/(?:\t)+/, "\\t")
      end

      # Replace placeholders with the original mathjax codes
      block_mathjax.each_with_index do |code, index|
        html.gsub!("BLOCK_MATHJAX_PLACEHOLDER_#{index}", "$$#{code}$$")
      end

      inline_mathjax.each_with_index do |code, index|
        html.gsub!("INLINE_MATHJAX_PLACEHOLDER_#{index}", "$#{code}$")
      end
    else
      html = Kramdown::Document.new(t3,
                                    syntax_highlighter: :rouge,
                                    input: "GFM",
                                    syntax_highlighter_ops: {
                                      guess_lang: true
                                    }).to_html

    end

    theme_mapping = {
      "base16" => "Base16",
      "bw" => "BlackWhiteTheme",
      "monokai_sublime" => "MonokaiSublime",
      "igor_pro" => "IgorPro",
      "thankful_eyes" => "ThankfulEyes"
    }

    theme_mode = CONFIG["ROUGE_THEME"] || "pastie:light"

    theme, mode = theme_mode.split(":")
    mode = mode || "dark"

    theme_class = theme_mapping[theme] || theme.capitalize

    case theme
    when "base16", "github", "gruvbox"
      if mode == "dark"
        Rouge::Themes.const_get(theme_class).dark!
      else
        Rouge::Themes.const_get(theme_class).light!
      end
    end


    # Setup formatter and determine if this is a dark theme
    formatter = Rouge::Formatters::HTML.new(css_class: "highlight", inline_theme: theme)
    is_dark_theme = mode == "dark"
    
    # Get theme object and apply fixes for dark themes if needed
    theme_obj = Rouge::Themes.const_get(theme_class)
    if is_dark_theme
      # Use our custom theme fixer for dark themes
      wrapped_theme = StringUtils::DarkThemeFixer.new(theme_obj, theme)
      css = wrapped_theme.render(scope: ".highlight")
    else
      # Normal theme rendering for light themes
      css = theme_obj.render(scope: ".highlight")
    end

    <<~HTML
    <style>
    #{css}
    </style>
    #{html}
    HTML
  end
end
