# frozen_string_literal: true

class SyntaxTreeGenerator < MonadicApp
  def icon
    "<i class='fas fa-tree'></i>"
  end

  def description
    ""
  end

  def initial_prompt
    text = <<~TEXT
      Analyze the user's message and create the syntactic parsing in the labeled bracketing format. Then run `draw_syntree` function with the labeled bracketing as the parameter to visualize the syntactic tree. The `draw_syntree` function will generate an image file and returns the file name if the RSyntaxTree tool is installed in the environment.

      The labeled bracketing format is a way to represent the syntactic structure of a sentence. It is a nested structure of labeled brackets, where the label is the part of speech or phrase type, and the content is the word or phrase itself. Below is the sentence "John loves Mary" represented in the labeled bracketing format.

[S
  [NP
    [NNP
      John
    ]
  ]
  [VP
    [VBZ
      loves
    ]
    [NP
      [NNP
        Mary
      ]
    ]
  ]
]

    It is extremely important that all the brackets are balanced. Make sure to check the validity of the labeled bracketing before running the `draw_syntree` function. If the labeled bracketing is not valid, the function will not generate the image. In that case, return an error message.

    Respond to the user's request in the following format. Note that the IMAGE_FILE_NAME is the name of the svg file that is returned from the `draw_syntree` function.

    <div class="sourcecode">
      <pre>
        <code>labeled bracketing (no trailing and leading spaces)</code>
      </pre>
    </div>

    <div class="generated_image">
      <img src="IMAGE_FILE_NAME" />
    </div>
    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Syntax Tree Generator",
      "model": "gpt-4-0125-preview",
      "image_generation": true,
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 1000,
      "context_size": 20,
      "sourcecode": true,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "initiate_from_assistant": false,
      "tools": [
        {
          "type": "function",
          "function":
          {
            "name": "draw_syntree",
            "description": "Draw the syntactic tree from the labeled bracketing.",
            "parameters": {
              "type": "object",
              "properties": {
                "text": {
                  "type": "string",
                  "description": "The labeled bracketing of the syntactic parsing"
                }
              },
              "required": ["text", "image_file_name"]
            }
          }
        }
      ]
    }
  end

  def draw_syntree(text: "")
    text = text.gsub('"', '\"')
    if IN_CONTAINER
      shared_volume = "/monadic/data/"
    else
      shared_volume = File.expand_path(File.join(Dir.home, "monadic", "data"))
    end

    image_file_name = Time.now.strftime("%Y%m%d%H%M%S") + ".svg"

    command1 = "rsyntaxtree -f svg -o #{shared_volume} \"#{text}\""
    send_command(command: command1, container: "ruby")

    command2 = "mv #{shared_volume}syntree.svg #{shared_volume}#{image_file_name}"
    send_command(command: command2, container: "ruby")

    command3 = "ls #{shared_volume}#{image_file_name}"
    send_command(command: command3, container: "ruby") do |stdout, stderr, status|
      if status.success? && /#{image_file_name}/ =~ stdout
        "The syntaxtree image file #{image_file_name} has been generated."
      else
        "Error occurred: the bracketing is not valid."
      end
    end
  end
end
