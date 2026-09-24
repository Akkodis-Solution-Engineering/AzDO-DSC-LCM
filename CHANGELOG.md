# Change log for AzureDevOpsDsc

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Stub/Partial Configuration: Enables merging of properties within the pipeline runner at an elevated level for enhanced flexibility.
- Added `executionMethodOverride` property to DSC-Based Resources.
- Added Datum.yaml PipelineConfigurationMode property. Introduced CaC Change Windows.
- Added `-ContinueOnError` switch to cascade resource failures to dependents while allowing independent resources to continue.
- Added `Invoke-DscRunner` public function exposing the pipeline runner's generic orchestration logic (Datum compilation, configuration-mode resolution, per-file resource execution) without any Azure DevOps authentication dependency, enabling non-Azure-DevOps DSC resource modules to use the runner.

### Changed

- Replaced "Set" and "Test" modes with "ApplyOnly", "Audit", "Enforce" and "Scheduled"
- Refactored DSC Resources to be classed-based.
- The runner will perform an additional 'Test' after 'Set' to validate that setting has been applied correctly.
- `AzureDevOpsDsc` and `AzureDevOpsDsc.Common` are no longer hard `RequiredModules` for the `DSC.PipelineRunner.Akkodis` module manifest; `Invoke-DscPipelineRunner` now checks for `AzureDevOpsDsc.Common` at call time instead, so `Import-Module DSC.PipelineRunner.Akkodis` no longer requires them to be installed.
- The `AZDODSC_CACHE_DIRECTORY` environment variable check moved from the generic `Invoke-DscRunner` to `Invoke-DscPipelineRunner`, since it's only read by the `AzureDevOpsDsc` resources themselves, not by the pipeline runner engine.

### Fixed

- `Test-DatumConfiguration` called `.ContainsKey()` on the `PipelineConfigurationMode` block,
  but Datum returns an `OrderedDictionary`, which has no such method, so every real Datum.yml
  failed validation. It now uses `.Contains()`.
- `Test-DatumConfiguration` checked the installed `DSC.PipelineRunner.Akkodis` version against the
  `DSCResource*` bounds (1.0-1.9), which rejects every 0.x release. It now uses
  `PipelineRunnerMinimumVersion`/`PipelineRunnerMaximumVersion`, and the minimum was lowered to
  `0.0.1`.
- `Invoke-DscRunner` looked for `datum.yml`; the file is `Datum.yml`, and the lookup is
  case-sensitive on Linux.
- Integration suites no longer leak process environment variables into later suites, and
  `upload-artifact` was bumped to v4.
- Integration test fixtures used a `PipelineRunnerVersionSettings` block that the runner never
  reads; they now use `PipelineRunnerSettings`.
- `Example Configuration`, the README and the wiki now follow the upstream Dsc.PipelineRunner
  naming: the `AzureDevOpsDscNative` resource module, `PipelineRunnerSettings`,
  `$(variables('Name'))` accessors and `preCondition`. The example adds a working composite
  resource (`CompositeResources/ConfigurationRepository.yml`) and stub resource. The README's
  `ChangeWindows` example was not valid YAML and has been fixed. The Composite and Stub
  Resources wiki page now describes how stub merging actually behaves: the merge is additive, a
  missing target only warns, and `mergable` is not enforced.
- Issues with Build script running on 'ubuntu-latest'. Issues with pwsh core handling classes.
- Fixed Bugs within the Symantec Versioning script. Wasn't detecting tag versions.
- The module manifest listed all seven public commands under `CmdletsToExport` instead of
  `FunctionsToExport`, even though every one of them is an advanced function, not a binary
  cmdlet - `Import-Module DSC.PipelineRunner.Akkodis` exported none of its public commands.
  Moved them to `FunctionsToExport` (and added `ConvertTo-DscV3ConfigurationDocument`, which
  wasn't listed anywhere) and set `CmdletsToExport = @()`. Also tightened `VariablesToExport`
  from `'*'` to `@()`, which previously leaked the module's internal `$references`/`$variables`/
  `$parameters` state into every caller's session.
