# Every other suite in this folder dot-sources functions out of source/ and mocks the edges. This
# one tests what ships: it imports the BUILT module from output/, writes a real Datum
# configuration source, and runs the public Invoke-DscRunner entry point over it - Datum compile,
# validation, Start-DscRunner, the real DscV2 engine and a real Invoke-DscResource - against two
# real resources from Microsoft's PSDscResources module, with no mocks anywhere:
#
#   * Registry    - a string value under a per-run HKCU key
#   * Environment - a per-run MACHINE environment variable, dependsOn the Registry resource
#
# Each resource goes through Test (Audit), Set (Enforce), Test again (Audit, now clean) and Get
# (which the runner calls after every resource, and which the suite also calls directly), then
# an Ensure = Absent pass removes both again. AfterAll cleans up whatever a failed run left.
#
# Whether it can run is decided by Get-PipelineEndToEndSkipReason (Tests/TestHelpers); see
# SecretManagementCredential.Integration.tests.ps1 for why the probe is called twice.

$script:EndToEndSkipReason = Get-PipelineEndToEndSkipReason
$script:EndToEndAvailable  = [string]::IsNullOrEmpty($script:EndToEndSkipReason)

if (-not $script:EndToEndAvailable) {
    Write-Warning "[PipelineEndToEnd.Integration] Skipping the end-to-end pipeline tests: $($script:EndToEndSkipReason)"
}

Describe "The built module's pipeline, end to end against real PSDscResources resources" -Tag Integration, DscV2SelfHosted {

    BeforeAll {
        # Suites share one process; see Save-ProcessEnvironment for why this matters.
        $script:ProcessEnvironment = Save-ProcessEnvironment
        $script:EndToEndAvailable  = [string]::IsNullOrEmpty((Get-PipelineEndToEndSkipReason))

        $runId = [guid]::NewGuid().ToString('N').Substring(0, 12)
        $script:RegistryKey      = "HKEY_CURRENT_USER\Software\DscLcmIntegration\$runId"
        $script:RegistryPSPath   = "Registry::$($script:RegistryKey)"
        $script:RegistryValue    = 'Configured'
        $script:RegistryData     = "lcm-$runId"
        $script:EnvironmentName  = "DSCLCM_INTEGRATION_$runId"
        $script:EnvironmentValue = "lcm-$runId"

        if ($script:EndToEndAvailable) {
            $manifest = Get-BuiltModuleManifest

            # Build-DatumConfiguration compiles in a fresh runspace that imports the module BY
            # NAME, so the build output has to be on PSModulePath, ahead of any installed copy.
            $builtRoot = Split-Path -Parent (Split-Path -Parent $manifest.FullName)
            $env:PSModulePath = $builtRoot + [System.IO.Path]::PathSeparator + $env:PSModulePath

            Get-Module -Name DSC.PipelineRunner.Akkodis | Remove-Module -Force
            $script:Module = Import-Module -Name $manifest.FullName -Force -PassThru -ErrorAction Stop

            $script:ExportDirectory = Join-Path $TestDrive 'Export'
            $script:SourceDirectory = Join-Path $TestDrive 'Source'
            New-Item -ItemType Directory -Path $script:ExportDirectory, (Join-Path $script:SourceDirectory 'Projects/Present'), (Join-Path $script:SourceDirectory 'CompositeResources') -Force | Out-Null

            Set-Content -LiteralPath (Join-Path $script:SourceDirectory 'Datum.yml') -Value @'
ResolutionPrecedence:
  - Projects\$($Node.ProjectPresence)\$($Node.Project)

DatumHandlersThrowOnError: true
default_lookup_options: MostSpecific

PipelineConfigurationMode:
  ConfigurationMode: Audit
  ChangeWindows: []

PipelineRunnerSettings:
  ConfigurationVersion: 0.5
  PipelineRunnerVersion: 0.0.5

DatumHandlers:
  Datum.InvokeCommand::InvokeCommand:
    SkipDuringLoad: true

lookup_options:
  variables:
    merge_hash_array: deep
  resources:
    merge_hash_array: UniqueKeyValTuples
    merge_options:
      tuple_keys:
        - name
'@

            # Writes the node file with every resource at the given Ensure. Values flow through
            # configuration variables, so the run also proves variable resolution end to end.
            function Set-EndToEndConfiguration {
                param([Parameter(Mandatory)][ValidateSet('Present', 'Absent')][string]$Ensure)

                Set-Content -LiteralPath (Join-Path $script:SourceDirectory 'Projects/Present/EndToEnd.yml') -Value @"
parameters: {}

variables: {
  RegistryKey: '$($script:RegistryKey)',
  RegistryValue: '$($script:RegistryValue)',
  RegistryData: '$($script:RegistryData)',
  EnvironmentName: '$($script:EnvironmentName)',
  EnvironmentValue: '$($script:EnvironmentValue)'
}

resources:

  - name: Marker Value
    type: PSDscResources/Registry
    properties:
      Key: `$RegistryKey
      ValueName: `$RegistryValue
      ValueData:
        - `$RegistryData
      ValueType: String
      Force: true
      Ensure: $Ensure

  - name: Marker Variable
    type: PSDscResources/Environment
    dependsOn:
      - PSDscResources/Registry/Marker Value
    properties:
      Name: `$EnvironmentName
      Value: `$EnvironmentValue
      Target:
        - Machine
      Ensure: $Ensure
"@
            }

            # Runs the shipped entry point and also collects the errors it reported, so a
            # failed Get (which the runner downgrades to an error, not a FAIL) is visible.
            function Invoke-EndToEndRun {
                param([Parameter(Mandatory)][ValidateSet('Audit', 'Enforce')][string]$ConfigurationMode)
                $runErrors = $null
                $result = Invoke-DscRunner -exportConfigDir $script:ExportDirectory -ConfigurationSourcePath $script:SourceDirectory `
                    -ConfigurationMode $ConfigurationMode -Engine DscV2 -ErrorAction SilentlyContinue -ErrorVariable runErrors
                [pscustomobject]@{ Result = $result; Errors = @($runErrors) }
            }

            function Get-MachineEnvironmentValue {
                [Environment]::GetEnvironmentVariable($script:EnvironmentName, 'Machine')
            }

            Set-EndToEndConfiguration -Ensure Present
        }
    }

    AfterAll {
        if ($script:Module) { Remove-Module -ModuleInfo $script:Module -Force -ErrorAction SilentlyContinue }
        Restore-ProcessEnvironment -Snapshot $script:ProcessEnvironment

        # Whatever a failed run left behind.
        if ($script:EndToEndAvailable) {
            Remove-Item -LiteralPath $script:RegistryPSPath -Recurse -Force -ErrorAction SilentlyContinue
            [Environment]::SetEnvironmentVariable($script:EnvironmentName, $null, 'Machine')
        }
    }

    It "is loaded from the build output, not from source" -Skip:(-not $script:EndToEndAvailable) {
        $script:Module.ModuleBase | Should -BeLike (Join-Path $Global:RepositoryRoot 'output*')
        (Get-Command Invoke-DscRunner).Module.ModuleBase | Should -Be $script:Module.ModuleBase
    }

    It "Test: reports drift on both resources in Audit mode without changing anything" -Skip:(-not $script:EndToEndAvailable) {
        $run = Invoke-EndToEndRun -ConfigurationMode Audit

        $run.Result.TotalConfigurations | Should -Be 1
        $run.Result.FailCount           | Should -Be 2
        Test-Path -LiteralPath $script:RegistryPSPath | Should -BeFalse
        Get-MachineEnvironmentValue | Should -BeNullOrEmpty
    }

    It "Set: brings both resources into their desired state in Enforce mode" -Skip:(-not $script:EndToEndAvailable) {
        $run = Invoke-EndToEndRun -ConfigurationMode Enforce

        $run.Result.FailCount | Should -Be 0
        $run.Result.PassCount | Should -Be 2
        (Get-ItemProperty -LiteralPath $script:RegistryPSPath -Name $script:RegistryValue).$($script:RegistryValue) | Should -Be $script:RegistryData
        Get-MachineEnvironmentValue | Should -Be $script:EnvironmentValue

        # The runner calls Get after every resource; a failure there is reported, not FAILed.
        @($run.Errors | Where-Object { "$_" -like "*'Get' method failed*" }) | Should -BeNullOrEmpty
    }

    It "Test: reports no drift in Audit mode once enforced" -Skip:(-not $script:EndToEndAvailable) {
        $run = Invoke-EndToEndRun -ConfigurationMode Audit

        $run.Result.FailCount | Should -Be 0
        $run.Result.PassCount | Should -Be 2
    }

    It "Get: returns the enforced state through the shipped DscV2 engine action" -Skip:(-not $script:EndToEndAvailable) {
        $engineActionPath = Join-Path $script:Module.ModuleBase 'Actions/Engine/DscV2.ps1'
        if (-not (Test-Path -LiteralPath $engineActionPath)) {
            $engineActionPath = Join-Path $Global:RepositoryRoot 'Actions/Engine/DscV2.ps1'
        }

        $registry = & $engineActionPath -Context @{
            Method = 'Get'; ModuleName = 'PSDscResources'; Name = 'Registry'
            Property = @{ Key = $script:RegistryKey; ValueName = $script:RegistryValue }
        }
        @($registry.Raw.ValueData) | Should -Be @($script:RegistryData)
        $registry.Raw.Ensure       | Should -Be 'Present'

        $environment = & $engineActionPath -Context @{
            Method = 'Get'; ModuleName = 'PSDscResources'; Name = 'Environment'
            Property = @{ Name = $script:EnvironmentName; Target = @('Machine') }
        }
        $environment.Raw.Value  | Should -Be $script:EnvironmentValue
        $environment.Raw.Ensure | Should -Be 'Present'
    }

    It "Set: removes both resources again with Ensure = Absent" -Skip:(-not $script:EndToEndAvailable) {
        Set-EndToEndConfiguration -Ensure Absent

        $run = Invoke-EndToEndRun -ConfigurationMode Enforce

        $run.Result.FailCount | Should -Be 0
        $run.Result.PassCount | Should -Be 2
        Get-ItemProperty -LiteralPath $script:RegistryPSPath -Name $script:RegistryValue -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-MachineEnvironmentValue | Should -BeNullOrEmpty
    }
}
