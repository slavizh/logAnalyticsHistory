# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#
# You can define helper functions, run commands, or specify environment variables
# NOTE: any variables defined that are not environment variables will get reset after the first execution

# Authenticate with Azure PowerShell using MSI.
# Remove this if you are not planning on using MSI or Azure PowerShell.
if ($env:MSI_SECRET -and (Get-Module -ListAvailable Az.Accounts)) {
    Connect-AzAccount -Identity
}

$ErrorActionPreference = "Stop"

Function Get-OMSAPISignature
{
    Param
    (
        [Parameter(Mandatory = $True)]$customerId,
        [Parameter(Mandatory = $True)]$sharedKey,
        [Parameter(Mandatory = $True)]$date,
        [Parameter(Mandatory = $True)]$contentLength,
        [Parameter(Mandatory = $True)]$method,
        [Parameter(Mandatory = $True)]$contentType,
        [Parameter(Mandatory = $True)]$resource
    )

    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}

Function Send-OMSAPIIngestionFile
{
    Param
    (
        [Parameter(Mandatory = $True)]$customerId,
        [Parameter(Mandatory = $True)]$sharedKey,
        [Parameter(Mandatory = $True)]$body,
        [Parameter(Mandatory = $True)]$logType,
        [Parameter(Mandatory = $False)]$TimeStampField,
        [Parameter(Mandatory = $False)]$ResourceId,
        [Parameter(Mandatory = $False)]$EnvironmentName
    )

    #<KR> - Added to encode JSON message in UTF8 form for double-byte characters
    $body=[Text.Encoding]::UTF8.GetBytes($body)

    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Get-OMSAPISignature `
     -customerId $customerId `
     -sharedKey $sharedKey `
     -date $rfc1123date `
     -contentLength $contentLength `
     -method $method `
     -contentType $contentType `
     -resource $resource
    if($EnvironmentName -eq "AzureUSGovernment")
    {
        $Env = ".ods.opinsights.azure.us"
    }
    Else
    {
        $Env = ".ods.opinsights.azure.com"
    }
    $uri = "https://" + $customerId + $Env + $resource + "?api-version=2016-04-01"

    if ($TimeStampField.length -gt 0)
    {
        if ($ResourceId.length -gt 0)
        {
            $headers = @{
                "Authorization" = $signature;
                "Log-Type" = $logType;
                "x-ms-date" = $rfc1123date;
                "time-generated-field"=$TimeStampField;
                "x-ms-AzureResourceId"=$ResourceId;
            }
        }
        else
        {
            $headers = @{
                "Authorization" = $signature;
                "Log-Type" = $logType;
                "x-ms-date" = $rfc1123date;
                "time-generated-field"=$TimeStampField;
            }
        }
    }
    else {
        if ($ResourceId.length -gt 0)
        {
            $headers = @{
                "Authorization" = $signature;
                "Log-Type" = $logType;
                "x-ms-date" = $rfc1123date;
                "x-ms-AzureResourceId"=$ResourceId;
            }
        }
        else
        {
            $headers = @{
                "Authorization" = $signature;
                "Log-Type" = $logType;
                "x-ms-date" = $rfc1123date;
            }
        }
    }
    $response = Invoke-WebRequest `
        -Uri $uri `
        -Method $method `
        -ContentType $contentType `
        -Headers $headers `
        -Body $body `
        -UseBasicParsing `
        -verbose

    if ($response.StatusCode -ge 200 -and $response.StatusCode -le 299)
    {
        write-output 'Accepted'
    }
    else
    {
        Write-Output $response.StatusCode
    }
}
# Uncomment the next line to enable legacy AzureRm alias in Azure PowerShell.
# Enable-AzureRmAlias

# You can also define functions or aliases that can be referenced in any of your PowerShell functions.
