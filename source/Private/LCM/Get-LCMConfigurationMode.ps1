<#
.SYNOPSIS
    Determines the Local Configuration Manager (LCM) Configuration Mode based on the provided Datum Configuration.

.DESCRIPTION
    The Get-LCMConfigurationMode function calculates the LCM Configuration Mode for a given Datum Configuration object. It supports both static modes (ApplyOnly, Audit, Enforce) and a Scheduled mode that allows for time-based configuration changes.

.PARAMETER DatumConfigurationMode
    The Datum Configuration object that contains the LCMConfigurationMode property. This property can either be a static mode or a Scheduled mode with defined Change Windows.
    Example of DatumConfigurationMode:

    LCMConfigurationMode:
        # The LCM Configuration Mode can be one of the following: ApplyOnly, Audit, Enforce, Scheduled
        ConfigurationMode: Audit
        # Define a Change Window Array that specifies when the configuration can be applied.
        ChangeWindows:
            - StartTime: '20:00' # Start of the change window. Time is in UTC.
            EndTime: '24:00' # End of the change window. Time is in UTC.
            ConfigurationMode: Audit # The configuration mode for this change window.
            - StartTime: '00:00'
            EndTime: '02:00'
            ConfigurationMode: Enforce

#>
function Get-LCMConfigurationMode {
    param(
        [Parameter(Mandatory = $true)]
        [HashTable]$DatumConfigurationMode
    )

    <#
    
    # Define the LCM Configuration Mode for the Datum Configuration.
    LCMConfigurationMode:
        # The LCM Configuration Mode can be one of the following: ApplyOnly, Audit, Enforce, Scheduled
        ConfigurationMode: Audit
        # Define a Change Window Array that specifies when the configuration can be applied.
        ChangeWindows:
            - StartTime: '20:00' # Start of the change window. Time is in UTC.
            EndTime: '24:00' # End of the change window. Time is in UTC.
            ConfigurationMode: Audit # The configuration mode for this change window.
            - StartTime: '00:00'
            EndTime: '02:00'
            ConfigurationMode: Enforce
    #>

    Write-Verbose "[Get-LCMConfigurationMode] Determining LCM Configuration Mode for Datum Configuration: $DatumConfigurationMode"

    #
    # Caculate the LCM Configuration Mode based on the Datum Configuration Mode
    
    # Set the top-level LCM Configuration Mode
    if ($DatumConfigurationMode.ConfigurationMode -eq 'Scheduled') {        
        
        # Iterate through each Change Window to determine the current Configuration Mode based on the current time. If there are overlapping windows, the first one in the list takes precedence.
        $CurrentTimeUTC = (Get-Date).ToUniversalTime().ToString('HH:mm')
        $LCMConfigurationMode = 'Audit' # Default to Audit if no windows match
        $isSet = $false

        foreach ($ChangeWindow in $DatumConfigurationMode.ChangeWindows) {
            if ($CurrentTimeUTC -ge $ChangeWindow.StartTime -and $CurrentTimeUTC -lt $ChangeWindow.EndTime) {

                Write-Host "[Get-LCMConfigurationMode] Current time $CurrentTimeUTC is within Change Window: $($ChangeWindow.StartTime) - $($ChangeWindow.EndTime). Setting LCM Configuration Mode to $($ChangeWindow.ConfigurationMode)."

                if ($isSet) {
                    Write-Warning "[Get-LCMConfigurationMode] Overlapping Change Windows detected in Datum Configuration LCMConfigurationMode. The first matching window takes precedence."
                }

                $isSet = $true
                $LCMConfigurationMode = $ChangeWindow.ConfigurationMode                
            }
        }

    } else {
        # For non-scheduled modes, set the LCM Configuration Mode to the specified mode. Please note that the configuration was validated earlier.
        $LCMConfigurationMode = $DatumConfigurationMode.ConfigurationMode
    }

    return $LCMConfigurationMode

}