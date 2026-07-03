# Change log for AzureDevOpsDsc

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Stub/Partial Configuration: Enables merging of properties within the LCM at an elevated level for enhanced flexibility.
- Added `executionMethodOverride` property to DSC-Based Resources.
- Added Datum.yaml LCMConfigurationMode property. Introduced CaC Change Windows.
- Added `-ContinueOnError` switch to cascade resource failures to dependents while allowing independent resources to continue.
- Added `Invoke-DscLCM` public function exposing the LCM's generic orchestration logic (Datum compilation, configuration-mode resolution, per-file LCM execution) without any Azure DevOps authentication dependency, enabling non-Azure-DevOps DSC resource modules to use the LCM.

### Changed

- Replaced "Set" and "Test" modes with "ApplyOnly", "Audit", "Enforce" and "Scheduled"
- Refactored DSC Resources to be classed-based.
- LCM will perform an additional 'Test' after 'Set' to validate that setting has been applied correctly.
- `AzureDevOpsDsc` and `AzureDevOpsDsc.Common` are no longer hard `RequiredModules` for the `azdo-dsc-lcm` module manifest; `Invoke-AZDoLCM` now checks for `AzureDevOpsDsc.Common` at call time instead, so `Import-Module azdo-dsc-lcm` no longer requires them to be installed.
- The `AZDODSC_CACHE_DIRECTORY` environment variable check moved from the generic `Invoke-DscLCM` to `Invoke-AZDoLCM`, since it's only read by the `AzureDevOpsDsc` resources themselves, not by the LCM engine.

### Fixed

- Issues with Build script running on 'ubuntu-latest'. Issues with pwsh core handling classes.
- Fixed Bugs within the Symantec Versioning script. Wasn't detecting tag versions.
