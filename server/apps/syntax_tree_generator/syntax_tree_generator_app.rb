# frozen_string_literal: false

class SyntaxTreeGenerator < MonadicApp
  attr_accessor :context

  def icon
    "<i class='fas fa-tree'></i>"
  end

  def description
    ""
  end

  def initial_prompt
    text = <<~TEXT
      Analyze the user's message and create the syntactic parsing in the labeled bracketing format. Then run `draw_syntree` function with the labeled bracketing and the svg IMAGE_FILE_NAME (e.g. john-loves-mary.svg) as the parameters to visualize the syntactic tree. It saves the svg file in the `/data` directory.

      The labeled bracketing format is a way to represent the syntactic structure of a sentence. It is a nested structure of labeled brackets, where the label is the part of speech or phrase type, and the content is the word or phrase itself. For example, the sentence "John loves Mary" is represented as:

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

    Respond to the user's request in the following format. Note that the IMAGE_FILE_NAME is the name of the svg file that will be generated from the labeled bracketing.

    <div class="sourcecode">
      <pre>
        <code>labeled bracketing (no trailing and leading spaces)</code>
      </pre>
    </div>

    <div class="generated_image">
      <img src="/data/IMAGE_FILE_NAME" />
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
      "context_size": 10,
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
                },
                "image_file_name": {
                  "type": "string",
                  "description": "The name of the image file that will be generated from the labeled bracketing."
                }
              },
              "required": ["text", "image_file_name"]
            }
          }
        }
      ]
    }
  end

  def draw_syntree(hash)
    text = hash[:text]
    text = text.gsub('"', '\"')
    image_file_name = hash[:image_file_name]
    shared_volume = "/monadic/data/"
    conda_container = "monadic-chat-conda-container"

    docker_command1 =<<~DOCKER
      docker exec -w #{shared_volume} #{conda_container} \
      rsyntaxtree -f svg -o #{shared_volume} "#{text}"
    DOCKER
    docker_command1 = docker_command1.strip
    stdout1, stderr1, status1 = Open3.capture3(docker_command1)
    if !status1.success?
      return "Error occurred " + stderr1
    end

    docker_command2 =<<~DOCKER
      docker exec -w #{shared_volume} #{conda_container} \
      mv #{shared_volume}syntree.svg #{shared_volume}#{image_file_name}
    DOCKER
    docker_command2 = docker_command2.strip
    stdout2, stderr2, status2 = Open3.capture3(docker_command2)
    if !status2.success?
      return "Error occurred " + stderr2
    end

    docker_command3 =<<~DOCKER
      docker exec -w #{shared_volume} #{conda_container} \
      ls #{shared_volume}#{image_file_name}
    DOCKER
    docker_command3 = docker_command3.strip
    stdout3, stderr3, status3 = Open3.capture3(docker_command3)
    if status3.success? && /#{image_file_name}/ =~ stdout3
      "The syntaxtree file #{image_file_name} has been generated."
    else
      "Error occurred: the bracketing is not valid."
    end
  end
end
