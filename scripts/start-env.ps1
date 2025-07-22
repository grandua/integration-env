# Start the integration environment
Write-Host "Starting AteraDb + MindsDB environment..."
docker compose up -d

# Wait for health (optional enhancement)
Write-Host "Waiting for containers to be healthy..."
$healthy = $false
for ($i = 0; $i -lt 30; $i++) {
    $ps = docker ps --filter "health=healthy" --filter "name=postgres" --format "{{.Names}}"
    $ms = docker ps --filter "health=healthy" --filter "name=mindsdb_instance" --format "{{.Names}}"
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

# Add a retry loop to wait for the database to be ready to accept connections from the host.
# This prevents a race condition where the container is 'healthy' but not yet listening on the mapped port.
Write-Host "Waiting for PostgreSQL to be ready..."
$maxRetries = 15
$retryIntervalSeconds = 2
for ($i = 1; $i -le $maxRetries; $i++) {
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect('localhost', 5432)
        if ($tcpClient.Connected) {
            Write-Host "PostgreSQL is ready!"
            $tcpClient.Close()
            break
        }
    } catch {
        Write-Host "Attempt $i of ${maxRetries}: PostgreSQL not ready yet. Retrying in $retryIntervalSeconds seconds..."
        Start-Sleep -Seconds $retryIntervalSeconds
    }
    if ($i -eq $maxRetries) {
        Write-Error "Failed to connect to PostgreSQL after $maxRetries attempts. Aborting."
        exit 1
    }
}

$ateraMcpServerProjectDir = Join-Path $PSScriptRoot "..\..\AteraMcpServer"
$migrationsProject = Join-Path $ateraMcpServerProjectDir "AteraDb.DataAccess"
$connectionString = "Host=localhost;Port=5432;Database=AteraDb;Username=atera_user;Password=atera_password"

dotnet ef database update --project $migrationsProject --startup-project $migrationsProject --connection $connectionString

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
