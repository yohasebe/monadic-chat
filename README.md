<p>&nbsp;</p>

<div align="center"><img src="./assets/images/monadic-chat.svg" width="500px"/></div>

<div align="center"><b>A highly configurable Ruby framework for creating intelligent chatbots </b></div>

<p>&nbsp;</p>
<p>&nbsp;</p>

> **Note**
> The command-line program Monadic Chat was renamed to **[Monadic Chat CLI](https://github.com/yohasebe/monadic-chat-cli)** and moved to a separate repository. Going forward, Monadic Chat will be developed as a web-based application on this repository.

<p>&nbsp;</p>
<div align="center"><img src="./assets/images/screenshot-01.png" width="100%"/></div>
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

- [Git](https://github.com/git-guides/install-git)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Google Chrome](https://www.google.com/chrome/) or [Microsoft Edge](https://www.microsoft.com/edge/)
- A terminal emulator app (i.e., Terminal.app for Mac, Windows Terminal for Windows)

### Setting Up

1. Start Docker Desktop

2. Open a terminal emulator app

2. Clone the git repository

    `git clone git@github.com:yohasebe/monadic-chat.git`

3. Change directory

    `cd monadic-chat`

4. Build Docker image

    `docker-compose build`

    Or, add `--no-cache` to rebuild the image without using cached data

    `docker-compose build --no-cache`

This will take some time when running for the first time

5. Build a Docker container and start

    `docker-compose up`

    Or, add `-d` to start the system in the background

    `docker-compose up -d`

6. Access with a web browser

    Access `http://localhost:4567` with Google Chrome or Microsoft Edge

### Shutting down

1. If the system is run in the foreground:

    Press `ctrl-c`

2. If the system is run in the background:

    Run `docker-compose stop`

### Uninstall the Docker container and image

Run `docker-compose rm`

## Author

Yoichiro HASEBE

[yohasebe@gmail.com](yohasebe@gmail.com)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
