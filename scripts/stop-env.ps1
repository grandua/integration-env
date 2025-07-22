# Stop and clean up the integration environment
Write-Host "Stopping AteraDb + MindsDB environment..."
docker compose down -v

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
