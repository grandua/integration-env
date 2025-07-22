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

# Apply EF Core Migrations from the host
Write-Host "Applying EF Core migrations..."
$ateraMcpPath = "..\..\AteraMcpServer"
if (Test-Path $ateraMcpPath) {
    Push-Location $ateraMcpPath
    dotnet ef database update --project AteraDb.DataAccess
    Pop-Location
} else {
    Write-Host "Error: AteraMcpServer project not found at $ateraMcpPath"
    exit 1
}

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
