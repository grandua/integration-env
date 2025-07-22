$payload = @{
    query = "SHOW TABLES FROM AteraDb;"
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri 'http://127.0.0.1:47334/api/sql/query' -Method Post -Body $payload -ContentType 'application/json'
    if ($response.data) {
        Write-Host "Smoke Test PASSED. Available tables:"
        $response.data | Format-Table
    } else {
        Write-Host "Smoke Test FAILED. No data returned."
        $response | ConvertTo-Json -Depth 5
    }
} catch {
    Write-Host "Smoke Test FAILED with an exception:"
    Write-Host $_.Exception.Message
    if ($_.Exception.Response) {
        $errorResponse = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $errorBody = $reader.ReadToEnd();
        Write-Host "Error Body: $errorBody"
    }
}
