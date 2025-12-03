# Monadic Chat

## Project Overview

Monadic Chat is a locally hosted web application for creating and utilizing intelligent chatbots. It provides a desktop application built with Electron that manages a Docker-based environment. The application is composed of multiple services that work together, including a Ruby server, a Python service, a PostgreSQL database with pgvector, a Selenium Grid, and Ollama for running large language models locally.

The application allows users to interact with AI models from various providers, with advanced features like voice interaction, image/video processing, and a PDF knowledge base. The conversations are stored locally, giving users full control over their data.

The main components of the project are:

*   **Electron App:** The desktop application that serves as the main entry point and management interface.
*   **Docker Environment:** A set of Docker containers that provide the backend services.
*   **Web Application:** A web-based UI that runs in an Electron webview and communicates with the backend services.

## Building and Running

### Prerequisites

*   Node.js and npm
*   Docker

### Development

To run the application in development mode, use the following command:

```bash
npm start
```

This will start the Electron application. From the application's UI, you can start the Docker environment by clicking the "Start" button. This will start all the necessary services. The web application will be available at `http://localhost:4567`.

### Building

To build the application for your platform, use the following commands:

*   **macOS (Apple Silicon):** `npm run build:mac-arm64`
*   **macOS (Intel):** `npm run build:mac-x64`
*   **Windows:** `npm run build:win`
*   **Linux (arm64):** `npm run build:linux-arm64`
*   **Linux (x64):** `npm run build:linux-x64`

The built application will be located in the `dist` directory.

### Testing

The project uses Jest for testing. There are two test modes:

*   **Unit tests (with mocks):**
    ```bash
    npm test
    ```
*   **UI tests (no mocks):**
    ```bash
    npm run test:no-mock
    ```

## Development Conventions

*   **Code Style:** The project uses ESLint for linting the JavaScript code. The configuration can be found in `.eslintrc.js`.
*   **Testing:** The project has a well-defined testing strategy with both unit and integration tests. The tests are located in the `test` directory.
*   **Branching:** The project uses a `main` branch for the latest stable version. Feature branches should be created from the `main` branch.
*   **Commits:** Commit messages should be clear and concise.
*   **Dependencies:** The project uses npm for managing dependencies. The dependencies are listed in the `package.json` file.
