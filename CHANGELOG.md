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

- Issues with Build script running on 'ubuntu-latest'. Issues with pwsh core handling classes.
- Fixed Bugs within the Symantec Versioning script. Wasn't detecting tag versions.
