<p>&nbsp;</p>

<div align="center"> <img src="./assets/images/monadic-chat-logo.png" width="600px"/></div>

<div align="center" style="color: #777777 "><b>A highly configurable Ruby framework for creating intelligent chatbots </b></div>

<p>&nbsp;</p>

> **Note**
>
> The command-line program Monadic Chat was renamed to **[Monadic Chat CLI](https://github.com/yohasebe/monadic-chat-cli)** and moved to a separate repository. Going forward, Monadic Chat will be developed as a web-based application on this repository.

- Monadic Chat: [https://github.com/yohasebe/monadic-chat](https://github.com/yohasebe/monadic-chat) (this repo)
- Monadic Chat CLI: [https://github.com/yohasebe/monadic-chat-cli](https://github.com/yohasebe/monadic-chat-cli)

<p>&nbsp;</p>
<div align="center"><img src="./assets/images/screenshot-01.png" width="800px"/></div>
<p>&nbsp;</p>

## About

**Monadic Chat** is a platform for creating and using AI assistant apps that can be easily accessed through a web browser using **OpenAI's Chat API**.

## Features

### General

- Uses **GPT-3.5** or **GPT-4** via OpenAI’s Chat API, with no limit on the number of conversation turns
- Easy to install using **Docker for Mac, Windows, or Linux**

### Data Storage and Retrieval

- Has functionalities to **export/import** messages
- Can specify the number of recent messages (**active messages**) to send to the API. Messages beyond the specified number (**inactive messages**) can be stored in the system and exported to an external file
- Can create **text embeddings** from data contained in multiple **PDF files** and make inquiries about their content (using OpenAI’s text embedding API)

### Voice Input and Output

- Can automatically transcribe messages from **microphone input** (using OpenAI’s Whisper API)
- Can use **text-to-speech** functionality to voice responses from the AI assistant
- Can specify the **language and voice** for text-to-speech functionality available on the browser being used (Google Chrome or Microsoft Edge)
- Can **automatically detect the language** of the message and play the text-to-speech accordingly
- Can combine speech recognition and text-to-speech functionality to enable **voice conversations** with the AI agent

### Chat Settings and Configuration

- Can easily define the character of the AI agent by specifying **API **parameters and the **system**** prompt****
- Can implement additional functionality using the **Ruby** programming language

###  Message Editing

- Can **edit previous messages** and try again when the expected response from the AI agent is not obtained
- Can **delete specific messages** from previous conversations
- Can **add past messages** specifying the role **user**, **assistant**, or **system**.

### Advanced

- Can obtain additional information in parallel with the AI assistant's primary response message and keep it within a predefined JSON object as the **conversation state**

## Installation

### Dependencies

Install the following software:

- [Git](https://github.com/git-guides/install-git)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Google Chrome](https://www.google.com/chrome/) or [Microsoft Edge](https://www.microsoft.com/edge/)
- A terminal emulator app (e.g., Terminal.app for Mac, Windows Terminal for Windows)

Also, you need an OpenAI API key. Note that it is does not come with a ChatGPT or ChatGPT Plus account. Sign up and get an API key at the [OpenAI API sign-up page](https://platform.openai.com/account/api-keys).

### Setting Up


1. Start Docker Desktop

2. Open a terminal emulator app

3. Clone the git repository

    `git clone git@github.com:yohasebe/monadic-chat.git`

4. Change directory

    `cd monadic-chat`

5. Build Docker image

    `docker-compose build`

    To rebuild the image without using cached data, add `--no-cache`:

    `docker-compose build --no-cache`

### Start Monadic Chat

Do as follows inside the `monadic-chat` folder:

1. To start the system in the foreground, run:

    `docker-compose up`

2. To start the system in the background, run: 

    `docker-compose up -d`

Then access `http://localhost:4567` with Google Chrome or Microsoft Edge

### Stop Monadic Chat

Do as follows inside the `monadic-chat` folder:

1. If the system is run in the foreground:

    Press `ctrl-c`

2. If the system is run in the background:

    `docker-compose stop`

### Update Monadic Chat

Do as follows inside the `monadic-chat` folder:

1. Stop the system and remove the Docker container with

    `docker-compose down`

2. Run `git pull`.

3. Then run `docker-compose build`.

### Uninstall the Docker container and image

Do as follows inside the `monadic-chat` folder:

Run `docker-compose rm`

### Import/Export Vector Database

Do as follows inside the `monadic-chat` folder:

**Export**

`docker-compose exec db pg_dump -U postgres -F t monadic > ~/Desktop/monadic.tar`

**Import**


## Base Apps

Currently, the following base apps are available for use. By selecting one of them and changing the parameters or rewriting the initial prompt, you can adjust the behavior of the AI agent. You can export/import the adjusted settings to/from an external JSON file.

### Chat

<img src="./assets/icons/chat.png" width="40px"/> This is the standard application for monadic chat. It can be used in basically the same way as ChatGPT.

### Language Practice

<img src="./assets/icons/language-practice.png" width="40px"/> This is a language learning application where conversations begin with the assistant's speech. The assistant's speech is played back in a synthesized voice. To speak, press the Enter key to start speech input, and press Enter again to stop speech input.

### Language Practice Plus

<img src="./assets/icons/language-practice-plus.png" width="40px"/> This is a language learning application where conversations start with the assistant’s speech. The assistant’s speech is played back in a synthesized voice. To speak, press the Enter key to start speech input, and press Enter again to stop speech input. The assistant’s response will include linguistic advice in addition to the usual content. The language advice is presented only as text and not as text-to-speech.

### Novel

<img src="./assets/icons/novel.png" width="40px"/> This is an application for collaboratively writing a novel with an assistant. The assistant writes a paragraph summarizing the theme, topic, or event presented in the prompt. Always use the same language as the assistant in your response.

### PDF Navigator

<img src="./assets/icons/pdf-navigator.png" width="40px"/> This is an application that reads a PDF file, and the assistant answers the user's questions based on its content. First, click on the "Upload PDF" button and specify the file. The content of the file will be divided into segments of approximately max_tokens length, and the text embedding will be calculated for each segment. When input is received from the user, the text segment that is closest to the text embedding value of the input text is given to GPT along with the user's input value, and an answer is generated based on that content.

### Translate

<img src="./assets/icons/translate.png" width="40px"/> The assistant will translate the user's input text into another language. First, the assistant will ask for the target language. Then, the input text will be translated into the target language. If you want the assistant to use a specific translation, please put parentheses after the relevant part of the input text and specify the translation in the parentheses.

### Voice Chat

<img src="./assets/icons/voice-chat.png" width="40px"/> This app enables users to chat using voice through OpenAI’s Whisper API and the browser’s text-to-speech API. The initial prompt is the same as the one for the Chat app. Please note that a web browser with the latter API, such as Google Chrome or Microsoft Edge, is required.

### Wikipedia

<img src="./assets/icons/wikipedia.png" width="40px"/> This is essentially the same as Chat, but for questions that GPT cannot answer, such as questions about events that occurred after the language model cutoff time, it searches Wikipedia to answer them. If the query is in a non-English language, the Wikipedia search is performed in English, and the results are translated into the original language.

### Linguistic Analysis

<img src="./assets/icons/linguistic-analysis.png" width="40px"/> This app utilizes Monadic Chat’s feature that allows for updating a pre-specified JSON object with multiple properties while providing a regular response. As the main response to the user’s query, it returns a syntactic structure of the input sentence. In the process, the app updates the values of the JSON object with the properties of `topic`, `sentence_type`, and `sentiment`.

## Creating New Apps

UNDER CONSTRUCTION

## Author

Yoichiro HASEBE

[yohasebe@gmail.com](yohasebe@gmail.com)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
