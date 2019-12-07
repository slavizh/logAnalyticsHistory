using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

try
{
    $workspaceName = '<the name of the workspace>'
    $workspaceResourceGroup = '<the resource group of the workspace.>'
    $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $workspaceResourceGroup -Name $workspaceName
    $query = 'Perf | where TimeGenerated between (startofmonth( startofmonth(now()) -1d)..(startofmonth(now()) -1d)) | where ObjectName == "Processor" | where CounterName == "% Processor Time"  | summarize  pct95CPU = percentile(CounterValue, 95), avgCpu = avg(CounterValue) by Computer, _ResourceId, bin(TimeGenerated, 31d)   | extend TimeStamp = strcat( format_datetime((startofmonth(now()) -1d), "yyyy-MM-dd"), "T", format_datetime((startofmonth(now()) -1d), "HH:mm:ss.fff"), "Z" ) | project TimeStamp, Computer, _ResourceId, ResourceId = _ResourceId ,pct95CPU, avgCpu'
    $queryOutput = Invoke-AzOperationalInsightsQuery -Workspace $workspace -Query $query
    $keys = Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $workspaceResourceGroup -Name $workspaceName -WarningAction SilentlyContinue
    $logType = "PerfHistory"
    $timestampField = "TimeStamp"
    $jsonResults = $queryOutput.Results | ConvertTo-Json -Depth 5
    $requestResult = Send-OMSAPIIngestionFile -customerId $workspace.CustomerId -sharedKey $keys.PrimarySharedKey -body $jsonResults -logType $logType -TimeStampField $timestampField
    if ($requestResult -eq 'Accepted')
    {
        $status = [HttpStatusCode]::OK
        $body = $requestResult
    }
    else
    {
        $status = [HttpStatusCode]::InternalServerError
        $body = $requestResult
    }
}
catch
{
    $body = $_.Exception.Message
    $status = [HttpStatusCode]::InternalServerError
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $status
    Body = $body
})
