@{
    RootModule = 'AzureDevOpsDsc.psm1'

    # Version number of this module.
    moduleVersion      = '0.0.1'

    # ID used to uniquely identify this module
    GUID               = 'bd78c05f-ac9d-405c-bcb2-14a2877d6baf'

    # Author of this module
    Author             = 'MOCK'

    # Company or vendor of this module
    CompanyName        = 'MOCK'

    # Copyright statement for this module
    Copyright          = 'Copyright MOCK. All rights reserved.'

    # Description of the functionality provided by this module
    Description        = 'MOCK Module with MOCK DSC Resources for testing.'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion  = '7.0'

    # Minimum version of the common language runtime (CLR) required by this module
    CLRVersion         = '4.0'

    # Functions to export from this module
    #FunctionsToExport  = @()

    # Cmdlets to export from this module
    #CmdletsToExport    = @()

    # Variables to export from this module
    VariablesToExport  = @()

    # Aliases to export from this module
    AliasesToExport    = @()

    # Import all the 'DSCClassResource', modules as part of this module
    NestedModules = @()

    DscResourcesToExport = @('AzDevOpsProject','AzDoOrganizationGroup','AzDoProjectGroup','AzDoProject','AzDoProjectServices','AzDoGroupMember','AzDoGitRepository','AzDoGitPermission')

    RequiredAssemblies = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData        = @{

        PSData = @{
            # Set to a prerelease string value if the release should be a prerelease.
            Prerelease   = ''

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags         = @('MOCK')

            # A URL to the license for this module.
            LicenseUri   = 'https://github.com/dsccommunity/AzureDevOpsDsc/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/dsccommunity/AzureDevOpsDsc'

            # A URL to an icon representing this module.
            IconUri      = 'https://dsccommunity.org/images/DSC_Logo_300p.png'

            # ReleaseNotes of this module
            ReleaseNotes = 'MOCK'

        } # End of PSData hashtable

    } # End of PrivateData hashtable
}
