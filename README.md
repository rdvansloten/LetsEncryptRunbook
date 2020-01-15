# Azure Automation Runbook: LetsEncryptRunbook
Azure Automation Runbook to renew LetsEncrypt certificates on Azure Application Gateway

## Requirements
- Azure Storage Account
- Azure Automation Account
- Azure Automation Modules
  - AzureRM.Network
  - AzureRM.Storage
  - AzureRM.Profile
  - Posh-ACME
- Azure Application Gateway
  - :80 Listener, redirecting to Storage Account URL
- Valid DNS A record

## Variables

### Mandatory
```PowerShell
    [string] $emailAddress                     # Email address for renewals
    [string] $domainName                       # Domain name to request the certificate for (i.e.: test.contoso.com)
    [string] $storageAccountResourceGroupName  # Resource Group name in which the Storage Account resides
    [string] $storageAccountName               # Storage Account name
    [string] $blobContainerName                # Name of the blob container
    [string] $appGatewayResourceGroupName      # Resource Group name in which the Application Gateway resides
    [string] $appGatewayName                   # Application Gateway name
    [string] $certificateName                  # Desired name of the certificate or name of the existing certificate

```

### Optional
```PowerShell
    [string] $stagingMode                      # If set to true, will use (invalid) LetsEncrypt certificates for testing purposes
```

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

Please make sure to update tests as appropriate.