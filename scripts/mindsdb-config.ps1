# Configure MindsDB after container start (idempotent)
param(
    [string]$ApiHost = "127.0.0.1",
    [int]$Port = 47334,
    [switch]$ForceRecreate
)

$baseApiUrl = "http://${ApiHost}:$Port/api"
$dbConnectionName = "atera_prod"
$agentName = "atera_agent"

# DRY: Define all key paths at the top
$deployDir = Join-Path $PSScriptRoot "..\..\AteraMindsDbMcpServer\deploy"
$scriptsDir = Join-Path $PSScriptRoot "..\..\AteraMindsDbMcpServer\scripts"
$dropSqlScriptPath = Join-Path $deployDir "drop-mindsdb-agents-and-skills.sql"
$createSqlScriptPath = Join-Path $deployDir "create-mindsdb-agents-and-skills.sql"
$executeSqlScriptPath = Join-Path $scriptsDir "Execute-MindsDbSqlScript.ps1"

# --- Check for required env vars ---
$requiredEnvVars = @("POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD")
foreach ($var in $requiredEnvVars) {
    if (-not (Get-Item "Env:$var").Value) {
        Write-Error "Required environment variable '$var' is not set. Aborting."
        exit 1
    }
}

# --- Wait for MindsDB API to be ready ---
Write-Verbose "Waiting for MindsDB API to be ready at $baseApiUrl/databases/$dbConnectionName..."
$maxRetries = 30
$retryDelaySeconds = 5
$retries = 0
$apiReady = $false

do {
    try {
        Invoke-RestMethod -Uri "$baseApiUrl/databases/$dbConnectionName" -Method Get -TimeoutSec 5 -ErrorAction Stop | Out-Null
        $apiReady = $true
        Write-Verbose "MindsDB API is ready and database connection '$dbConnectionName' already exists."
    } catch {
        $resp = $_.Exception.Response
        if ($resp -and $resp.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
            $apiReady = $true
            Write-Verbose "MindsDB API is ready but database connection '$dbConnectionName' not yet created."
        } else {
            $retries++
            Write-Verbose "MindsDB API not ready (attempt $retries/$maxRetries). Waiting $retryDelaySeconds seconds..."
            Start-Sleep -Seconds $retryDelaySeconds
        }
    }
} while (-not $apiReady -and $retries -lt $maxRetries)

if (-not $apiReady) {
    Write-Error "MindsDB API did not become ready after $maxRetries attempts. Exiting."
    exit 1
}

if ($ForceRecreate) {
    Write-Information "Attempting to drop existing DB connection: $dbConnectionName..." -InformationAction Continue
    try {
        Invoke-RestMethod -Uri "$baseApiUrl/databases/$dbConnectionName" -Method Delete -ErrorAction Stop | Out-Null
        Write-Information "DB connection '$dbConnectionName' dropped successfully." -InformationAction Continue
    } catch {
        $resp = $_.Exception.Response
        if ($resp -and $resp.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
            Write-Verbose "DB connection '$dbConnectionName' not found. No need to drop."
        } else {
            Write-Warning "Failed to drop DB connection '$dbConnectionName': $($_.Exception.Message)"
        }
    }
}

# --- 1. Create Database Connection (Idempotent) ---
Write-Verbose "Checking for existing DB connection: $dbConnectionName..."

try {
    Invoke-RestMethod -Uri "$baseApiUrl/databases/$dbConnectionName" -Method Get | Out-Null
    Write-Verbose "DB connection '$dbConnectionName' already exists. Skipping creation."
} catch {
    $resp = $_.Exception.Response
    if ($resp -and $resp.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
        Write-Information "DB connection not found. Creating..." -InformationAction Continue
        Write-Verbose "DEBUG (mindsdb-config.ps1): POSTGRES_DB = '$((Get-Item "Env:POSTGRES_DB").Value)'"
        Write-Verbose "DEBUG (mindsdb-config.ps1): POSTGRES_USER = '$((Get-Item "Env:POSTGRES_USER").Value)'"
        Write-Verbose "DEBUG (mindsdb-config.ps1): POSTGRES_PASSWORD = '$((Get-Item "Env:POSTGRES_PASSWORD").Value)'"
        $payloadObj = @{
            database = @{
                name   = $dbConnectionName
                engine = "postgres"
                parameters = @{
                    host     = "postgres" # Docker service name
                    database = "$((Get-Item "Env:POSTGRES_DB").Value)"
                    user     = "$((Get-Item "Env:POSTGRES_USER").Value)"
                    password = "$((Get-Item "Env:POSTGRES_PASSWORD").Value)"
                    port     = 5432
                }
            }
        }
        $body = $payloadObj | ConvertTo-Json -Depth 6
        Write-Verbose "Payload being sent to /databases endpoint: $body"

        try {
            $response = Invoke-RestMethod -Uri "$baseApiUrl/databases/" -Method Post -Body $body -ContentType 'application/json'
            Write-Information "SUCCESS: Database connection '$dbConnectionName' created." -InformationAction Continue
            $response | ConvertTo-Json -Depth 10 | Write-Verbose
        } catch {
            Write-Error "FAILED to create database connection '$dbConnectionName': $($_.Exception.Message)"
            $resp = $_.Exception.Response
            if ($resp) {
                $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $responseBody = $reader.ReadToEnd()
                Write-Error "MindsDB API Error Response Body: $responseBody"
            }
            throw "Failed to create database connection in MindsDB."
        }
    } else {
        throw "Failed to check for existing DB connection: $($_.Exception.Message)"
    }
}

# --- 2. Create Agents and Skills (Idempotent) ---
Write-Verbose "Checking for existing agent: $agentName..."

if ($ForceRecreate) {
    Write-Information "Attempting to drop existing agent and skills..." -InformationAction Continue
    if ((Test-Path $dropSqlScriptPath) -and (Test-Path $executeSqlScriptPath)) {
        & $executeSqlScriptPath -SqlFilePath $dropSqlScriptPath
        Write-Information "Existing MindsDB Agents and Skills dropped (if they existed)." -InformationAction Continue
    } else {
        Write-Warning "Cannot drop existing agents/skills. Missing: $dropSqlScriptPath or $executeSqlScriptPath."
    }
}

$agentExists = $false
try {
    $agentQueryResult = Invoke-RestMethod -Uri "$baseApiUrl/sql/query" -Method Post -Body (@{ query = "SHOW AGENTS;" } | ConvertTo-Json) -ContentType 'application/json'
    if ($agentQueryResult.data | Where-Object { $_[0] -eq $agentName }) {
        $agentExists = $true
    }
} catch {
    Write-Warning "Could not check for existing agent: $($_.Exception.Message)"
}

if ($agentExists) {
    Write-Verbose "Agent '$agentName' already exists. Skipping creation."
} else {
    Write-Information "Agent not found. Creating..." -InformationAction Continue
    if ((Test-Path $createSqlScriptPath) -and (Test-Path $executeSqlScriptPath)) {
        & $executeSqlScriptPath -SqlFilePath $createSqlScriptPath
        Write-Information "MindsDB Agents and Skills creation process initiated." -InformationAction Continue
    } else {
        Write-Error "Cannot create agents/skills. Missing: $createSqlScriptPath or $executeSqlScriptPath."
        exit 1
    }
}

# Check for existing skills and create if not present
$skillsToCreate = @(
    "atera_tickets_skill",
    "atera_agents_skill",
    "atera_customers_skill",
    "atera_devices_skill"
)

foreach ($skillName in $skillsToCreate) {
    Write-Verbose "Checking for existing skill: $skillName..."
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
        Write-Verbose "Skill '$skillName' already exists. Skipping creation."
    } else {
        Write-Warning "Skill '$skillName' not found. Please re-run the full setup to create missing skills."
        # Note: We don't attempt to create individual skills here as they are part of the main SQL script.
        # The user will need to re-run the full setup if skills are missing and the agent was not created.
    }
}
