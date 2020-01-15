param(
    [Parameter(mandatory=$true)]
    [string] $emailAddress,

    [Parameter(mandatory=$true)]
    [string] $domainName,

    [Parameter(mandatory=$true)]
    [string] $storageAccountResourceGroupName,

    [Parameter(mandatory=$true)]
    [string] $storageAccountName,

    [Parameter(mandatory=$true)]
    [string] $blobContainerName,

    [Parameter(mandatory=$true)]
    [string] $appGatewayResourceGroupName,

    [Parameter(mandatory=$true)]
    [string] $appGatewayName,

    [Parameter(mandatory=$true)]
    [string] $certificateName,

    [Parameter(mandatory=$false)]
    [string] $stagingMode
)

$connectionName = "AzureRunAsConnection"
try {
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
} catch {
    if (!$servicePrincipalConnection) {
        $errorMessage = "Connection $connectionName not found."
        throw $errorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

# Select the appropriate server
if ($stagingMode) {
    Write-Output "Setting server to LetsEncrypt staging"
    Set-PAServer LE_STAGE
} else {
    Write-Output "Setting server to LetsEncrypt production"
    Set-PAServer LE_PROD
}

# Create new account and order
Write-Output "Creating new account and order for domain $domainName and email address $emailAddress"
New-PAAccount -AcceptTOS -Contact $emailAddress -KeyLength 2048 -Force
New-PAOrder $domainName -Force

# Get authorizations
Write-Output "Retrieving authorizations for HTTP01"
$auths = Get-PAOrder | Get-PAAuthorizations
$authData = $auths | Select @{L='Body';E={Get-KeyAuthorization $_.HTTP01Token (Get-PAAccount)}},
                            @{L='FileName';E={$($_.HTTP01Token)}}



# Set local file path for blob
$filePath = $env:TEMP + "\" + $authData.FileName
Write-Output "Local file path set to $filePath"

# Create acme-challenge file
Write-Output "Writing authData to $filePath"
Set-Content -Value $authData.Body -Path $filePath

# Upload acme-challenge file to blob storage
Write-Output "Connecting to $storageAccountName"
$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $storageAccountResourceGroupName -Name $storageAccountName
$blobName = ".well-known\acme-challenge\" + $authData.FileName
$blobContext = $storageAccount.Context
Write-Output "Creating blob $blobName in context $blobContext"
Set-AzureStorageBlobContent -File $filePath -Container $blobContainerName -Context $blobContext -Blob $blobName

# Send challenge
Write-Output "Sending challenge"
$auths.HTTP01Url | Send-ChallengeAck

# Sane waiting period for challenge
Write-Output "Waiting for challenge validation (60s)"
Start-Sleep -s 60

# Store certificate in variable
Write-Output "Storing certificate with domain $domainName to variable certificateData"
$certificateData = New-PACertificate $domainName

# Remove storage 
Write-Output "Removing blob $blobName from container $blobContainerName"
Remove-AzureStorageBlob -Container $blobContainerName -Context $blobContext -Blob $blobName

# Define App Gateway
Write-Output "Using App Gateway $appGatewayName"
$appGateway = Get-AzureRmApplicationGateway -ResourceGroupName $appGatewayResourceGroupName -Name $appGatewayName

# Retrieve list of current App Gateway certificates
$certificateList = $(Get-AzureRmApplicationGatewaySslCertificate -ApplicationGateway $appGateway).Name
Write-Output "Available certificates on $($appGatewayName): `n $($certificateList)"

if ($certificateList -contains $certificateName) {
    Write-Output "Updating existing certificate $certificateName"
    Set-AzureRmApplicationGatewaySSLCertificate -Name $certificateName -ApplicationGateway $appGateway -CertificateFile $certificateData.PfxFullChain -Password $certificateData.PfxPass

} else {
    Write-Output "Creating new certificate $certificateName"
    New-AzureRmApplicationGatewaySslCertificate -Name $certificateName -ApplicationGateway $appGateway -CertificateFile $certificateData.PfxFullChain -Password $certificateData.PfxPass
}

# Write configuration back to App Gateway
Write-Output "Writing updated configuration to $appGateway"
Set-AzureRmApplicationGateway -ApplicationGateway $appGateway
