# The following script bootstraps the environment by installing necessary modules.

# Install all the Dependencies needed for the AzDO-DSC-LCM module.
# Check PowerShell Version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    # Must be running on Windows if PowerShell version is less than 7
    # Use winget to install PowerShell 7
    winget install --id Microsoft.PowerShell --source winget
    exit 1
}

Install-Module PSDesiredStateConfiguration, Datum, Datum.InvokeCommand, powershell-yaml, pester -Force -Scope AllUsers -SkipPublisherCheck
