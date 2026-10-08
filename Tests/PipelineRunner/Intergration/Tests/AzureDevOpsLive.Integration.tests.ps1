# The built module's Azure DevOps entry point, end to end against a REAL Azure DevOps
# organization through the AzureDevOpsDscNative resource module - no mocks anywhere.
#
# Invoke-DscPipelineRunner signs in with AuthenticationType 'ManagedIdentity' as the Azure
# Arc-enabled runner's managed identity, which must be a member of AZUREDEVOPSORG allowed to
# create and delete projects. Each run works in its own throwaway project:
#
#   * AzDoProject       - lcm-ci-<run>-<attempt>
#   * AzDoGitRepository - a repository inside it, dependsOn the project
#
# and takes them through Test (Audit), Set (Enforce), Test again (Audit, now clean) and Get, then
# deletes the project with an Ensure = Absent run. AfterAll repeats that deletion best-effort so
# a failed run does not leave a project behind.
#
# Whether it can run is decided by Get-AzureDevOpsLiveSkipReason (Tests/TestHelpers); see
# SecretManagementCredential.Integration.tests.ps1 for why the probe is called twice.

$script:AzDoSkipReason = Get-AzureDevOpsLiveSkipReason
$script:AzDoAvailable  = [string]::IsNullOrEmpty($script:AzDoSkipReason)

if (-not $script:AzDoAvailable) {
    Write-Warning "[AzureDevOpsLive.Integration] Skipping the live Azure DevOps tests: $($script:AzDoSkipReason)"
}

Describe "The built module's Azure DevOps pipeline against a live organization (AzureDevOpsDscNative)" -Tag Integration, AzureDevOpsLive {

    BeforeAll {
        # Suites share one process; see Save-ProcessEnvironment for why this matters.
        $script:ProcessEnvironment = Save-ProcessEnvironment
        $script:AzDoAvailable      = [string]::IsNullOrEmpty((Get-AzureDevOpsLiveSkipReason))

        $runSuffix = if ($env:GITHUB_RUN_ID) { "$($env:GITHUB_RUN_ID)-$($env:GITHUB_RUN_ATTEMPT)" } else { [guid]::NewGuid().ToString('N').Substring(0, 12) }
        $script:ProjectName    = "lcm-ci-$runSuffix"
        $script:RepositoryName = 'lcm-ci-repository'
        $script:ProjectCreated = $false

        if ($script:AzDoAvailable) {
            $manifest = Get-BuiltModuleManifest

            # Build-DatumConfiguration compiles in a fresh runspace that imports the module BY
            # NAME, so the build output has to be on PSModulePath, ahead of any installed copy.
            # AzureDevOpsDscNative's bundled AzureDevOpsDsc.Common goes first too:
            # Invoke-DscPipelineRunner.tests.ps1 installs a MOCK AzureDevOpsDsc.Common into the
            # user's module folder, which must never be the one this suite signs in with.
            $builtRoot = Split-Path -Parent (Split-Path -Parent $manifest.FullName)
            $native = Get-Module -ListAvailable -Name AzureDevOpsDscNative | Sort-Object Version -Descending | Select-Object -First 1
            $env:PSModulePath = $builtRoot, (Join-Path $native.ModuleBase 'Modules'), $env:PSModulePath -join [System.IO.Path]::PathSeparator
            Get-Module -Name AzureDevOpsDsc.Common | Remove-Module -Force

            Get-Module -Name DSC.PipelineRunner.Akkodis | Remove-Module -Force
            $script:Module = Import-Module -Name $manifest.FullName -Force -PassThru -ErrorAction Stop

            # AzureDevOpsDscNative keeps its token and lookup caches here; every resource
            # constructor reads ModuleSettings.clixml from it.
            $env:AZDODSC_CACHE_DIRECTORY = Join-Path $TestDrive 'Cache'
            New-Item -ItemType Directory -Path $env:AZDODSC_CACHE_DIRECTORY -Force | Out-Null

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

            # 'Present' declares the project and a repository in it. 'Absent' declares only the
            # project: deleting it deletes the repository with it, and a separate repository
            # resource would then be evaluated against a project that no longer exists.
            function Set-AzDoConfiguration {
                param([Parameter(Mandatory)][ValidateSet('Present', 'Absent')][string]$Ensure)

                $repository = if ($Ensure -eq 'Present') {
                    @"

  - name: CI Repository
    type: AzureDevOpsDscNative/AzDoGitRepository
    dependsOn:
      - AzureDevOpsDscNative/AzDoProject/CI Project
    properties:
      ProjectName: `$ProjectName
      RepositoryName: `$RepositoryName
      Ensure: Present
"@
                }

                Set-Content -LiteralPath (Join-Path $script:SourceDirectory 'Projects/Present/AzDo.yml') -Value @"
parameters: {}

variables: {
  ProjectName: '$($script:ProjectName)',
  RepositoryName: '$($script:RepositoryName)'
}

resources:

  - name: CI Project
    type: AzureDevOpsDscNative/AzDoProject
    properties:
      ProjectName: `$ProjectName
      ProjectDescription: 'Created by the AzDO-DSC-LCM integration tests; deleted at the end of the run.'
      SourceControlType: Git
      ProcessTemplate: Agile
      Visibility: Private
      Ensure: $Ensure
$repository
"@
            }

            # GitHub's log viewer folds a failed test's message away, so every run also prints
            # what each resource did - the cause of a failure is then readable straight from
            # the job log.
            function Invoke-AzDoRun {
                param([Parameter(Mandatory)][ValidateSet('Audit', 'Enforce')][string]$ConfigurationMode)
                $runErrors = $null
                try {
                    $result = Invoke-DscPipelineRunner -AzureDevopsOrganizationName $env:AZUREDEVOPSORG -AuthenticationType ManagedIdentity `
                        -JITToken 'unused-local-configuration-source' `
                        -exportConfigDir $script:ExportDirectory -ConfigurationSourcePath $script:SourceDirectory `
                        -ConfigurationMode $ConfigurationMode -Engine DscV2 -ErrorAction SilentlyContinue -ErrorVariable runErrors
                }
                catch {
                    Write-Host "[AzureDevOpsLive.Integration] $ConfigurationMode run threw: $($_.Exception.Message)"
                    Write-Host $_.ScriptStackTrace
                    throw
                }

                Write-Host "[AzureDevOpsLive.Integration] $ConfigurationMode run: Status=$($result.Status) Configurations=$($result.TotalConfigurations) Pass=$($result.PassCount) Fail=$($result.FailCount) Skip=$($result.SkipCount)"
                foreach ($configuration in @($result.Configurations)) {
                    foreach ($resource in @($configuration.Results)) {
                        Write-Host "[AzureDevOpsLive.Integration]   [$($resource.Status)] $($resource.InstanceName) $($resource.ErrorMessage)"
                    }
                }
                foreach ($runError in @($runErrors)) {
                    Write-Host "[AzureDevOpsLive.Integration]   error: $runError"
                }

                [pscustomobject]@{ Result = $result; Errors = @($runErrors) }
            }

            function Invoke-AzDoGet {
                param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][hashtable]$Property)
                $engineActionPath = Join-Path $script:Module.ModuleBase 'Actions/Engine/DscV2.ps1'
                try {
                    $raw = (& $engineActionPath -Context @{ Method = 'Get'; ModuleName = 'AzureDevOpsDscNative'; Name = $Name; Property = $Property }).Raw
                }
                catch {
                    Write-Host "[AzureDevOpsLive.Integration] Get $Name threw: $($_.Exception.Message)"
                    throw
                }
                Write-Host "[AzureDevOpsLive.Integration] Get $Name returned: $($raw | ConvertTo-Json -Depth 3 -Compress -WarningAction SilentlyContinue)"
                $raw
            }

            # Whether Get found the resource. AzureDevOpsDscNative's Get functions leave Ensure at
            # Absent even when the resource exists; existence is the lookup's DSCGetSummaryState,
            # NotFound (2) when it is missing and Changed (0) / Unchanged (1) when it is there.
            function Test-AzDoGetFound {
                param([Parameter(Mandatory)]$GetResult)
                $status = $GetResult.LookupResult.status
                if ($null -eq $status) { throw "Get returned no LookupResult.status to tell whether the resource exists." }
                [int]$status -ne 2
            }

            Set-AzDoConfiguration -Ensure Present
        }
    }

    AfterAll {
        # Never leave a project behind in the organization, whatever failed above.
        if ($script:AzDoAvailable -and $script:ProjectCreated) {
            try {
                Set-AzDoConfiguration -Ensure Absent
                $null = Invoke-AzDoRun -ConfigurationMode Enforce
            }
            catch {
                Write-Warning "[AzureDevOpsLive.Integration] Could not delete project [$($script:ProjectName)]; remove it by hand: $($_.Exception.Message)"
            }
        }

        if ($script:Module) { Remove-Module -ModuleInfo $script:Module -Force -ErrorAction SilentlyContinue }
        Restore-ProcessEnvironment -Snapshot $script:ProcessEnvironment
    }

    It "Test: reports drift in Audit mode while the project does not exist" -Skip:(-not $script:AzDoAvailable) {
        $run = Invoke-AzDoRun -ConfigurationMode Audit

        $run.Result.TotalConfigurations | Should -Be 1
        $run.Result.FailCount           | Should -BeGreaterThan 0
        $run.Result.PassCount           | Should -Be 0
    }

    It "Set: creates the project and its repository in Enforce mode" -Skip:(-not $script:AzDoAvailable) {
        # From here on AfterAll must clean up, even if this test fails part-way.
        $script:ProjectCreated = $true

        $run = Invoke-AzDoRun -ConfigurationMode Enforce

        $run.Result.FailCount | Should -Be 0
        $run.Result.PassCount | Should -Be 2
        @($run.Errors | Where-Object { "$_" -like "*'Get' method failed*" }) | Should -BeNullOrEmpty
    }

    It "Test: reports no drift in Audit mode once enforced" -Skip:(-not $script:AzDoAvailable) {
        $run = Invoke-AzDoRun -ConfigurationMode Audit

        $run.Result.FailCount | Should -Be 0
        $run.Result.PassCount | Should -Be 2
    }

    It "Get: reads the project and repository back from the organization" -Skip:(-not $script:AzDoAvailable) {
        $project = Invoke-AzDoGet -Name 'AzDoProject' -Property @{ ProjectName = $script:ProjectName }
        $project.ProjectName | Should -Be $script:ProjectName
        Test-AzDoGetFound -GetResult $project | Should -BeTrue

        $repository = Invoke-AzDoGet -Name 'AzDoGitRepository' -Property @{ ProjectName = $script:ProjectName; RepositoryName = $script:RepositoryName }
        $repository.RepositoryName | Should -Be $script:RepositoryName
        Test-AzDoGetFound -GetResult $repository | Should -BeTrue
    }

    It "Set: deletes the project again with Ensure = Absent" -Skip:(-not $script:AzDoAvailable) {
        Set-AzDoConfiguration -Ensure Absent

        $run = Invoke-AzDoRun -ConfigurationMode Enforce

        $run.Result.FailCount | Should -Be 0
        $run.Result.PassCount | Should -Be 1
        $script:ProjectCreated = $false

        $project = Invoke-AzDoGet -Name 'AzDoProject' -Property @{ ProjectName = $script:ProjectName }
        Test-AzDoGetFound -GetResult $project | Should -BeFalse
    }
}
