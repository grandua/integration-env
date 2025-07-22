# Start the integration environment
Write-Host "Starting AteraDb + MindsDB environment..."
docker compose up -d

# Wait for health (optional enhancement)
Write-Host "Waiting for containers to be healthy..."
$healthy = $false
for ($i = 0; $i -lt 30; $i++) {
    $ps = docker ps --filter "health=healthy" --filter "name=atera_postgres" --format "{{.Names}}"
    $ms = docker ps --filter "status=running" --filter "name=mindsdb_instance" --format "{{.Names}}"
    if ($ps -and $ms) {
        Write-Host "All services are healthy."
        $healthy = $true
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $healthy) { 
    Write-Host "Warning: Not all services are healthy after timeout." 
    exit 1
}

# Apply EF Core migrations from the host to the container.
# We construct the connection string here and pass it directly to the tool.
# This is the most robust method as it overrides any appsettings.json configuration,
# ensuring the host-based tool connects to localhost where the container port is mapped.
Write-Host "Applying EF Core migrations..."
$ateraMcpServerProjectDir = Join-Path $PSScriptRoot "..\..\AteraMcpServer"
$connectionString = "Host=localhost;Port=5432;Database=atera_prod;Username=atera_user;Password=atera_password"

dotnet ef database update --project $ateraMcpServerProjectDir --startup-project $ateraMcpServerProjectDir --connection $connectionString

Write-Host "EF Core migrations applied successfully."

# Configure MindsDB
Write-Host "Configuring MindsDB..."
$configScriptPath = "..\..\AteraMindsDbMcpServer\deploy\mindsdb-config.ps1"
if (Test-Path $configScriptPath) {
    & $configScriptPath
} else {
    Write-Host "Error: Configuration script not found at $configScriptPath"
    exit 1
}

Write-Host "Environment is ready."
