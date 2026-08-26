# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#HelloID variables
#Note: when running this script inside HelloID; portalUrl and API credentials are provided automatically (generate and save API credentials first in your admin panel!)
$portalUrl = "https://CUSTOMER.helloid.com"
$apiKey = "API_KEY"
$apiSecret = "API_SECRET"
$delegatedFormAccessGroupNames = @("") #Only unique names are supported. Groups must exist!
$delegatedFormCategories = @("Exchange On-Premises") #Only unique names are supported. Categories will be created if not exists
$script:debugLogging = $false #Default value: $false. If $true, the HelloID resource GUIDs will be shown in the logging
$script:duplicateForm = $false #Default value: $false. If $true, the HelloID resource names will be changed to import a duplicate Form
$script:duplicateFormSuffix = "_tmp" #the suffix will be added to all HelloID resource names to generate a duplicate form with different resource names

#The following HelloID Global variables are used by this form. No existing HelloID global variables will be overriden only new ones are created.
#NOTE: You can also update the HelloID Global variable values afterwards in the HelloID Admin Portal: https://<CUSTOMER>.helloid.com/admin/variablelibrary
$globalHelloIDVariables = [System.Collections.Generic.List[object]]@();

#Global variable #1 >> ExchangeConnectionUri
$tmpName = @'
ExchangeConnectionUri
'@ 
$tmpValue = @'
'@ 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False" });

#Global variable #2 >> ExchangeAdminPassword
$tmpName = @'
ExchangeAdminPassword
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "True" });

#Global variable #3 >> ExchangeAdminUsername
$tmpName = @'
ExchangeAdminUsername
'@ 
$tmpValue = @'
'@ 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False" });

#Global variable #4 >> ADusersSearchOU
$tmpName = @'
ADusersSearchOU
'@ 
$tmpValue = @'
'@ 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False" });


#make sure write-information logging is visual
$InformationPreference = "continue"

# Check for prefilled API Authorization header
if (-not [string]::IsNullOrEmpty($portalApiBasic)) {
    $script:headers = @{"authorization" = $portalApiBasic }
    Write-Information "Using prefilled API credentials"
}
else {
    # Create authorization headers with HelloID API key
    $pair = "$apiKey" + ":" + "$apiSecret"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $key = "Basic $base64"
    $script:headers = @{"authorization" = $Key }
    Write-Information "Using manual API credentials"
}

# Check for prefilled PortalBaseURL
if (-not [string]::IsNullOrEmpty($portalBaseUrl)) {
    $script:PortalBaseUrl = $portalBaseUrl
    Write-Information "Using prefilled PortalURL: $script:PortalBaseUrl"
}
else {
    $script:PortalBaseUrl = $portalUrl
    Write-Information "Using manual PortalURL: $script:PortalBaseUrl"
}

# Define specific endpoint URI
$script:PortalBaseUrl = $script:PortalBaseUrl.trim("/") + "/"  

# Make sure to reveive an empty array using PowerShell Core
function ConvertFrom-Json-WithEmptyArray([string]$jsonString) {
    # Running in PowerShell Core?
    if ($IsCoreCLR -eq $true) {
        $r = [Object[]]($jsonString | ConvertFrom-Json -NoEnumerate)
        return , $r  # Force return value to be an array using a comma
    }
    else {
        $r = [Object[]]($jsonString | ConvertFrom-Json)
        return , $r  # Force return value to be an array using a comma
    }
}

function Invoke-HelloIDGlobalVariable {
    param(
        [parameter(Mandatory)][String]$Name,
        [parameter(Mandatory)][String][AllowEmptyString()]$Value,
        [parameter(Mandatory)][String]$Secret
    )

    $Name = $Name + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/automation/variables/named/$Name")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false

        if ([string]::IsNullOrEmpty($response.automationVariableGuid)) {
            #Create Variable
            $body = @{
                name     = $Name;
                value    = $Value;
                secret   = $Secret;
                ItemType = 0;
            }    
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/automation/variable")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $variableGuid = $response.automationVariableGuid

            Write-Information "Variable '$Name' created$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
        else {
            $variableGuid = $response.automationVariableGuid
            Write-Warning "Variable '$Name' already exists$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
    }
    catch {
        Write-Error "Variable '$Name', message: $_"
    }
}

function Invoke-HelloIDAutomationTask {
    param(
        [parameter(Mandatory)][String]$TaskName,
        [parameter(Mandatory)][String]$UseTemplate,
        [parameter(Mandatory)][String]$AutomationContainer,
        [parameter(Mandatory)][String][AllowEmptyString()]$Variables,
        [parameter(Mandatory)][String]$PowershellScript,
        [parameter()][String][AllowEmptyString()]$ObjectGuid,
        [parameter()][String][AllowEmptyString()]$ForceCreateTask,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $TaskName = $TaskName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/automationtasks?search=$TaskName&container=$AutomationContainer")
        $responseRaw = (Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false) 
        $response = $responseRaw | Where-Object -filter { $_.name -eq $TaskName }

        if ([string]::IsNullOrEmpty($response.automationTaskGuid) -or $ForceCreateTask -eq $true) {
            #Create Task

            $body = @{
                name                = $TaskName;
                useTemplate         = $UseTemplate;
                powerShellScript    = $PowershellScript;
                automationContainer = $AutomationContainer;
                objectGuid          = $ObjectGuid;
                variables           = (ConvertFrom-Json-WithEmptyArray($Variables));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/automationtasks/powershell")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $taskGuid = $response.automationTaskGuid

            Write-Information "Powershell task '$TaskName' created$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
        else {
            #Get TaskGUID
            $taskGuid = $response.automationTaskGuid
            Write-Warning "Powershell task '$TaskName' already exists$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
    }
    catch {
        Write-Error "Powershell task '$TaskName', message: $_"
    }

    $returnObject.Value = $taskGuid
}

function Invoke-HelloIDDatasource {
    param(
        [parameter(Mandatory)][String]$DatasourceName,
        [parameter(Mandatory)][String]$DatasourceType,
        [parameter(Mandatory)][String][AllowEmptyString()]$DatasourceModel,
        [parameter()][String][AllowEmptyString()]$DatasourceStaticValue,
        [parameter()][String][AllowEmptyString()]$DatasourcePsScript,        
        [parameter()][String][AllowEmptyString()]$DatasourceInput,
        [parameter()][String][AllowEmptyString()]$AutomationTaskGuid,
        [parameter()][String][AllowEmptyString()]$DatasourceRunInCloud,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $DatasourceName = $DatasourceName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    $datasourceTypeName = switch ($DatasourceType) { 
        "1" { "Native data source"; break } 
        "2" { "Static data source"; break } 
        "3" { "Task data source"; break } 
        "4" { "Powershell data source"; break }
    }

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/datasource/named/$DatasourceName")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
    
        if ([string]::IsNullOrEmpty($response.dataSourceGUID)) {
            #Create DataSource
            $body = @{
                name               = $DatasourceName;
                type               = $DatasourceType;
                model              = (ConvertFrom-Json-WithEmptyArray($DatasourceModel));
                automationTaskGUID = $AutomationTaskGuid;
                value              = (ConvertFrom-Json-WithEmptyArray($DatasourceStaticValue));
                script             = $DatasourcePsScript;
                input              = (ConvertFrom-Json-WithEmptyArray($DatasourceInput));
                runInCloud         = $DatasourceRunInCloud;
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl + "api/v1/datasource")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            
            $datasourceGuid = $response.dataSourceGUID
            Write-Information "$datasourceTypeName '$DatasourceName' created$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
        else {
            #Get DatasourceGUID
            $datasourceGuid = $response.dataSourceGUID
            Write-Warning "$datasourceTypeName '$DatasourceName' already exists$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
    }
    catch {
        Write-Error "$datasourceTypeName '$DatasourceName', message: $_"
    }

    $returnObject.Value = $datasourceGuid
}

function Invoke-HelloIDDynamicForm {
    param(
        [parameter(Mandatory)][String]$FormName,
        [parameter(Mandatory)][String]$FormSchema,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $FormName = $FormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl + "api/v1/forms/$FormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        }
        catch {
            $response = $null
        }

        if (([string]::IsNullOrEmpty($response.dynamicFormGUID)) -or ($response.isUpdated -eq $true)) {
            #Create Dynamic form
            $body = @{
                Name       = $FormName;
                FormSchema = (ConvertFrom-Json-WithEmptyArray($FormSchema));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/forms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $formGuid = $response.dynamicFormGUID
            Write-Information "Dynamic form '$formName' created$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
        else {
            $formGuid = $response.dynamicFormGUID
            Write-Warning "Dynamic form '$FormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
    }
    catch {
        Write-Error "Dynamic form '$FormName', message: $_"
    }

    $returnObject.Value = $formGuid
}


function Invoke-HelloIDDelegatedForm {
    param(
        [parameter(Mandatory)][String]$DelegatedFormName,
        [parameter(Mandatory)][String]$DynamicFormGuid,
        [parameter()][Array][AllowEmptyString()]$AccessGroups,
        [parameter()][String][AllowEmptyString()]$Categories,
        [parameter(Mandatory)][String]$UseFaIcon,
        [parameter()][String][AllowEmptyString()]$FaIcon,
        [parameter()][String][AllowEmptyString()]$task,
        [parameter(Mandatory)][Ref]$returnObject
    )
    $delegatedFormCreated = $false
    $DelegatedFormName = $DelegatedFormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl + "api/v1/delegatedforms/$DelegatedFormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        }
        catch {
            $response = $null
        }

        if ([string]::IsNullOrEmpty($response.delegatedFormGUID)) {
            #Create DelegatedForm
            $body = @{
                name            = $DelegatedFormName;
                dynamicFormGUID = $DynamicFormGuid;
                isEnabled       = "True";
                useFaIcon       = $UseFaIcon;
                faIcon          = $FaIcon;
                task            = ConvertFrom-Json -inputObject $task;
            }
            if (-not[String]::IsNullOrEmpty($AccessGroups)) { 
                $body += @{
                    accessGroups = (ConvertFrom-Json-WithEmptyArray($AccessGroups));
                }
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/delegatedforms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Information "Delegated form '$DelegatedFormName' created$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
            $delegatedFormCreated = $true

            $bodyCategories = $Categories
            $uri = ($script:PortalBaseUrl + "api/v1/delegatedforms/$delegatedFormGuid/categories")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $bodyCategories
            Write-Information "Delegated form '$DelegatedFormName' updated with categories"
        }
        else {
            #Get delegatedFormGUID
            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Warning "Delegated form '$DelegatedFormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
        }
    }
    catch {
        Write-Error "Delegated form '$DelegatedFormName', message: $_"
    }

    $returnObject.value.guid = $delegatedFormGuid
    $returnObject.value.created = $delegatedFormCreated
}

<# Begin: HelloID Global Variables #>
foreach ($item in $globalHelloIDVariables) {
    Invoke-HelloIDGlobalVariable -Name $item.name -Value $item.value -Secret $item.secret 
}
<# End: HelloID Global Variables #>


<# Begin: HelloID Data sources #>
<# Begin: DataSource "exchange-on-premises-usermailbox-update-attributes | Exchange-On-Premises-Get-Usermailbox-Wildcard-Name-Alias" #>
$tmpPsScript = @'
# Variables configured in form
$searchValue = $datasource.searchValue
if ($searchValue -eq "*") {
    $filter = "RecipientTypeDetails -eq 'UserMailbox'"
}
else {
    $filter = "RecipientTypeDetails -eq 'UserMailbox' -and (Name -like '*$searchValue*' -or SamAccountName -like '*$searchValue*' -or Alias -like '*$searchValue*' -or PrimarySmtpAddress -like '*$searchValue*')"
}

# Global variables
# Outcommented as these are set from Global Variables
# $ExchangeConnectionUri = ""
# $ExchangeAdminUsername = ""
# $ExchangeAdminPassword = ""
# $ADusersSearchOU = ""

# Fixed values
# Properties to select - Select only needed properties to limit memory usage and speed up processing
$propertiesToSelect = @(
    "ExchangeGuid"
    , "samAccountName"
    , "UserPrincipalName"
    , "DistinguishedName"
    , "PrimarySmtpAddress"
    , "DisplayName"
    , "Identity"    
    , "HiddenFromAddressListsEnabled"
    , "CustomAttribute1"
    , "CustomAttribute2"
    , "CustomAttribute3"    
    , "CustomAttribute4"  
    , "CustomAttribute5"  
    , "CustomAttribute6"
    , "CustomAttribute7"
    , "CustomAttribute8"    
    , "CustomAttribute9"  
    , "CustomAttribute10"  
    , "CustomAttribute11"
    , "CustomAttribute12"
    , "CustomAttribute13"    
    , "CustomAttribute14"  
    , "CustomAttribute15"  
)


# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
#endregion functions

try {
    # Create credentials
    $actionMessage = "creating credentials object"
    
    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)

    # Connect to Exchange On-Premises
    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell
    $actionMessage = "connecting to Exchange On-Premises using URI [$ExchangeConnectionUri]"

    $sessionOptionParams = @{
        SkipCACheck         = $false
        SkipCNCheck         = $false
        SkipRevocationCheck = $false
    }

    $sessionOption = New-PSSessionOption @sessionOptionParams

    $sessionParams = @{
        Authentication    = 'Default'
        ConfigurationName = 'Microsoft.Exchange'
        ConnectionUri     = $ExchangeConnectionUri
        Credential        = $credential
        SessionOption     = $sessionOption
        ErrorAction       = "Stop"
    }

    $exchangeSession = New-PSSession @sessionParams
    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName "Get-Mailbox" -ErrorAction Stop

    # Get Mailboxes
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailbox
    $actionMessage = "querying user mailboxes that match filter [$($filter)]"

    $getMailboxesSplatParams = @{
        Filter      = $filter
        ResultSize  = "Unlimited"
        ErrorAction = 'Stop'
    }

    $mailboxes = Get-Mailbox @getMailboxesSplatParams | Select-Object -Property $propertiesToSelect
    Write-Information "Queried user mailboxes that match filter [$($filter)]. Result count: $(($mailboxes | Measure-Object).Count)"

    # Sort and send results to HelloID
    $actionMessage = "sending results to HelloID"
    $mailboxes | Sort-Object -Property DisplayName | ForEach-Object {
        # Set mailDomain and mailPrefix properties
        Write-Output $_
    }       
}
catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
    # exit # use when using multiple try/catch and the script must stop
}
finally {
    # Disconnect from Exchange
    # Docs: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-pssession
    if ($null -ne $exchangeSession) {
        try {
            $deleteExchangeSessionSplatParams = @{
                Session     = $exchangeSession
                Confirm     = $false
                ErrorAction = "Stop"
            }
            $null = Remove-PSSession @deleteExchangeSessionSplatParams
        }
        catch {
            Write-Warning "Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)"
        }
    }
}
'@ 
$tmpModel = @'
[{"key":"ExchangeGuid","type":0},{"key":"SamAccountName","type":0},{"key":"UserPrincipalName","type":0},{"key":"DistinguishedName","type":0},{"key":"PrimarySmtpAddress","type":0},{"key":"DisplayName","type":0},{"key":"Identity","type":0},{"key":"HiddenFromAddressListsEnabled","type":0},{"key":"CustomAttribute1","type":0},{"key":"CustomAttribute2","type":0},{"key":"CustomAttribute3","type":0},{"key":"CustomAttribute4","type":0},{"key":"CustomAttribute5","type":0},{"key":"CustomAttribute6","type":0},{"key":"CustomAttribute7","type":0},{"key":"CustomAttribute8","type":0},{"key":"CustomAttribute9","type":0},{"key":"CustomAttribute10","type":0},{"key":"CustomAttribute11","type":0},{"key":"CustomAttribute12","type":0},{"key":"CustomAttribute13","type":0},{"key":"CustomAttribute14","type":0},{"key":"CustomAttribute15","type":0}]
'@ 
$tmpInput = @'
[{"description":"Search  filter","translateDescription":false,"inputFieldType":1,"key":"searchValue","type":0,"options":1}]
'@ 
$dataSourceGuid_0 = [PSCustomObject]@{} 
$dataSourceGuid_0_Name = @'
exchange-on-premises-usermailbox-update-attributes | Exchange-On-Premises-Get-Usermailbox-Wildcard-Name-Alias
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_0_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_0) 
<# End: DataSource "exchange-on-premises-usermailbox-update-attributes | Exchange-On-Premises-Get-Usermailbox-Wildcard-Name-Alias" #>
<# End: HelloID Data sources #>

<# Begin: Dynamic Form "Exchange On-Premises - Usermailbox - Update attributes" #>
$tmpSchema = @"
[{"label":"Select mailbox","fields":[{"key":"searchMailbox","templateOptions":{"label":"Search Usermailbox","required":true},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"selectedmailbox","templateOptions":{"label":"Select Usermailbox","required":true,"grid":{"columns":[{"headerName":"Display Name","field":"DisplayName"},{"headerName":"Primary Smtp Address","field":"PrimarySmtpAddress"},{"headerName":"User Principal Name","field":"UserPrincipalName"},{"headerName":"Hidden From Address Lists Enabled","field":"HiddenFromAddressListsEnabled"}],"height":300,"rowSelection":"single"},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_0","input":{"propertyInputs":[{"propertyName":"searchValue","otherFieldValue":{"otherFieldKey":"searchMailbox"}}]}},"useFilter":true,"useDefault":false,"allowCsvDownload":true},"type":"grid","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":true}]},{"label":"Edit attributes","fields":[{"key":"textDisplayName","templateOptions":{"label":"Display name","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"DisplayName","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA1","templateOptions":{"label":"CustomAttribute1","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute1","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA2","templateOptions":{"label":"CustomAttribute2","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute2","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA3","templateOptions":{"label":"CustomAttribute3","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute3","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA4","templateOptions":{"label":"CustomAttribute4","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute4","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA5","templateOptions":{"label":"CustomAttribute5","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute5","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA6","templateOptions":{"label":"CustomAttribute6","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute6","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA7","templateOptions":{"label":"CustomAttribute7","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute7","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA8","templateOptions":{"label":"CustomAttribute8","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute8","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA9","templateOptions":{"label":"CustomAttribute9","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute9","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA10","templateOptions":{"label":"CustomAttribute10","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute10","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA11","templateOptions":{"label":"CustomAttribute11","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute11","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA12","templateOptions":{"label":"CustomAttribute12","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute12","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA13","templateOptions":{"label":"CustomAttribute13","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute13","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA14","templateOptions":{"label":"CustomAttribute14","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute14","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"textCA15","templateOptions":{"label":"CustomAttribute15","useDependOn":true,"dependOn":"selectedmailbox","dependOnProperty":"CustomAttribute15","placeholder":"<retrieving current value>"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}]}]
"@ 

$dynamicFormGuid = [PSCustomObject]@{} 
$dynamicFormName = @'
Exchange On-Premises - Usermailbox - Update attributes
'@ 
Invoke-HelloIDDynamicForm -FormName $dynamicFormName -FormSchema $tmpSchema  -returnObject ([Ref]$dynamicFormGuid) 
<# END: Dynamic Form #>

<# Begin: Delegated Form Access Groups and Categories #>
$delegatedFormAccessGroupGuids = @()
if (-not[String]::IsNullOrEmpty($delegatedFormAccessGroupNames)) {
    foreach ($group in $delegatedFormAccessGroupNames) {
        try {
            $uri = ($script:PortalBaseUrl + "api/v1/groups/$group")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
            $delegatedFormAccessGroupGuid = $response.groupGuid
            $delegatedFormAccessGroupGuids += $delegatedFormAccessGroupGuid
        
            Write-Information "HelloID (access)group '$group' successfully found$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormAccessGroupGuid })"
        }
        catch {
            Write-Error "HelloID (access)group '$group', message: $_"
        }
    }
    if ($null -ne $delegatedFormAccessGroupGuids) {
        $delegatedFormAccessGroupGuids = ($delegatedFormAccessGroupGuids | Select-Object -Unique | ConvertTo-Json -Depth 100 -Compress)
    }
}

$delegatedFormCategoryGuids = @()
foreach ($category in $delegatedFormCategories) {
    try {
        $uri = ($script:PortalBaseUrl + "api/v1/delegatedformcategories/$category")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        $response = $response | Where-Object { $_.name.en -eq $category }
    
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid
    
        Write-Information "HelloID Delegated Form category '$category' successfully found$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
    catch {
        Write-Warning "HelloID Delegated Form category '$category' not found"
        $body = @{
            name = @{"en" = $category };
        }
        $body = ConvertTo-Json -InputObject $body -Depth 100

        $uri = ($script:PortalBaseUrl + "api/v1/delegatedformcategories")
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid

        Write-Information "HelloID Delegated Form category '$category' successfully created$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
}
$delegatedFormCategoryGuids = (ConvertTo-Json -InputObject $delegatedFormCategoryGuids -Depth 100 -Compress)
<# End: Delegated Form Access Groups and Categories #>

<# Begin: Delegated Form #>
$delegatedFormRef = [PSCustomObject]@{guid = $null; created = $null } 
$delegatedFormName = @'
Exchange On-Premises - Usermailbox - Update attributes
'@
$tmpTask = @'
{"name":"Exchange On-Premises - Usermailbox - Update attributes","script":"# Variables configured in form\r\n$mailbox = $form.selectedmailbox\r\n\r\n# Global variables\r\n# Outcommented as these are set from Global Variables\r\n# $ExchangeConnectionUri = \"\"\r\n# $ExchangeAdminUsername = \"\"\r\n# $ExchangeAdminPassword = \"\"\r\n\r\n# Fixed values\r\n$commands = @(\r\n    \"Set-Mailbox\"\r\n)\r\n\r\n# Enable TLS1.2\r\n[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12\r\n\r\n# Set debug logging\r\n$VerbosePreference = \"SilentlyContinue\"\r\n$InformationPreference = \"Continue\"\r\n$WarningPreference = \"Continue\"\r\n\r\n#region functions\r\n#endregion functions\r\n\r\n# Connect to Exchange\r\ntry {\r\n    # Create credentials\r\n    $actionMessage = \"creating credentials object\"\r\n    \r\n    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force\r\n    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)\r\n    \r\n    Write-Verbose \"Created credentials for user [$ExchangeAdminUsername]\"\r\n\r\n    # Connect to Exchange On-Premises\r\n    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell\r\n    $actionMessage = \"connecting to Exchange On-Premises\"\r\n\r\n    $sessionOptionParams = @{\r\n        SkipCACheck         = $false\r\n        SkipCNCheck         = $false\r\n        SkipRevocationCheck = $false\r\n    }\r\n\r\n    $sessionOption = New-PSSessionOption @sessionOptionParams\r\n\r\n    $sessionParams = @{\r\n        Authentication    = 'Default'\r\n        ConfigurationName = 'Microsoft.Exchange'\r\n        Credential        = $credential\r\n        ConnectionUri     = $ExchangeConnectionUri\r\n        SessionOption     = $sessionOption\r\n        ErrorAction       = \"Stop\"\r\n    }\r\n\r\n    $exchangeSession = New-PSSession @sessionParams\r\n    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName $commands -ErrorAction Stop\r\n\r\n    # Send initial audit log\r\n    $Log = @{\r\n        Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n        System            = \"Exchange On-Premises\" # optional (free format text) \r\n        Message           = \"Successfully connected to Exchange using URI [$ExchangeConnectionUri]\" # required (free format text) \r\n        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $ExchangeConnectionUri # optional (free format text) \r\n        TargetIdentifier  = $([string]$exchangeSession.InstanceId) # optional (free format text) \r\n    }\r\n    Write-Information -Tags \"Audit\" -MessageData $log\r\n\r\n    $exchangeSetMailboxParams = @{\r\n        identity = $mailbox.identity\r\n        ErrorAction = 'Stop'\r\n    } \r\n\r\n    if ( -not ($null -eq $MailboxDisplayName)) {      \r\n        $exchangeSetMailboxParams.add(\"DisplayName\", $MailboxDisplayName)     \r\n    }\r\n    \r\n    for ($i = 1; $i -le 15; $i++) {\r\n        if($null -ne $form.\"textCA$i\"){\r\n            $exchangeSetMailboxParams.add(\"CustomAttribute$i\",$form.\"textCA$i\")\r\n        }    \r\n    }\r\n\r\n    $actionMessage = \"setting mailbox attributes\"  \r\n    $null = Set-Mailbox @exchangeSetMailboxParams\r\n     \r\n    Write-Information \"Succesfully updated mailbox attributes for [$($mailbox.DisplayName) ($($mailbox.ExchangeGuid))]\"\r\n    $Log = @{\r\n        Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n        System            = \"Exchange On-Premises\" # optional (free format text) \r\n        Message           = \"Succesfully updated mailbox attributes for [$($mailbox.DisplayName) ($($mailbox.ExchangeGuid))].\" # required (free format text) \r\n        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $mailbox.DisplayName # optional (free format text) \r\n        TargetIdentifier  = $mailbox.ExchangeGuid # optional (free format text) \r\n    }\r\n    #send result back  \r\n    Write-Information -Tags \"Audit\" -MessageData $log\r\n}\r\ncatch {\r\n    $ex = $PSItem\r\n    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {\r\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n    }\r\n    else {\r\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)\"\r\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception)\"\r\n    }\r\n\r\n    # Send error audit log to HelloID\r\n    $Log = @{\r\n        Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n        System            = \"Exchange On-Premises\" # optional (free format text) \r\n        Message           = $auditMessage # required (free format text) \r\n        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $mailbox.DisplayName # optional (free format text) \r\n        TargetIdentifier  = $mailbox.ExchangeGuid # optional (free format text) \r\n    }\r\n    \r\n    Write-Information -Tags \"Audit\" -MessageData $log\r\n    Write-Warning $warningMessage\r\n    Write-Error $auditMessage\r\n}\r\nfinally {\r\n    # Disconnect from Exchange\r\n    # Docs: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-pssession\r\n    if ($null -ne $exchangeSession) {\r\n        try {\r\n            $deleteExchangeSessionSplatParams = @{\r\n                Session     = $exchangeSession\r\n                Confirm     = $false\r\n                ErrorAction = \"Stop\"\r\n            }\r\n            $null = Remove-PSSession @deleteExchangeSessionSplatParams\r\n\r\n            # Send disconnect audit log\r\n            $Log = @{\r\n                Action            = \"UpdateAccount\" # optional. ENUM (undefined = default) \r\n                System            = \"Exchange On-Premises\" # optional (free format text) \r\n                Message           = \"Successfully disconnected from Exchange using URI [$ExchangeConnectionUri]\" # required (free format text) \r\n                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                TargetDisplayName = $ExchangeConnectionUri # optional (free format text) \r\n                TargetIdentifier  = $([string]$exchangeSession.InstanceId) # optional (free format text) \r\n            }\r\n            Write-Information -Tags \"Audit\" -MessageData $log\r\n        }\r\n        catch {\r\n            Write-Warning \"Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)\"\r\n        }\r\n    }\r\n}","runInCloud":false}
'@ 

Invoke-HelloIDDelegatedForm -DelegatedFormName $delegatedFormName -DynamicFormGuid $dynamicFormGuid -AccessGroups $delegatedFormAccessGroupGuids -Categories $delegatedFormCategoryGuids -UseFaIcon "True" -FaIcon "fa fa-file-text-o" -task $tmpTask -returnObject ([Ref]$delegatedFormRef) 
<# End: Delegated Form #>

