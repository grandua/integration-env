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

---

## Troubleshooting and Maintenance Notes

This section documents key lessons learned from debugging the Docker environment. Understanding these points will help with future maintenance and troubleshooting.

### 1. Verifying Container Health Checks

**Issue:** The `mindsdb_instance` container was reported as `unhealthy` by Docker, but the startup script didn't stop, leading to subsequent failures.

**Root Cause & Lessons Learned:**

*   **Health check endpoints are not standardized.** The original `docker-compose.yml` used `/api/health`, which returned a `404 Not Found`. The correct endpoint for this MindsDB image was the root URL (`/`).
*   **Don't trust logs alone.** The container logs showed a successful application startup, which was misleading. The health check is a separate mechanism that must be validated independently.
*   **How to Debug:** The most effective way to solve this was to execute the health check command directly inside the running container: `docker exec mindsdb_instance curl -f http://localhost:47334/`. This immediately revealed the `404` error.

### 2. Writing Robust Automation Scripts

**Issue:** The `start-env.ps1` script continued to execute even after the `docker compose` command reported that the MindsDB container was unhealthy.

**Root Cause & Lessons Learned:**

*   **Always check exit codes.** Automation scripts must check the exit code of critical commands (like `docker compose up`). In PowerShell, this is done by checking the `$LASTEXITCODE` variable immediately after the command. This ensures the script "fails fast" and provides a clear error instead of continuing in a broken state.

### 3. Creating Reliable File Paths in Scripts

**Issue:** The `start-env.ps1` script failed with a "Configuration script not found" error.

**Root Cause & Lessons Learned:**

*   **Avoid fragile relative paths.** The script used a hardcoded relative path (`..\..\...`) which only works if the script is run from a specific directory. 
*   **Use script-relative path variables.** The fix was to use PowerShell's built-in `$PSScriptRoot` variable to construct a reliable path from the script's own location: `Join-Path $PSScriptRoot "..\..\path\to\file.ps1"`. This makes the script runnable from anywhere.

### 4. Handling Shell-Specific Syntax

**Issue:** The standalone `Start-MindsDb.bat` script failed with a `bad format of filter` error.

**Root Cause & Lessons Learned:**

*   **Quoting rules differ between shells.** The `docker ps -f name=...` command works in a direct PowerShell or Bash terminal, but the Windows Command Prompt (in a `.bat` file) requires quotes around the filter value (`"name=..."`) when used inside a `for` loop. This is a common source of errors in batch scripts.
