# Every other suite in this folder dot-sources functions out of source/ and mocks the edges. This
# one tests what ships: it imports the BUILT module from output/, writes a real Datum
# configuration source, and runs the public Invoke-DscRunner entry point over it - Datum compile,
# validation, Start-DscRunner, the real DscV2 engine and a real Invoke-DscResource against the
# PipelineRunnerFile fixture resource - with no mocks anywhere.
#
# Whether it can run is decided by Get-PipelineEndToEndSkipReason (Tests/TestHelpers); see
# SecretManagementCredential.Integration.tests.ps1 for why the probe is called twice.

$script:EndToEndSkipReason = Get-PipelineEndToEndSkipReason
$script:EndToEndAvailable  = [string]::IsNullOrEmpty($script:EndToEndSkipReason)

if (-not $script:EndToEndAvailable) {
    Write-Warning "[PipelineEndToEnd.Integration] Skipping the end-to-end pipeline tests: $($script:EndToEndSkipReason)"
}

Describe "The built module's pipeline, end to end against a real DSC v2 resource" -Tag Integration, DscV2SelfHosted {

    BeforeAll {
        # Suites share one process; see Save-ProcessEnvironment for why this matters.
        $script:ProcessEnvironment = Save-ProcessEnvironment
        $script:EndToEndAvailable  = [string]::IsNullOrEmpty((Get-PipelineEndToEndSkipReason))

        if ($script:EndToEndAvailable) {
            $manifest = Get-BuiltModuleManifest

            # Build-DatumConfiguration compiles in a fresh runspace that imports the module BY
            # NAME, so the build output has to be on PSModulePath, ahead of any installed copy.
            # The fixture resource has to be there too for Invoke-DscResource to find it.
            $builtRoot   = Split-Path -Parent (Split-Path -Parent $manifest.FullName)
            $fixtureRoot = Join-Path $Global:RepositoryRoot 'Tests/Fixtures/DscV2'
            $env:PSModulePath = $builtRoot, $fixtureRoot, $env:PSModulePath -join [System.IO.Path]::PathSeparator

            Get-Module -Name DSC.PipelineRunner.Akkodis | Remove-Module -Force
            $script:Module = Import-Module -Name $manifest.FullName -Force -PassThru -ErrorAction Stop

            $script:StateDirectory = Join-Path $TestDrive 'State'
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
  ConfigurationVersion: 0.1
  PipelineRunnerVersion: 0.2
  DSCResourceVersion: 2.0

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

            # Two resources with a dependency, so the run also proves ordering and the
            # dependency path through the real engine, not only a single call.
            Set-Content -LiteralPath (Join-Path $script:SourceDirectory 'Projects/Present/EndToEnd.yml') -Value @"
parameters: {}

variables: {
  StatePath: '$($script:StateDirectory)'
}

resources:

  - name: First
    type: PipelineRunnerTestResource/PipelineRunnerFile
    properties:
      Name: first
      Path: `$StatePath
      Ensure: Present

  - name: Second
    type: PipelineRunnerTestResource/PipelineRunnerFile
    dependsOn:
      - PipelineRunnerTestResource/PipelineRunnerFile/First
    properties:
      Name: second
      Path: `$StatePath
      Ensure: Present
"@

            function Invoke-EndToEndRun {
                param([Parameter(Mandatory)][ValidateSet('Audit', 'Enforce')][string]$ConfigurationMode)
                Invoke-DscRunner -exportConfigDir $script:ExportDirectory -ConfigurationSourcePath $script:SourceDirectory `
                    -ConfigurationMode $ConfigurationMode -Engine DscV2 -ErrorAction SilentlyContinue
            }
        }
    }

    AfterAll {
        if ($script:Module) { Remove-Module -ModuleInfo $script:Module -Force -ErrorAction SilentlyContinue }
        Restore-ProcessEnvironment -Snapshot $script:ProcessEnvironment
    }

    It "is loaded from the build output, not from source" -Skip:(-not $script:EndToEndAvailable) {
        $script:Module.ModuleBase | Should -BeLike (Join-Path $Global:RepositoryRoot 'output*')
        (Get-Command Invoke-DscRunner).Module.ModuleBase | Should -Be $script:Module.ModuleBase
    }

    It "reports drift in Audit mode without changing anything" -Skip:(-not $script:EndToEndAvailable) {
        $result = Invoke-EndToEndRun -ConfigurationMode Audit

        $result.TotalConfigurations | Should -Be 1
        $result.FailCount           | Should -Be 2
        Test-Path -LiteralPath $script:StateDirectory | Should -BeFalse
    }

    It "brings the node into its desired state in Enforce mode" -Skip:(-not $script:EndToEndAvailable) {
        $result = Invoke-EndToEndRun -ConfigurationMode Enforce

        $result.FailCount | Should -Be 0
        $result.PassCount | Should -Be 2
        Test-Path -LiteralPath (Join-Path $script:StateDirectory 'first.marker')  | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:StateDirectory 'second.marker') | Should -BeTrue
    }

    It "reports no drift in Audit mode once enforced" -Skip:(-not $script:EndToEndAvailable) {
        $result = Invoke-EndToEndRun -ConfigurationMode Audit

        $result.FailCount | Should -Be 0
        $result.PassCount | Should -Be 2
    }
}
