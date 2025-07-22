# Stop and clean up the integration environment
Write-Host "Stopping AteraDb + MindsDB environment..."
docker compose down -v

# Forcefully remove any orphaned container with the same name to prevent conflicts
Write-Host "Checking for orphaned containers..."
$containerId = docker ps -a -q --filter "name=atera_postgres"
if ($containerId) {
    Write-Host "Found and removing orphaned container: atera_postgres ($containerId)"
    docker rm -f $containerId
}

$mindsdbContainerId = docker ps -a -q --filter "name=mindsdb_instance"
if ($mindsdbContainerId) {
    Write-Host "Found and removing orphaned container: mindsdb_instance ($mindsdbContainerId)"
    docker rm -f $mindsdbContainerId
}

Write-Host "Cleanup complete."
