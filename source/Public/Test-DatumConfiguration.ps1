<#
.SYNOPSIS
    Validates the Datum Configuration to ensure it meets the required standards.

.DESCRIPTION
    The Test-DatumConfiguration function validates the Datum Configuration object to ensure it contains the necessary properties and that the versioning is correct. 
    It checks for the presence of the LCMConfigSettings property, validates the versioning of the Datum Configuration, and ensures that the versions are within the acceptable range.

.PARAMETER Datum
    The Datum Configuration object that needs to be validated. This parameter is mandatory.

.EXAMPLE
    $datumConfig = Get-DatumConfiguration
    Test-DatumConfiguration -Datum $datumConfig

    This example retrieves a Datum Configuration object and validates it using the Test-DatumConfiguration function.

.NOTES
    The function throws an error if the Datum Configuration is invalid or if any of the version checks fail. It also provides verbose output for each validation step and a warning if the Datum Configuration version is two or more minor versions behind the current PSDesiredStateConfiguration version.

#>
function Test-DatumConfiguration {   
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Object]
        $Datum
    )

    Write-Verbose "[Test-DatumConfiguration] Validating the Datum (datum.yml) Configuration."

    #
    # Validate the LCMConfigurationMode Configuration
    #

    $allowedChangeWindowConfigurationModes = @('ApplyOnly', 'Audit', 'Enforce')
    $allowedConfigurationModes = @('ApplyOnly', 'Audit', 'Enforce', 'Scheduled')
    
    if ($null -eq $Datum.__Definition.LCMConfigurationMode) {
        throw "[Test-DatumConfiguration] The Datum Configuration does not contain the LCMConfigurationMode property. The Datum Configuration is invalid and cannot be processed."
    }

    # Validate that the LCMConfigurationMode contains the required properties.
    if (-not $Datum.__Definition.LCMConfigurationMode.ContainsKey('ConfigurationMode')) {
        throw "[Test-DatumConfiguration] The Datum Configuration LCMConfigurationMode does not contain the ConfigurationMode property. The Datum Configuration is invalid and cannot be processed."
    }

    # Permitted values for ConfigurationMode are: ApplyOnly, Audit, Enforce, Scheduled
    if ($allowedConfigurationModes -notcontains $Datum.__Definition.LCMConfigurationMode.ConfigurationMode) {
        throw "[Test-DatumConfiguration] The Datum Configuration LCMConfigurationMode ConfigurationMode property is not one of the allowed values: $($allowedConfigurationModes -join ', '). The Datum Configuration is invalid and cannot be processed."
    }

    # Validate that the ConfigurationMode is one of the allowed values.
    if (-not $Datum.__Definition.LCMConfigurationMode.ContainsKey('ChangeWindows')) {
        throw "[Test-DatumConfiguration] The Datum Configuration LCMConfigurationMode does not contain the ChangeWindows property. The Datum Configuration is invalid and cannot be processed."
    }

    # Validate the properties of the ChangeWindows array.
    ForEach ($ChangeWindow in $Datum.__Definition.LCMConfigurationMode.ChangeWindows) {
        if (-not $ChangeWindow.ContainsKey('StartTime') -or -not $ChangeWindow.ContainsKey('EndTime') -or -not $ChangeWindow.ContainsKey('ConfigurationMode')) {
            throw "[Test-DatumConfiguration] Each ChangeWindow in the Datum Configuration LCMConfigurationMode must contain StartTime, EndTime, and ConfigurationMode properties. The Datum Configuration is invalid and cannot be processed."
        }
        # Permitted values for ConfigurationMode in ChangeWindows are: ApplyOnly, Audit, Enforce
        if ($allowedChangeWindowConfigurationModes -notcontains $ChangeWindow.ConfigurationMode) {
            throw "[Test-DatumConfiguration] The ConfigurationMode property in each ChangeWindow of the Datum Configuration LCMConfigurationMode must be one of the allowed values: $($allowedChangeWindowConfigurationModes -join ', '). The Datum Configuration is invalid and cannot be processed."
        }
        # Validate that Start and End are time strings are in the correct 24-hour format.
        if (-not ($ChangeWindow.StartTime -match '^\d{2}:\d{2}$') -or -not ($ChangeWindow.EndTime -match '^\d{2}:\d{2}$')) {
            throw "[Test-DatumConfiguration] The StartTime and EndTime properties in the ChangeWindow must be in the format HH:mm (24-hour format). The Datum Configuration is invalid and cannot be processed."
        }
        # Ensure that the StartTime and EndTime are in 24-hour format.
        try {
            $null = [datetime]::ParseExact($ChangeWindow.StartTime, "HH:mm", $null)
            $null = [datetime]::ParseExact($ChangeWindow.EndTime, "HH:mm", $null)
        } catch {
            throw "[Test-DatumConfiguration] The StartTime and EndTime properties in the ChangeWindow must be valid time strings in the format HH:mm (24-hour format). The Datum Configuration is invalid and cannot be processed."
        }
        # Validate DaysOfWeek if the optional property is present.
        $validDays = @('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')
        if ($null -ne $ChangeWindow.DaysOfWeek -and $ChangeWindow.DaysOfWeek.Count -gt 0) {
            foreach ($day in $ChangeWindow.DaysOfWeek) {
                if ($validDays -inotcontains $day) {
                    throw "[Test-DatumConfiguration] Invalid DaysOfWeek value '$day' in ChangeWindow. Valid values are: $($validDays -join ', '). The Datum Configuration is invalid and cannot be processed."
                }
            }
        }
    }
    
    # Validate that the ConfigurationMode is one of the allowed values.
    $allowedConfigurationModes = @('ApplyOnly', 'Audit', 'Enforce', 'Scheduled')
    if ($Datum.__Definition.LCMConfigurationMode.ConfigurationMode -and 
        -not $allowedConfigurationModes -contains $Datum.__Definition.LCMConfigurationMode.ConfigurationMode) {
        throw "[Test-DatumConfiguration] The Datum Configuration LCMConfigurationMode ConfigurationMode property is not one of the allowed values: $($allowedConfigurationModes -join ', '). The Datum Configuration is invalid and cannot be processed."
    }
    # Ensure that ChangeWindows contains at least one entry if ConfigurationMode is 'Scheduled'.
    if ($Datum.__Definition.LCMConfigurationMode.ConfigurationMode -eq 'Scheduled' -and 
        -not $Datum.__Definition.LCMConfigurationMode.ChangeWindows.Count -ne 0) {
        throw "[Test-DatumConfiguration] The Datum Configuration LCMConfigurationMode ChangeWindows property must contain at least one entry when the ConfigurationMode is 'Scheduled'. The Datum Configuration is invalid and cannot be processed."
    }
    
    #
    # LCM Configuration Versioning
    #

    # Validate that the Datum Configuration meets the requirements for the Datum Configuration.
    if ($null -eq $Datum.__Definition.LCMConfigSettings) {
        throw "[Test-DatumConfiguration] The Datum Configuration does not contain the LCMConfigSettings property. The Datum Configuration is invalid and cannot be processed."
    }

    # Validate that the Datum Configuration Versioning is the correct version. If not, throw an error.

    # Get the Datum Configuration Version
    $LCMConfiguration = @{
        DatumConfigurationVersion       = $Datum.__Definition.LCMConfigSettings.ConfigurationVersion -as [Version]
        AZDOLCMVersion                  = $Datum.__Definition.LCMConfigSettings.AZDOLCMVersion -as [Version]
        YAMLConfigurationMinimumVersion = $ModuleConfigurationData.YAMLConfigurationMinimumVersion -as [Version]
        YAMLConfigurationMaximumVersion = $ModuleConfigurationData.YAMLConfigurationMaximumVersion -as [Version]
        AZDOLCMMinimumVersion           = $ModuleConfigurationData.AZDOLCMMinimumVersion -as [Version]
        AZDOLCMMaximumVersion           = $ModuleConfigurationData.AZDOLCMMaximumVersion -as [Version]
        CurrentAZDOLCMVersion           = (Get-Module azdo-dsc-lcm | Select-Object -First 1).Version
    }

    $CurrentPSDesiredStateConfigurationVersion = (Get-Module PSDesiredStateConfiguration | Select-Object -First 1).Version

    Write-Verbose "[Test-DatumConfiguration] Datum Configuration Version: $($LCMConfiguration.DatumConfigurationVersion)"

    # Confirm that all the Datum Configuration Versions have been safely typecasted to the [Version] type.
    foreach ($LCMConfigurationKey in $LCMConfiguration.Keys) {
        Write-Verbose "[Test-DatumConfiguration] Validating Datum Configuration Version for $LCMConfigurationKey."
        if ($null -eq $LCMConfiguration[$LCMConfigurationKey]) {
            throw "[Test-DatumConfiguration] The Datum Configuration Version for $LCMConfigurationKey is not a valid version. The Datum Configuration is invalid and cannot be processed. Please ensure that the Datum Configuration Version is a valid version."
        }
    }

    #
    # Validate the Datum Configuration Versioning
    #

    $supportedConfigurationMaxMajorVersion = $LCMConfiguration.YAMLConfigurationMaximumVersion.Major
    $supportedConfigurationMaxMinorVersion = $LCMConfiguration.YAMLConfigurationMaximumVersion.Minor
    $supportedConfigurationMinMajorVersion = $LCMConfiguration.YAMLConfigurationMinimumVersion.Major
    $supportedConfigurationMinMinorVersion = $LCMConfiguration.YAMLConfigurationMinimumVersion.Minor

    $datumConfigurationMajorVersion = $LCMConfiguration.DatumConfigurationVersion.Major
    $datumConfigurationMinorVersion = $LCMConfiguration.DatumConfigurationVersion.Minor

    # Combine the Major and Minor versions as a decimal number to compare the versions.
    $maxSupportedVersion = [decimal]::Parse("$supportedConfigurationMaxMajorVersion.$supportedConfigurationMaxMinorVersion")
    $minSupportedVersion = [decimal]::Parse("$supportedConfigurationMinMajorVersion.$supportedConfigurationMinMinorVersion")

    $currentVersion = [decimal]::Parse("$datumConfigurationMajorVersion.$datumConfigurationMinorVersion")
    
    # Throw an error if the Datum Configuration Version is outside the valid range of the Datum Configuration Versions.
    if (($currentVersion -lt $minSupportedVersion) -or ($currentVersion -gt $maxSupportedVersion)) {
        throw "[Test-DatumConfiguration] The Datum Configuration Version $($LCMConfiguration.DatumConfigurationVersion) is outside the valid range ($($LCMConfiguration.YAMLConfigurationMinimumVersion) to $($LCMConfiguration.YAMLConfigurationMaximumVersion)). The Datum Configuration is invalid and cannot be processed."
    }

    # Check if the Datum Configuration Version is two or more minor versions behind the current PSDesiredStateConfiguration version.
    # If it is, write a warning.
    if ($currentVersion -ge ($maxSupportedVersion - 0.2)) {
        Write-Warning "[Test-DatumConfiguration] The Datum Configuration Version $($LCMConfiguration.DatumConfigurationVersion) is two or more minor versions behind the current PSDesiredStateConfiguration version $($LCMConfiguration.CurrentPSDesiredStateConfigurationVersion). Consider updating to a more recent version."
    }

    #
    # Validate the PSDesiredStateConfiguration Versions
    #

    $PSDesiredStateConfigurationMinimumVersion = $ModuleConfigurationData.PSDesiredStateConfigurationMinimumVersion -as [Version]
    $PSDesiredStateConfigurationMaximumVersion = $ModuleConfigurationData.PSDesiredStateConfigurationMaximumVersion -as [Version]

    # Ensure that the Module PSDesiredStateConfiguration Version is within the valid range of the Datum Configuration Versions.
    if ($CurrentPSDesiredStateConfigurationVersion -lt $PSDesiredStateConfigurationMinimumVersion -or 
        $CurrentPSDesiredStateConfigurationVersion -gt $PSDesiredStateConfigurationMaximumVersion) {
        throw "[Test-DatumConfiguration] The PSDesiredStateConfiguration Version $($CurrentPSDesiredStateConfigurationVersion) is outside the valid range ($($PSDesiredStateConfigurationMinimumVersion) to $($PSDesiredStateConfigurationMaximumVersion)). The Datum Configuration is invalid and cannot be processed."
    }

    #
    # Validate the azdo-dsc-lcm Versions
    #

    # Ensure that the Module azdo-dsc-lcm Version is within the valid range of the Datum Configuration Versions.
    if ($LCMConfiguration.CurrentAZDOLCMVersion -lt $LCMConfiguration.AZDOLCMMinimumVersion -or 
        $LCMConfiguration.CurrentAZDOLCMVersion -gt $LCMConfiguration.AZDOLCMMaximumVersion) {
        throw "[Test-DatumConfiguration] The azdo-dsc-lcm Version $($LCMConfiguration.CurrentAZDOLCMVersion) is outside the valid range ($($LCMConfiguration.AZDOLCMMinimumVersion) to $($LCMConfiguration.AZDOLCMMaximumVersion)). The Datum Configuration is invalid and cannot be processed."
    }

}
