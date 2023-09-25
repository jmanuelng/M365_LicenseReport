# M365_LicenseReport
# Azure AD User License Management Script

PowerShell script to get insights into user license assignments within an Azure AD environment. 


## Features
- **Comprehensive User License Information Retrieval:**
  - Extracts detailed information about assigned licenses, services, and their statuses for each user.
  - Offers the flexibility to process either a specified list of users or all users within the Azure AD environment.
  - Generates detailed and simplified reports in CSV format for quick analysis and review.

- **Azure AD Module Validation and Installation:**
  - Validates and installs the AzureAD module as needed, ensuring all dependencies are met before execution.

- **Local Administrator Privilege Validation:**
  - Ensures the script is executed with local administrator privileges for secure and proper execution.

- **Friendly Name Mapping:**
  - Converts SKU IDs and Service Names to more readable friendly names, enhancing the understandability of the output.

- **Real-Time Progress Display:**
  - Provides real-time progress updates during execution, indicating the current user being processed and the total number of users exported.

## Prerequisites
- Local Administrator Privileges are required to run the script.
- AzureAD module needs to be installed. The script will prompt for installation if it's not already present.

## Usage
To run the script for a specified list of users, use the following command:
```sh
.\M365UserLicenseReport.ps1 -UserNamesFile .\UserList.csv
```
Replace `.\UserList.csv` with the path to your user list file.

To process all users in the Azure AD environment, simply run the script without any parameters:
```sh
.\M365UserLicenseReport.ps1
```

## Output
- **Detailed Report (CSV):**
  - Contains comprehensive details such as DisplayName, UserPrincipalName, LicensePlan, FriendlyNameofLicensePlan, ServiceId, ServiceName, and ProvisioningStatus.

- **Simplified Report (CSV):**
  - Provides a concise view containing DisplayName, UserPrincipalName, Country, LicensePlanWithEnabledService, and FriendlyNameOfLicensePlanAndEnabledService.

## License
Distributed under the MIT License.
