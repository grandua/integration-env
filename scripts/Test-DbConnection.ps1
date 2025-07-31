$hostname = "localhost" # Use localhost as the script runs on the host machine and port 5432 is exposed
$port = 5432 # Fixed port

# Retrieve from environment variables
$dbName = $env:POSTGRES_DB
$dbUser = $env:POSTGRES_USER
$dbPassword = $env:POSTGRES_PASSWORD
$timeout = 1000  # milliseconds

# Test ping
Write-Output "Testing ping to $hostname ..."
$pingTask = Test-Connection -ComputerName $hostname -Count 1 -AsJob
if ($pingTask | Wait-Job -Timeout 5) {
    $pingResult = $pingTask | Receive-Job
    if ($pingResult.Status -eq 'Success') {
        Write-Output "Ping successful to $hostname"
    } else {
        Write-Output "Ping failed to $hostname"

    }
} else {
    Write-Output "Ping timed out to $hostname"

}

# Test TCP connection
$tcpClient = New-Object System.Net.Sockets.TcpClient
$connectTask = $tcpClient.ConnectAsync($hostname, $port)
if ($connectTask.Wait($timeout)) {
    if ($tcpClient.Connected) {
        Write-Output "TCP connection to $hostname`:$port successful"
        $tcpClient.Close()
    } else {
        Write-Output "TCP connection to $hostname`:$port failed"
        exit 1
    }
} else {
    Write-Output "TCP connection to $hostname`:$port timed out after $timeout ms"
    exit 1
}

# Check for ODBC driver
$drivers = Get-OdbcDriver | Where-Object { $_.Name -like "*PostgreSQL*" }
if (-not $drivers) {
    Write-Output "No PostgreSQL ODBC driver found. Please install it."
    exit 1
}

# Test database connection with ODBC
$conn = New-Object System.Data.Odbc.OdbcConnection
$conn.ConnectionString = "Driver={PostgreSQL Unicode};Server=$hostname;Port=$port;Database=$dbName;Uid=$dbUser;Pwd=$dbPassword;"
try {
    $conn.Open()
    Write-Output "Database connection successful!"
}
catch {
    Write-Output "Database connection failed: $_"
    exit 1
}
finally {
    $conn.Close()
}
