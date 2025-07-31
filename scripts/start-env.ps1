# Start the integration environment
Write-Host "Starting AteraDb + MindsDB environment..."

# ------------------------------------------------------------
# 1. Load .env file so that PowerShell scripts have access to
#    POSTGRES_* variables that docker-compose passes to containers
# ------------------------------------------------------------
# .env sits in the integration-env folder (one level up from this script)
$envFilePath = Join-Path $PSScriptRoot "..\.env"
if (Test-Path $envFilePath) {
    Write-Host "Loading environment variables from $envFilePath"
    Get-Content $envFilePath | ForEach-Object {
        if ($_ -match '^[ ]*([^#][^=]*)=(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                Write-Host "  setting $name=$value"
                [System.Environment]::SetEnvironmentVariable($name, $value)
            }
        }
    }
} else {
    Write-Warning ".env file not found at $envFilePath; POSTGRES_* variables may be undefined for local scripts"
}

# Use the --wait flag to let Docker Compose handle waiting for healthy containers.
# This is the most reliable method and removes our brittle, manual polling loop.
docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Error "One or more containers failed to start or become healthy. Aborting."
    exit 1
}

Write-Host "All services are healthy."

# Apply EF Core migrations from the host to the container.
# We construct the connection string here and pass it directly to the tool.
# This is the most robust method as it overrides any appsettings.json configuration,
# ensuring the host-based tool connects to localhost where the container port is mapped.
Write-Host "Applying EF Core migrations..."

$ateraMcpServerProjectDir = Join-Path $PSScriptRoot "..\..\AteraMcpServer"
$migrationsProject = Join-Path $ateraMcpServerProjectDir "AteraDb.DataAccess"
$connectionString = "Host=localhost;Port=5432;Database=$env:POSTGRES_DB;Username=$env:POSTGRES_USER;Password=$env:POSTGRES_PASSWORD"

dotnet ef database update --project $migrationsProject --startup-project $migrationsProject --connection $connectionString

Write-Host "EF Core migrations applied successfully."

# Special handling for mindsdb_instance: allow it to start unhealthy so config can run
Write-Host "Waiting for mindsdb_instance to start (may be unhealthy initially)..."
$mindsdbContainer = "mindsdb_instance"
$timeoutSeconds = 120 # Give it some time to start up
$startTime = Get-Date

while ((Get-Date).Subtract($startTime).TotalSeconds -lt $timeoutSeconds) {
    $status = (docker inspect --format='{{.State.Status}}' $mindsdbContainer 2>$null).Trim()
    if ($status -eq "running") {
        Write-Host "Container $mindsdbContainer is running. Proceeding to configuration."
        break
    }
    Start-Sleep -Seconds 5
}

if ($status -ne "running") {
    Write-Error "Container $mindsdbContainer did not start within the timeout period. Aborting."
    exit 1
}

# Configure MindsDB
Write-Host "Configuring MindsDB..."
$configScriptPath = Join-Path $PSScriptRoot "mindsdb-config.ps1"
if (Test-Path $configScriptPath) {
    Write-Host "DEBUG (start-env.ps1): Calling mindsdb-config.ps1 with..."
    Write-Host "DEBUG (start-env.ps1): POSTGRES_DB = '$env:POSTGRES_DB'"
    Write-Host "DEBUG (start-env.ps1): POSTGRES_USER = '$env:POSTGRES_USER'"
    Write-Host "DEBUG (start-env.ps1): POSTGRES_PASSWORD = '$env:POSTGRES_PASSWORD'"
    & $configScriptPath
} else {
    Write-Host "Error: Configuration script not found at $configScriptPath"
    exit 1
}

# Wait for mindsdb_instance to become healthy after configuration
Write-Host "Waiting for mindsdb_instance to become healthy..."
$timeoutSeconds = 180 # Give it more time to become healthy after configuration
$startTime = Get-Date

while ((Get-Date).Subtract($startTime).TotalSeconds -lt $timeoutSeconds) {
    $healthStatus = (docker inspect --format='{{json .State.Health.Status}}' $mindsdbContainer 2>$null).Trim('"')
    if ($healthStatus -eq "healthy") {
        Write-Host "Container $mindsdbContainer is healthy." -ForegroundColor Green
        break
    }
    Write-Host "Container $mindsdbContainer health status: $healthStatus. Waiting..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
}

if ($healthStatus -ne "healthy") {
    Write-Error "Container $mindsdbContainer did not become healthy within the timeout period. Please check container logs for details." -ForegroundColor Red
    exit 1
}

Write-Host "Environment is ready." -ForegroundColor Green
