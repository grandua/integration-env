# Atera Integration Environment

This repository contains the orchestration logic to run the 
`AteraMcpServer` (AteraDb) and `AteraMindsDbMcpServer` (MindsDB) services 
together as a complete application stack. 
It is the single source of truth for both local development and CI/CD environment setup.

---

## Core Concept

This setup follows a standard microservices pattern 
where application code lives in separate service repositories (`AteraMcpServer`, `AteraMindsDbMcpServer`), 
and this `integration-env` repository only handles how they are built, 
configured, and run together.

- **For CI/CD & Production**: The `docker-compose.yml` file is used. It pulls version-tagged, pre-built images from a container registry.
- **For Local Development**: A `docker-compose.override.yml` file is used. This file tells Docker to build the services from your local source code, enabling rapid development without needing to push/pull images.

---

## Local Development Quick Start

**Prerequisites:**
- Docker Desktop installed and running.
- The following repositories cloned into a single parent directory:
  - `AteraMcpServer`
  - `AteraMindsDbMcpServer`
  - `integration-env` (this repository)

**One-Time Setup:**

1.  Navigate to the `integration-env` directory.
2.  Rename `docker-compose.override.yml.example` to `docker-compose.override.yml`. This file is ignored by Git and is specific to your local machine.

**Daily Workflow:**

1.  **Start the environment:**
    ```powershell
    # From the integration-env directory
    .\scripts\start-env.ps1
    ```
    This command will build the images from your local source code (on the first run), start the containers, and run the MindsDB configuration.

2.  **Run a smoke test:**
    ```powershell
    .\scripts\smoke-test.ps1
    ```
    This will query MindsDB and should return a list of tables from the `AteraDb` database.

3.  **Stop the environment:**
    ```powershell
    .\scripts\stop-env.ps1
    ```
    This command stops the containers and removes the data volume, ensuring a clean slate for the next startup.

---

## How It Works

- **`docker-compose.yml`**: The base file used by everyone. It defines the services, network, and volumes. For CI/CD, it pulls images like `ateracorp/atera-db:1.2.0`.

- **`docker-compose.override.yml`**: Your local-only file. Docker Compose automatically merges it with the base file. The `build` directives in the override tell Docker to ignore the `image` tags from the base file and build from your local source code paths instead (e.g., `../AteraMcpServer`).

- **`scripts/`**: Contains the helper scripts to automate the startup, shutdown, and testing of the environment, providing a consistent experience for all developers.
