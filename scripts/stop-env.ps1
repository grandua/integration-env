# Stop and clean up the integration environment
Write-Host "Stopping AteraDb + MindsDB environment..."
# Note: Use "docker compose down -v" to reset Docker volume for DB to an empty DB
docker compose down

# Forcefully remove specific containers if they exist to prevent name conflicts
Write-Host "Checking for orphaned containers..."
$orphanedContainers = @("mindsdb_instance")
foreach ($container in $orphanedContainers) {
    if (docker ps -a --format '{{.Names}}' | Select-String -Quiet $container) {
        Write-Host "Found and removing orphaned container: $container"
        docker rm -f $(docker ps -a -q --filter "name=$container")
    }
}

Write-Host "Cleanup complete."
