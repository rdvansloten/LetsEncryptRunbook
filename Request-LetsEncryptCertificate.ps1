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
    [string] $automationAccountResourceGroupName,

    [Parameter(mandatory=$false)]
    [string] $automationAccountName,

    [Parameter(mandatory=$false)]
    [string] $automationAccountCredential,

    [Parameter(mandatory=$false)]
    [string] $stagingMode
)

# Set up Azure RunAs connection
$connectionName = "AzureRunAsConnection"

try {
    # Get the connection "AzureRunAsConnection"
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection) {
        $errorMessage = "Connection $connectionName not found."
        throw $errorMessage
    } else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

# Get Azure Automation Credential with .pfx password
#if ($automationAccountCredential -and $automationAccountName -and $automationAccountResourceGroupName) {
#    $certificatePassword = Get-AutomationPSCredential  
#}

# Retrieves from LetsEncrypt Staging server, for testing purposes. Not a valid certificate. Only fires if variable is set
if ($stagingMode) { 
    Write-Output "Using LetsEncrypt Staging server"
    Set-PAServer LE_STAGE
} else {
    Write-Output "Using LetsEncrypt Production server"
    Set-PAServer LE_PROD
}

# Create a new account
New-PAAccount -AcceptTOS -Contact $emailAddress -KeyLength 2048 -Force

# Order a new/existing domain, with or without custom password
#if ($certificatePassword) {
#    New-PAOrder $domain -PfxPass $certificatePassword -Force 
#} else {
    New-PAOrder $domain -Force 
#}

# Retrieve authorizations and extract HTTP01 token
$authList = Get-PAOrder | Get-PAAuthorizations
$authData = $authList | Select-Object @{L='Body';E={Get-KeyAuthorization $_.HTTP01Token (Get-PAAccount)}},@{L='FileName';E={$($_.HTTP01Token)}}

# Dump gathered info to local file for later usage
$filePath = $env:TEMP + "\" + $authData.FileName
Set-Content -Value $authData.Body -Path $filePath

# Storage Account settings
$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $storageAccountResourceGroupName -Name $storageAccountName
$storageAccountContext = $storageAccount.Context

# Create a valid blob for HTTP challenge
$blobName = ".well-known\acme-challenge\" + $authData.FileName
Set-AzureStorageBlobContent -File $filePath -Container $containerName -Context $storageAccountContext -Blob $blobName

# Send challenge
$authList.HTTP01Url | Send-ChallengeAck

# Wait sane period of time for Challenge to resolve (dirty fix)
Write-Output "Starting wait period"
Start-Sleep -s 20

# Store certificate data (.pfx) in variable
$certificateData = New-PACertificate $domainName

# Clean up HTTP challenge blob after usage
Remove-AzureStorageBlob -Container $containerName -Context $storageAccountContext -Blob $blobName

# Set configuration to push to Application Gateway
$appGatewayData = Get-AzureRmApplicationGateway -ResourceGroupName $appGatewayResourceGroupName -Name $appGatewayName

# Retrieve list of certificates
$certificateList = $(Get-AzureRmApplicationGatewaySslCertificate -ApplicationGateway $appGatewayData).Name
Write-Output "Available certificates on $($appGatewayName): $($certificateList)"

# check if certificate already exists
if ($certificateList -contains $certificateName) {
    # Replace existing certificate
    Write-Output "Replacing existing certificate $certificateName"
    Set-AzureRmApplicationGatewaySSLCertificate -Name $certificateName -ApplicationGateway $appGatewayData -CertificateFile $certificateData.PfxFullChain -Password $certificateData.PfxPass
} else {
    # Create new certificate
    Write-Output "Installing new certificate $certificateName"
    Add-AzureRmApplicationGatewaySslCertificate -Name $certificateName -ApplicationGateway $appGatewayData -CertificateFile $certificateData.PfxFullChain -Password $certificateData.PfxPass
}

# Apply changes to Application Gateway
Write-Output "Writing new configuration to $appGatewayName"
Set-AzureRmApplicationGateway -ApplicationGateway $appGatewayData
