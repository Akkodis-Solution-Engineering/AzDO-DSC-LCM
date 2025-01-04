if ($AuthenticationType -eq 'PAT') {
    New-AzDoAuthenticationProvider -OrganizationName $AzureDevopsOrganizationName -PersonalAccessToken $PATToken
} elseif ($AuthenticationType -eq 'ManagedIdentity') {
    New-AzDoAuthenticationProvider -OrganizationName $AzureDevopsOrganizationName -useManagedIdentity
}


Function New-AzDoAuthenticationProvider {
    param (
        [string]$OrganizationName,
        [string]$PersonalAccessToken,
        [switch]$useManagedIdentity
    )

}

Export-ModuleMember -Function New-AzDoAuthenticationProvider