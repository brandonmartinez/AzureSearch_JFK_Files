# BEFORE RUNNING THIS!!!
# Make sure you've done `az login` and selected a subscription
# You can view subscriptions by using `az account list --output table`
# and you can select one by `az account set --subscription "My Subscription Name"`
# For more information on the Azure CLI, visit https://docs.microsoft.com/en-us/cli/azure/?view=azure-cli-latest

param (
    [Parameter(Position=0,mandatory=$true)]
    [string]$resourcePrefix = 'jfk',
    [Parameter(Position=1,mandatory=$false)]
    [string]$resourceGroupName,
    [Parameter(Position=2,mandatory=$false)]
    [string]$resourceLocation = 'eastus',
    [Parameter(Position=3,mandatory=$false)]
    [switch]$skipPrompts,
    [Parameter(Position=4,mandatory=$false)]
    [switch]$skipCreation
)

# We want to stop if *any* error occurs
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction']='Stop'

if($skipCreation) {
    $skipPrompts = $true
}

function Verify-LastExitCode {
    if($LastExitCode -ne 0) {
        throw "An error occurred executing the previous command. Check its output for more details."
    }
}

function Confirm-ResourceCreation {
    param([string] $serviceTypeToCreate)

    if($skipPrompts) {
        return -not $skipCreation;
    }

    $createSearchService = Read-Host -Prompt "Create $($serviceTypeToCreate)? (y/n)"
    return $createSearchService.Substring(0, 1).ToLower() -eq 'y'
}

# Some common variables
$scriptRoot = $PSScriptRoot
$resourceSuffix = 'demo'

# Resource Names
$webAppName = "$resourcePrefix-site-$resourceSuffix"
$storageAccountName = "$resourcePrefix-storage-$resourceSuffix".Replace('-', '')
$searchServiceName = "$resourcePrefix-search-service-$resourceSuffix"
$appServicePlanName = "$resourcePrefix-plan-$resourceSuffix"
$functionAppName = "$resourcePrefix-function-app-$resourceSuffix"
$cognitiveServicesName = "$resourcePrefix-cognitive-services-$resourceSuffix"

try {
    # Setting the default location for services
    Write-Host "Setting the Default Resource Location to $resourceLocation"
    az configure --defaults location=$resourceLocation
    Verify-LastExitCode

    # if no resource group name is specified, create one
    if([string]::IsNullOrWhiteSpace($resourceGroupName)){
        $resourceGroupName = "$resourcePrefix-rg"

        Write-Host "Creating Resource Group: $resourceGroupName"
        az group create --name $resourceGroupName
        Verify-LastExitCode
        Write-Host "Created Resource Group: $resourceGroupName"
    }

    # Setting the default resource group for services
    Write-Host "Setting the Default Resource Group to $resourceGroupName"
    az configure --defaults group=$resourceGroupName
    Verify-LastExitCode

    if(Confirm-ResourceCreation 'Search Service') {
        Write-Host "Creating Search Service: $searchServiceName"
        az search service create --name $searchServiceName --sku 'Basic'
        Verify-LastExitCode
        Write-Host "Created Search Service: $searchServiceName"
    }

    Write-Host "Retrieving Keys from Search Service: $searchServiceName"
    $searchServiceKeysOutput = az search admin-key show --service-name $searchServiceName | Out-String
    $searchServiceKeys = ConvertFrom-Json -InputObject $searchServiceKeysOutput
    $searchServiceKey = $searchServiceKeys.primaryKey

    if(Confirm-ResourceCreation 'Storage Account') {
        Write-Host "Creating Storage Account: $storageAccountName"
        az storage account create --name $storageAccountName --sku 'Standard_LRS'
        Verify-LastExitCode
        Write-Host "Created Storage Account: $storageAccountName"
    }

    Write-Host "Retrieving Connection String from Storage Account: $storageAccountName"
    $storageConnectionStringOutput = az storage account show-connection-string --name $storageAccountName | Out-String
    $storageConnectionString = (ConvertFrom-Json -InputObject $storageConnectionStringOutput).connectionString

    if(Confirm-ResourceCreation 'App Service Plan') {
        Write-Host "Creating App Service Plan: $appServicePlanName"
        az appservice plan create --name $appServicePlanName --sku 'B1'
        Verify-LastExitCode
        Write-Host "Created App Service Plan: $appServicePlanName"
    }

    if(Confirm-ResourceCreation 'Web App') {
        Write-Host "Creating Web App: $webAppName"
        az webapp create --plan $appServicePlanName --name $webAppName
        Verify-LastExitCode
        Write-Host "Created Web App: $webAppName"
    }

    Write-Host "Retrieving Publishing Credentials from Web App: $webAppName"
    $webAppPublishingCredentialsOutput = az webapp deployment list-publishing-credentials --name $webAppName | Out-String
    $webAppPublishingCredentials = ConvertFrom-Json -InputObject $webAppPublishingCredentialsOutput
    $webAppPublishingCredentialsUserName = $webAppPublishingCredentials.publishingUserName
    $webAppPublishingCredentialsPassword = $webAppPublishingCredentials.publishingPassword
    

    if(Confirm-ResourceCreation 'Function App') {
        Write-Host "Creating Function App: $functionAppName"
        az functionapp create --plan $appServicePlanName --storage-account $storageAccountName --name $functionAppName --deployment-source-url 'https://github.com/Microsoft/AzureSearch_JFK_Files' --deployment-source-branch 'master'
        Verify-LastExitCode
        Write-Host "Created Function App: $functionAppName"

        Write-Host "Updating CORS for Function App: $functionAppName"
        az functionapp cors add --name $functionAppName --allowed-origins https://$webAppName.azurewebsites.net
        Verify-LastExitCode
    }

    Write-Host "Updating Configuration of Function App: $functionAppName"
    az functionapp config appsettings set --name $functionAppName --settings "AzureWebJobsSecretStorageType=Files" "FUNCTIONS_EXTENSION_VERSION=beta" "SearchServiceName=$searchServiceName" "SearchServiceKey=$searchServiceKey" "BlobStorageAccountConnectionString=$storageConnectionString"
    Verify-LastExitCode

    Write-Host "Retrieving Publishing Credentials from Function App: $functionAppName"
    $functionAppPublishingCredentialsOutput = az functionapp deployment list-publishing-credentials --name $functionAppName | Out-String
    $functionAppPublishingCredentials = ConvertFrom-Json -InputObject $functionAppPublishingCredentialsOutput
    $functionAppPublishingCredentialsUserName = $functionAppPublishingCredentials.publishingUserName
    $functionAppPublishingCredentialsPassword = $functionAppPublishingCredentials.publishingPassword

    if(Confirm-ResourceCreation 'Cognitive Services') {
        Write-Host "Creating Cognitive Services: $cognitiveServicesName"
        az cognitiveservices account create --name $cognitiveServicesName --sku 'S0' --kind 'CognitiveServices'
        Verify-LastExitCode
        Write-Host "Created Cognitive Services: $cognitiveServicesName"
    }

    Write-Host "Retrieving Keys from Cognitive Services: $cognitiveServicesName"
    $cognitiveServicesKeysOutput = az cognitiveservices account keys list --name $cognitiveServicesName | Out-String
    $cognitiveServicesKeys = ConvertFrom-Json -InputObject $cognitiveServicesKeysOutput
    $cognitiveServicesKey = $cognitiveServicesKeys.key1

    Write-Host "Creation and Configuration of Services Complete!`n`n"
    Write-Host "*****************************************************************"
    Write-Host "Below is the required output to use in the example application:"
    Write-Host "*****************************************************************"
    Write-Host "Search Service Name: $searchServiceName"
    Write-Host "Search Service API Key: $searchServiceKey"
    Write-Host "Cognitive Services Name: $cognitiveServicesName"
    Write-Host "Cognitive Services Account Key: $cognitiveServicesKey"
    Write-Host "Storage Account Name: $storageAccountName"
    Write-Host "Storage Connection String: $storageConnectionString"
    Write-Host "Web App Name: $webAppName"
    Write-Host "Web App User Name: $webAppPublishingCredentialsUserName"
    Write-Host "Web App Password: $webAppPublishingCredentialsPassword"
    Write-Host "Function App Name: $functionAppName"
    Write-Host "Function App User Name: $functionAppPublishingCredentialsUserName"
    Write-Host "Function App Password: $functionAppPublishingCredentialsPassword"
    Write-Host "*****************************************************************"
}
catch {
    $ErrorMessage = $_.Exception.Message
    Write-Host "An error occurred: $ErrorMessage"
}
finally {
    # Clearing the default location
    Write-Host "Clearing the Default Resource Location and Resource Group"
    az configure --defaults location='' group=''

    # Always set our location back to our script root to make it easier to re-execute
    Set-Location -Path $scriptRoot
}
