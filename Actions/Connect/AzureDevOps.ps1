<#
.SYNOPSIS
Connect action: establish an Azure DevOps authentication session (opt-in).

.DESCRIPTION
Wraps New-AzDoAuthenticationProvider from AzureDevOpsDsc.Common to set up the
ambient session that the AzureDevOpsDscNative resource module consumes during Test/Set/Get.

This is a soft dependency: the module is imported on demand and only if present. The
core runner never lists AzureDevOpsDscNative in RequiredModules, so Azure DevOps support is
opt-in by naming this action (Connect: AzureDevOps) rather than a hard dependency for
every consumer. If the module is not installed a clear, actionable error is thrown.

.PARAMETER Context
A hashtable. Recognized keys:
  OrganizationName   - the Azure DevOps organization (required).
  AuthenticationType - 'ManagedIdentity' (default) or 'PAT'. ManagedIdentity works on Azure VMs
                       and on Azure Arc-enabled machines.
  PATToken           - the Personal Access Token, required when AuthenticationType = 'PAT'.

.OUTPUTS
$null (the provider registers an ambient session as a side effect).
#>
param(
    [hashtable]$Context = @{}
)

$organizationName = $Context.OrganizationName
if ([string]::IsNullOrWhiteSpace($organizationName)) {
    throw "[Actions/Connect/AzureDevOps] No 'OrganizationName' supplied in the action context."
}

$authenticationType = $Context.AuthenticationType
if ([string]::IsNullOrWhiteSpace($authenticationType)) {
    $authenticationType = 'ManagedIdentity'
}

# Soft dependency: import AzureDevOpsDsc.Common on demand (standalone, or the copy bundled in
# AzureDevOpsDscNative), fail clearly if absent.
if (-not (Get-Command -Name New-AzDoAuthenticationProvider -ErrorAction SilentlyContinue)) {
    try {
        Import-AzureDevOpsDscCommon
    }
    catch {
        throw "[Actions/Connect/AzureDevOps] $($_.Exception.Message)"
    }
}

switch ($authenticationType) {
    'PAT' {
        if ([string]::IsNullOrWhiteSpace($Context.PATToken)) {
            throw "[Actions/Connect/AzureDevOps] AuthenticationType 'PAT' requires a 'PATToken' in the action context."
        }
        Write-Verbose "[Actions/Connect/AzureDevOps] Authenticating to '$organizationName' with a Personal Access Token."
        Invoke-AzDoAuthenticationProvider -Parameters @{ OrganizationName = $organizationName; PersonalAccessToken = $Context.PATToken }
    }
    'ManagedIdentity' {
        Write-Verbose "[Actions/Connect/AzureDevOps] Authenticating to '$organizationName' with a Managed Identity."
        Invoke-AzDoAuthenticationProvider -Parameters @{ OrganizationName = $organizationName; useManagedIdentity = $true }
    }
    default {
        throw "[Actions/Connect/AzureDevOps] Unsupported AuthenticationType '$authenticationType'. Use 'ManagedIdentity' or 'PAT'."
    }
}

return $null
