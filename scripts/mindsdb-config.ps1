# Configure MindsDB after container start (idempotent)
param(
    [string]$ApiHost = "127.0.0.1",
    [int]$Port = 47334
)

$baseApiUrl = "http://${ApiHost}:$Port/api"
$dbConnectionName = "atera_prod"
$agentName = "atera_agent"

# --- Wait for MindsDB API to be ready ---
Write-Host "Waiting for MindsDB API to be ready at $baseApiUrl/databases/$dbConnectionName..."
$maxRetries = 30
$retryDelaySeconds = 5
$retries = 0
$apiReady = $false

do {
    try {
        Invoke-RestMethod -Uri "$baseApiUrl/databases/$dbConnectionName" -Method Get -TimeoutSec 5 -ErrorAction Stop | Out-Null
        $apiReady = $true
        Write-Host "MindsDB API is ready and database connection '$dbConnectionName' already exists."
    } catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
            $apiReady = $true
            Write-Host "MindsDB API is ready but database connection '$dbConnectionName' not yet created."
        } else {
            $retries++
            Write-Host "MindsDB API not ready (attempt $retries/$maxRetries). Waiting $retryDelaySeconds seconds..."
            Start-Sleep -Seconds $retryDelaySeconds
        }
    }
} while (-not $apiReady -and $retries -lt $maxRetries)

if (-not $apiReady) {
    Write-Error "MindsDB API did not become ready after $maxRetries attempts. Exiting."
    exit 1
}

# --- 0. Drop Existing Database Connection (Force Recreation) ---
Write-Host "Attempting to drop existing DB connection: $dbConnectionName..."
try {
    Invoke-RestMethod -Uri "$baseApiUrl/databases/$dbConnectionName" -Method Delete -ErrorAction Stop | Out-Null
    Write-Host "DB connection '$dbConnectionName' dropped successfully."
} catch {
    if ($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
        Write-Host "DB connection '$dbConnectionName' not found. No need to drop."
    } else {
        Write-Warning "Failed to drop DB connection '$dbConnectionName': $($_.Exception.Message)"
    }
}

# --- 1. Create Database Connection (Idempotent) ---
Write-Host "Checking for existing DB connection: $dbConnectionName..."

try {
    Invoke-RestMethod -Uri "$baseApiUrl/databases/$dbConnectionName" -Method Get | Out-Null
    Write-Host "DB connection '$dbConnectionName' already exists. Skipping creation."
} catch {
    if ($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
        Write-Host "DB connection not found. Creating..."
        Write-Host "DEBUG (mindsdb-config.ps1): POSTGRES_DB = '$env:POSTGRES_DB'"
        Write-Host "DEBUG (mindsdb-config.ps1): POSTGRES_USER = '$env:POSTGRES_USER'"
        Write-Host "DEBUG (mindsdb-config.ps1): POSTGRES_PASSWORD = '$env:POSTGRES_PASSWORD'"
        $payloadObj = @{
            database = @{
                name   = $dbConnectionName
                engine = "postgres"
                parameters = @{
                    host     = "postgres" # Docker service name
                    database = "$env:POSTGRES_DB"
                    user     = "$env:POSTGRES_USER"
                    password = "$env:POSTGRES_PASSWORD"
                    port     = 5432
                }
            }
        }
        $body = $payloadObj | ConvertTo-Json -Depth 6
        Write-Host "Payload being sent to /databases endpoint:"
        Write-Host $body

        try {
            $response = Invoke-RestMethod -Uri "$baseApiUrl/databases/" -Method Post -Body $body -ContentType 'application/json'
            Write-Host "SUCCESS: Database connection '$dbConnectionName' created."
            Write-Host "MindsDB API Response:"
            $response | ConvertTo-Json -Depth 10 | Write-Host
        } catch {
            Write-Error "FAILED to create database connection '$dbConnectionName': $($_.Exception.Message)"
            if ($_.Exception.Response) {
                $errorResponse = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorResponse)
                $responseBody = $reader.ReadToEnd()
                Write-Error "MindsDB API Error Response Body: $responseBody"
            }
            throw "Failed to create database connection in MindsDB."
        }
    } else {
        throw "Failed to check for existing DB connection: $($_.Exception.Message)"
    }
}

# --- 2. Drop Existing Agent (to force recreation of agent and skills) ---
Write-Host "Attempting to drop existing agent: $agentName to ensure latest skills are applied..."
try {
    # We don't need to check if it exists first. A 404 on DELETE is not a failure.
    Invoke-RestMethod -Uri "$baseApiUrl/models/$agentName" -Method Delete -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Agent '$agentName' dropped if it existed. Proceeding to creation."
} catch {
    # Even if there's an error, we can proceed, as the creation step will likely fail if the agent is in a bad state.
    Write-Warning "An error occurred while trying to drop agent '$agentName': $($_.Exception.Message). Continuing to creation step..."
}

# --- 3. Create Agent and Skills ---
Write-Host "Creating Agent and Skills from SQL file..."
$sqlScriptPath = Join-Path $PSScriptRoot "..\..\AteraMindsDbMcpServer\deploy\create-mindsdb-agents-and-skills.sql"
$executeSqlScriptPath = Join-Path $PSScriptRoot "..\..\AteraMindsDbMcpServer\scripts\Execute-MindsDbSqlScript.ps1"

if (Test-Path $sqlScriptPath) {
    if (Test-Path $executeSqlScriptPath) {
        & $executeSqlScriptPath -SqlFilePath $sqlScriptPath
        Write-Host "MindsDB Agents and Skills creation process initiated successfully."
    } else {
        Write-Error "Execute-MindsDbSqlScript.ps1 not found at $executeSqlScriptPath"
        exit 1
    }
} else {
    Write-Error "create-mindsdb-agents-and-skills.sql not found at $sqlScriptPath"
    exit 1
}

# Check for existing skills and create if not present
$skillsToCreate = @(
    "atera_tickets_skill",
    "atera_agents_skill",
    "atera_customers_skill",
    "atera_devices_skill"
)

foreach ($skillName in $skillsToCreate) {
    Write-Host "Checking for existing skill: $skillName..."
    $skillExists = $false
    try {
        $skillQueryResult = Invoke-RestMethod -Uri "$baseApiUrl/sql/query" -Method Post -Body (@{ query = "SHOW SKILLS;" } | ConvertTo-Json) -ContentType 'application/json'
        if ($skillQueryResult.data | Where-Object { $_[0] -eq $skillName }) {
            $skillExists = $true
        }
    } catch {
        Write-Warning "Could not check for existing skill: $($_.Exception.Message)"
    }

    if ($skillExists) {
        Write-Host "Skill '$skillName' already exists. Skipping creation."
    } else {
        Write-Host "Skill '$skillName' not found. Please re-run the full setup to create missing skills."
        # Note: We don't attempt to create individual skills here as they are part of the main SQL script.
        # The user will need to re-run the full setup if skills are missing and the agent was not created.
    }
}
