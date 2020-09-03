# Azure Automation Runbook: LetsEncryptRunbook
Azure Automation Runbook to renew LetsEncrypt certificates on Azure Application Gateway.

## Requirements
- Azure Storage Account
- Azure Automation Account
- Azure Application Gateway
  - :80 Listener, redirecting to Storage Account URL
- Valid DNS A record

You will need to install the latest versions of the following modules in your Azure Automation Account:
- AzureRM.Profile
- AzureRM.Network
- AzureRM.Storage
- AzureRM.KeyVault
- Posh-ACME


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
[string] $keyVaultName                     # If set to true, will use Azure Key Vault to store certificate
```

## Scheduling/invoking
LetsEncrypt advises that you set the renewals to monthly recurring. You may do so under your Runbook > Schedules. Alternatively, for one-time calls, create a Webhook in that same menu.

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

Please make sure to update tests as appropriate.
