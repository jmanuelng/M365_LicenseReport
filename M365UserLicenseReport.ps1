<#
.SYNOPSIS
Script to get detailed insights into user license assignments within an Azure AD environment. It extracts information about assigned licenses, services, and their statuses for each user.

.DESCRIPTION
The script performs the following key functions:
    1. **User License Information Retrieval:**
    - Extracts and consolidates information about assigned licenses, services, and their statuses for each user.
    - Provides the option to process a specified list of users or all users within the Azure AD environment.
    - Generates detailed and simplified reports in CSV format.

    2. **Azure AD Module Validation and Installation:**
    - Validates the presence of the AzureAD module and facilitates its installation if absent.

    3. **Local Administrator Privilege Validation:**
    - Verifies the script is executed with local administrator privileges.

    4. **Friendly Name Mapping:**
    - Converts SKU IDs and Service Names to more readable friendly names.
    - Utilizes predefined friendly name lists for license plans and services.

    5. **Progress Display:**
    - Provides progress update during execution, indicating user being processed and total number of users exported.

.PARAMETER UserNamesFile
An optional parameter allowing the user to specify a CSV file containing a list of users to be processed. If not provided, the script will process all users in the Azure AD environment.

.EXAMPLE
.\ScriptName.ps1 -UserNamesFile .\UserList.csv

Example demonstrates how to run script with a specified list of users contained in the 'UserList.csv' file.

.OUTPUTS
1. **Detailed Report (CSV):**
   - Contains comprehensive details such as DisplayName, UserPrincipalName, LicensePlan, FriendlyNameofLicensePlan, ServiceId, ServiceName, and ProvisioningStatus.

2. **Simplified Report (CSV):**
   - Provides a concise view containing DisplayName, UserPrincipalName, Country, LicensePlanWithEnabledService, and FriendlyNameOfLicensePlanAndEnabledService.

.NOTES
- Ensure the script is run with local administrator privileges.
- Allow the script to install the AzureAD module when prompted if it is not already installed.
- Uncomment the last section of the script to receive a prompt to open the output files immediately after the script execution.

.ToDo
- Cross-Tenant execution. Make a Report from a different TenantB while signing with TenantA user (assuming priviliges). A B2B scenario.

#>

Param
(
 [Parameter(Mandatory = $false)]
    [string]$UserNamesFile,
 [Parameter(Mandatory = $false)]
    [string]$TenantId  # New parameter for specifying Tenant
)


Function Validate-LocalAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $windowsPrincipal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
    return $windowsPrincipal.IsInRole($adminRole)
}

Function Validate-AzureADModule {
    if (-not (Get-Module -ListAvailable -Name AzureAD)) {
        $userConfirmation = Read-Host "AzureAD module is not installed. Would you like to install it now? (Y/N)"
        if ($userConfirmation -eq 'Y' -or $userConfirmation -eq 'y') {
            Install-Module -Name AzureAD -Force -AllowClobber -Scope CurrentUser
        } else {
            Write-Host "AzureAD module is required for this script to run. Exiting..."
            exit
        }
    }
}

Function NOTValidate-GlobalAdminOrReader {
    param (
        [string]$UserPrincipalName,  # Accept UserPrincipalName as a parameter
        [string]$TenantId = $null    # Accept TenantId as an optional parameter, default to $null
    )
    
    try {
        $userId = (Get-AzureADUser -ObjectId $UserPrincipalName).ObjectId
        if ($TenantId) {
            $globalAdminRoleId = (Get-AzureADDirectoryRole -Filter "DisplayName eq 'Global Administrator'" -TenantId $TenantId).ObjectId
            $globalReaderRoleId = (Get-AzureADDirectoryRole -Filter "DisplayName eq 'Global Reader'" -TenantId $TenantId).ObjectId
        } else {
            $globalAdminRoleId = (Get-AzureADDirectoryRole -Filter "DisplayName eq 'Global Administrator'").ObjectId
            $globalReaderRoleId = (Get-AzureADDirectoryRole -Filter "DisplayName eq 'Global Reader'").ObjectId
        }
        
        # Get members of both Global Admin and Global Reader roles
        $globalAdminMembers = if ($TenantId) {
            Get-AzureADDirectoryRoleMember -ObjectId $globalAdminRoleId -TenantId $TenantId
        } else {
            Get-AzureADDirectoryRoleMember -ObjectId $globalAdminRoleId
        }
        
        $globalReaderMembers = if ($TenantId) {
            Get-AzureADDirectoryRoleMember -ObjectId $globalReaderRoleId -TenantId $TenantId
        } else {
            Get-AzureADDirectoryRoleMember -ObjectId $globalReaderRoleId
        }
        
        # Combine both lists of members
        $allMembers = $globalAdminMembers + $globalReaderMembers
        
        # Check if the user is in either of the roles
        if ($allMembers.ObjectId -contains $userId) {
            return $true
        } else {
            Write-Host "User must be a Global Admin or Global Reader to run this script. Exiting..."
            exit
        }
    } catch {
        Write-Host "Error validating user role: $_"
        exit
    }
}


Function Get_UsersLicenseInfo {
  $upn = $_.UserPrincipalName
  $Country = $_.Country
  if ([string]$Country -eq "") {
      $Country = "-"
  }
  Write-Progress -Activity "`n     Exported user count:$LicensedUserCount "`n"Currently Processing:$upn"
  
  $Skus = $_.AssignedLicenses
  $LicensePlanWithEnabledService = ""
  $FriendlyNameOfLicensePlanWithService = ""
  
  foreach ($Sku in $Skus) {
      $LicenseItem = $Sku.SkuId
      if ($null -ne $global:LicenseFriendlyNames) {
                $EasyName = $global:LicenseFriendlyNames["$LicenseItem"] # Use global variable to get friendly name
        }
      $NamePrint = if ($EasyName) { $EasyName } else { $LicenseItem }
      
      $serviceExceptDisabled = ""
      $FriendlyNameOfServiceExceptDisabled = ""
      $DisabledServiceCount = 0
      $EnabledServiceCount = 0
      
      $SkuInfo = Get-AzureADSubscribedSku | Where-Object { $_.SkuId -eq $LicenseItem }
      
      foreach ($ServicePlan in $SkuInfo.ServicePlans) {
          $ServiceName = $ServicePlan.ServicePlanName
          $ServiceId = $ServicePlan.ServicePlanId
          $ServiceStatus = $_.AssignedPlans | Where-Object { $_.ServicePlanId -eq $ServicePlan.ServicePlanId } | Select-Object -ExpandProperty CapabilityStatus
          
          if ($ServiceStatus -eq "Disabled") {
              $DisabledServiceCount++
          } else {
              $EnabledServiceCount++
              if ($EnabledServiceCount -ne 1) {
                  $serviceExceptDisabled += ","
                  $FriendlyNameOfServiceExceptDisabled += ","
              }
              $serviceExceptDisabled += $ServiceName
              $FriendlyNameOfServiceExceptDisabled += $ServiceArray["$ServiceName"]
          }
          
          $Result = @{
              'DisplayName'                   = $_.DisplayName
              'UserPrinciPalName'             = $upn
              'LicensePlan'                   = $LicenseItem
              'FriendlyNameofLicensePlan'     = $NamePrint  # Updated to use friendly name
              'ServiceId'                     = $ServiceId
              'ServiceName'                   = $ServiceName
              'ProvisioningStatus'            = $ServiceStatus
          }
          $Results = New-Object PSObject -Property $Result
          $Results | Select-Object DisplayName, UserPrinciPalName, LicensePlan, FriendlyNameofLicensePlan, ServiceId, ServiceName, ProvisioningStatus | Export-Csv -Path $ExportCSV -NoTypeInformation -Append -Encoding UTF8
      }
      
      if ($DisabledServiceCount -eq 0) {
          $serviceExceptDisabled = "All services"
          $FriendlyNameOfServiceExceptDisabled = "All services"
      }
      
      if ($LicensePlanWithEnabledService -ne "") {
          $LicensePlanWithEnabledService += "; "
          $FriendlyNameOfLicensePlanWithService += "; "
      }
      
      $LicensePlanWithEnabledService += "$LicenseItem[$serviceExceptDisabled]"
      $FriendlyNameOfLicensePlanWithService += "$NamePrint[$FriendlyNameOfServiceExceptDisabled]"
  }
  
  $Output = @{
      'Displayname'                               = $_.DisplayName
      'UserPrincipalName'                         = $upn
      'Country'                                   = $Country
      'LicensePlanWithEnabledService'             = $LicensePlanWithEnabledService
      'FriendlyNameOfLicensePlanAndEnabledService'= $FriendlyNameOfLicensePlanWithService
  }
  $Outputs = New-Object PSObject -Property $output
  $Outputs | Select-Object Displayname, UserPrincipalName, Country, LicensePlanWithEnabledService, FriendlyNameOfLicensePlanAndEnabledService | Export-Csv -Path $ExportSimpleCSV -NoTypeInformation -Append -Encoding UTF8
}

 # Validate local admin privileges
if (-not (Validate-LocalAdmin)) {
    Write-Host "You do not have local admin privileges. Exiting..."
    exit
  }
  
# Validate and Install AzureAD module if not present
Validate-AzureADModule

# Connect to AzureAD with specified Tenant if provided
if ($TenantId) {
    try {
        $connectedAccount = Connect-AzureAD -TenantId $TenantId
    } catch {
        Write-Host "Error connecting to Azure AD with TenantId $($TenantId): $_" -ForegroundColor Red
        exit
    }
} else {
    try {
        $connectedAccount = Connect-AzureAD
    } catch {
        Write-Host "Error connecting to Azure AD: $_" -ForegroundColor Red
        exit
    }
}
  
# Validate Global Admin or Global Reader. Checks if TenantId is provided, if so, passes it to the validation function, else just pass UserPrincipalName
$UserPrincipalName = $connectedAccount.Account.Id  # Get UserPrincipalName from the connected account

if ($TenantId) {
    if (-not (Validate-GlobalAdminOrReader -UserPrincipalName $UserPrincipalName -TenantId $TenantId)) {  # Pass UserPrincipalName and TenantId to the function
        exit
    }
} else {
    if (-not (Validate-GlobalAdminOrReader -UserPrincipalName $UserPrincipalName)) {  # Pass only UserPrincipalName to the function
        exit
    }
}
  
  # Set output file
  $ExportCSV = ".\DetailedO365UserLicenseReport_$((Get-Date -format yyyy-MMM-dd-ddd` hh-mm` tt).ToString()).csv"
  $ExportSimpleCSV = ".\SimpleO365UserLicenseReport_$((Get-Date -format yyyy-MMM-dd-ddd` hh-mm` tt).ToString()).csv"
  
  # Get all subscribed SKUs in the tenant
  $subscribedSkus = Get-AzureADSubscribedSku
  
  # Create a hashtable to map SKU IDs to friendly names
  $LicenseFriendlyNames = @{}
  foreach ($sku in $subscribedSkus) {
      $skuId = $sku.SkuId
      $friendlyName = $sku.SkuPartNumber  # This is usually the friendly name of the license
      $LicenseFriendlyNames["$skuId"] = $friendlyName
  }
  
  # FriendlyName list for license plan and service
  $FriendlyNameHash = Get-Content -Raw -Path .\LicenseFriendlyName.txt -ErrorAction Stop | ConvertFrom-StringData
  $ServiceArray = Get-Content -Path .\ServiceFriendlyName.txt -ErrorAction Stop
  
  # Hash table declaration
  $Result=""
  $Results=@()
  $output=""
  $outputs=@()
  
  # Get licensed user
  $LicensedUserCount=0
  
  # Check for input file/Get users from input file
  if([string]$UserNamesFile -ne "") {
    # We have an input file, read it into memory
    $UserNames=@()
    $UserNames=Import-Csv -Header "DisplayName" $UserNamesFile
    $userNames
    foreach($item in $UserNames) {
        Get-AzureADUser -ObjectId $item.displayname | Where-Object{$_.AssignedLicenses -ne $null} | ForEach-Object{
            Get_UsersLicenseInfo
            $LicensedUserCount++
        }
    }
  }
  # Get all licensed users
  else {
    Get-AzureADUser -All $true | Where-Object{$_.AssignedLicenses -ne $null} | ForEach-Object{
        Get_UsersLicenseInfo
        $LicensedUserCount++
    }
  }
  
  # Open output file after execution
  Write-Host "Detailed report available in: $ExportCSV"
  Write-host "Simple report available in: $ExportSimpleCSV"
  #$Prompt = New-Object -ComObject wscript.shell
  #$UserInput = $Prompt.popup("Do you want to open output files?", 0, "Open Files", 4)
  #If ($UserInput -eq 6) {
  #  Invoke-Item "$ExportCSV"
  #  Invoke-Item "$ExportSimpleCSV"
  #}
  