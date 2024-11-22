# Change log for AzureDevOpsDsc

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Stub/Partial Configuration: Enables merging of properties within the LCM at an elevated level for enhanced flexibility.
- Composite Resources: Introduces parameterization in LCM, allowing for the reuse of configuration templates.

### Changed

- LCM will perform an additional 'Test' after 'Set' to validate that setting has been applied correctly.

### Fixed

- Issues with Build script running on 'ubuntu-latest'. Issues with pwsh core handling classes.
- Fixed Bugs within the Symantec Versioning script. Wasn't detecting tag versions.
