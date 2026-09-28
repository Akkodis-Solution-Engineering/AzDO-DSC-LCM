# DSC.PipelineRunner.Akkodis

[![Development Branch Code Coverage Status](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/actions/workflows/Development.CodeCoverage.yml/badge.svg)](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/actions/workflows/Development.CodeCoverage.yml)
[![Development Intergration Test Status](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/actions/workflows/Development.IntergrationTests.yml/badge.svg)](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/actions/workflows/Development.IntergrationTests.yml)
[![Main Branch Code Coverage Status](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/actions/workflows/Main.CodeCoverage.yml/badge.svg)](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/actions/workflows/Main.CodeCoverage.yml)
[![Main Intergration Test Status](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/actions/workflows/Main.IntergrationTests.yml/badge.svg)](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/actions/workflows/Main.IntergrationTests.yml)
[![Nightly Dev Build](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/actions/workflows/nightly-dev-build.yml/badge.svg)](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/actions/workflows/nightly-dev-build.yml)
[![CodeQL Advanced](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/actions/workflows/codeql.yml/badge.svg)](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/actions/workflows/codeql.yml)
[![Current Code Coverage Status](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/actions/workflows/CodeCoverage.yml/badge.svg)](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/actions/workflows/CodeCoverage.yml)

## Overview

`DSC.PipelineRunner.Akkodis` is a pipeline runner for Desired State Configuration (DSC). Its execution engine is resource-agnostic — it invokes whatever DSC resource module a compiled configuration's `type:` fields reference, so it isn't limited to the `AzureDevOpsDscNative` DSC resource module. It utilizes Datum to merge configuration stubs into larger pieces of configuration which is parsed into the pipeline runner.

Two public entry points build on this same engine:

- `Invoke-DscPipelineRunner`: the Azure DevOps-flavored entry point. Authenticates to Azure DevOps (Managed Identity or PAT) and is the recommended choice for configurations that manage `AzureDevOpsDscNative` resources.
- `Invoke-DscRunner`: a generic entry point with no Azure DevOps dependency at all — no `AzureDevOpsDscNative`/`AzureDevOpsDsc.Common` install required. Use this if your configuration targets other DSC resource modules; authenticate to whatever those resources require using their own mechanism before calling it. See [Using Invoke-DscRunner Directly (Non-Azure DevOps Consumers)](#using-invoke-dscrunner-directly-non-azure-devops-consumers) for details.

## Datum

This module utilizes Datum from Gael Colas to streamline configuration. For more information on how to implement and use it, please refer to the [official documentation or Gael Colas' resources.](https://github.com/gaelcolas/Datum)

A complete, working configuration lives in [`Example Configuration`](Example%20Configuration). The snippets below are taken from it.

### Key Functions

1. __Custom Datum Variable Interpolation__: Perform custom datum variable interpolation before runner initialization using the format `[x={ $Node.Project }=]`.
1. __Calculated Properties__: Utilize PowerShell subexpressions for calculated properties, such as `$( (1 -eq 2 )? $true: $false )`, to dynamically determine values.
1. __Custom Variables__: Define and reference custom variables within resource properties.

    __Variable Configuration__

    ```yaml
    variables:
      ProjectName: 'Test_Project'
      GroupName: 'Custom_Group_Name'
    ```

    __Resource Variable Reference__

    ```yaml
    - name: CON Board Administrators
      preCondition: equals (variables 'ProjectWorkBoardsStatus') 'enabled'
      type: AzureDevOpsDscNative/AzDoProjectGroup
      dependsOn:
        - AzureDevOpsDscNative/AzDoProject/Project
      properties:
        ProjectName: $(variables('ProjectName'))
        GroupName: $(variables('GroupName'))
    ```

1. __Modular Pipeline Formatting and Validation Rules__: Incorporate modular scripts stored in the `\Pipeline Rules\` directory into the module build process. These scripts are responsible for validating and formatting configuration resources to meet specific requirements. They can be modified and extended as needed. The current set of scripts includes:

    - `Pipeline Rules\PreParse\Test-CircularReferences.ps1`: Walks the `dependsOn` graph and
      rejects genuine cycles, including a resource that depends on itself. A resource reached
      by more than one branch — a diamond, or any other shared dependency — is not a cycle and
      is allowed. If this script detects an error, the runner will not apply any changes.
    - `Pipeline Rules\PreParse\Test-ResourcesForIncorrectProperties.ps1`: Validates resource properties against documented specifications. Errors prevent the runner from applying changes.
    - `Pipeline Rules\PreParse\Test-ExecutionScriptsAllowed.ps1`: Rejects any `preExecutionScript`/`postExecutionScript` unless `PipelineRunnerSettings.AllowExecutionScripts` is `true`.
    - `Pipeline Rules\Custom\Merge-StubResources.ps1`: Merges stub (partial) resources into their `merge_with` target.
    - `Pipeline Rules\Custom\Expand-CompositeResources.ps1`: Replaces each composite resource with the resources of the file it links to.
    - `Pipeline Rules\Custom\Sort-DependsOn.ps1`: Orders resources based on their `dependsOn` property. This script is mandatory and cannot be bypassed.
    - `Pipeline Rules\Format\`: Directory reserved for format rules that pre-process task properties before execution.

1. __Versioned Configuration__: Ensure all versions are managed by the pipeline runner to avoid unforeseen issues as new features are introduced.

    __Datum.yml__

    ```yaml
    PipelineRunnerSettings:
      ConfigurationVersion: 0.5
      PipelineRunnerVersion: 0.0.5
      Engine: DscV2
    ```

    `ConfigurationVersion` tracks the configuration's own YAML shape and must be bumped
    whenever the configuration's structure changes; `PipelineRunnerVersion` should reflect
    the `DSC.PipelineRunner.Akkodis` module version the configuration was authored/tested against
    (`ModuleVersion` in `source/DSC.PipelineRunner.Akkodis.psd1`).

    The runner enforces the following version constraints (defined in `source\Public\VersionConfiguration.ps1`):

    | Setting | Minimum | Maximum |
    |---|---|---|
    | `ConfigurationVersion` | `0.1` | `0.9` |
    | `PSDesiredStateConfiguration` module | `2.0` | `2.9` |
    | `DSC.PipelineRunner.Akkodis` module | `0.0.1` | `1.9` |

    See the [PipelineRunnerSettings](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/wiki/PipelineRunnerSettings) wiki page for every key (`Engine`, `AllowExecutionScripts`, `Reboot`, `Target`).

1. __ConfigurationMode Change Windows__: Datum.yml includes a `PipelineConfigurationMode` block that lets administrators specify the ConfigurationMode and the associated change windows. Configuration Modes are:

    - Audit: This mode allows for monitoring and reporting without making any changes to the system (`Test` only).
    - Enforce: In this mode, the system actively applies the defined configurations and then re-tests each changed resource to verify the change landed.
    - ApplyOnly: This mode applies the configurations (`Set`) without re-verifying them afterwards.
    - Scheduled: This mode picks one of the three modes above from the change window that matches the current time.

    Execution Precedence: The following hierarchy determines the order in which the `ConfigurationMode` is applied:

    1. `Invoke-DscPipelineRunner -ConfigurationMode` / `Invoke-DscRunner -ConfigurationMode` parameter. Setting this parameter will override the configuration.
    1. `PipelineConfigurationMode.ConfigurationMode`. Configuring this property will establish it as the default setting. The possible values are 'ApplyOnly', 'Audit', 'Enforce', and 'Scheduled'.
    1. `PipelineConfigurationMode.ChangeWindows`. When `ConfigurationMode` is `Scheduled`, the change windows define the times in UTC when the pipeline runner operates in each mode. _If no change window matches, it will revert to the default mode of 'Audit'. In cases of overlapping time windows, the first window will be chosen, and a warning will be issued._

        ```text
        [Get-PipelineRunnerConfigurationMode] Current time 00:30 (Tuesday) is within Change Window: 00:00-02:00 on [Tuesday, Wednesday, Thursday]. Setting Pipeline Runner Configuration Mode to Enforce.
        [Get-PipelineRunnerConfigurationMode] Overlapping Change Windows detected in Datum Configuration PipelineConfigurationMode. The first matching window takes precedence.
        ```

        Change Window Syntax (a window matches when `StartTime <= now < EndTime`, so a window cannot span midnight — split it into two windows instead):

        ```text
        [ArrayList] ChangeWindows:
            [String] StartTime: UTC start time (HH:mm, inclusive)
            [String] EndTime: UTC end time (HH:mm, exclusive)
            [String] ConfigurationMode: [Audit, Enforce, ApplyOnly]
            [String[]] DaysOfWeek: Optional. Restricts the window to these UTC days.
        ```

        Example:

        ```yaml
        PipelineConfigurationMode:
          # The Pipeline Configuration Mode can be one of the following: ApplyOnly, Audit, Enforce, Scheduled
          ConfigurationMode: Scheduled
          # All times are UTC. The first matching window takes precedence.
          ChangeWindows:
            - StartTime: '20:00'          # Audit every night.
              EndTime: '23:59'
              ConfigurationMode: Audit
            - StartTime: '00:00'          # Enforce only during the Tuesday/Wednesday/Thursday maintenance window.
              EndTime: '02:00'
              ConfigurationMode: Enforce
              DaysOfWeek:
                - Tuesday
                - Wednesday
                - Thursday
        ```

### Enhanced Pipeline Runner Resource Features

The pipeline runner provides a set of features applicable to all Desired State Configuration (DSC) resources, enhancing their flexibility and control. These features include:

- __preCondition__ (formerly `condition`, which is still accepted as a deprecated alias):
  This feature allows conditional execution of resources. The expression is evaluated as a
  PowerShell predicate before the resource runs. If it evaluates to `$true`, the resource
  executes; if it evaluates to `$false`, the resource is skipped. This is useful for
  dynamically controlling resource execution based on specific criteria.

    __Example:__

    ```yaml
    - name: CON Board Administrators
      preCondition: equals (variables 'ProjectWorkBoardsStatus') 'enabled'
      type: AzureDevOpsDscNative/AzDoProjectGroup
    ```

    A preCondition may also call the function-language accessors — an explicit allow-list
    covering lookups (`parameters()`, `variables()`, `reference()`, `using()`), run context
    (`nodeName()`, `configurationFile()`), logic (`equals()`, `not()`), strings and collections
    (`concat()`, `empty()`, `coalesce()`, `toLower()`, `toUpper()`, `startsWith()`,
    `contains()`) and arithmetic (`add()`, `sub()`, `mul()`, `div()`, `mod()`, `min()`,
    `max()`, `int()`, `float()`). Any other command invocation, a variable assignment, or a
    method call is still rejected. There is deliberately no `secret()` accessor: a condition is
    recorded verbatim in the audit record and in every SKIP message it produces, so secrets
    reach a resource through its `resourceCredential` block instead. Unlike a bare
    comparison, `parameters()`/`reference()` throw on a missing key or reference rather than
    silently resolving to `$null`, so a typo fails just that resource instead of skipping it
    unnoticed. These are ordinary PowerShell commands, so multi-argument calls take
    space-separated arguments — `equals (parameters 'Environment') 'Prod'`, not
    `equals(parameters('Environment'), 'Prod')` — the comma-in-parens form parses as a single
    array argument and silently mis-binds:

    ```yaml
    - name: CON Board Administrators
      preCondition: (parameters('Environment')) -eq 'Prod' -and (variables('ProjectWorkBoardsStatus')) -eq 'enabled'
      type: AzureDevOpsDscNative/AzDoProjectGroup
    ```

- __postCondition__: evaluated after the resource's `Test`/`Set`, before `postExecutionScript`.
  A `$false` result marks the resource `FAIL` regardless of what the engine itself reported —
  it asserts something about the *outcome*, where `preCondition` decides whether the resource
  runs at all. It is parsed by the same predicate allow-list as `preCondition`, plus two
  accessors reserved for `postCondition` only: `result()` (the resource's normalized engine
  result — `InDesiredState` / `RebootRequired` / `Message` / `Raw`) and `stopProcessing()` (see
  below).

    __Example:__

    ```yaml
    - name: Project Services
      type: AzureDevOpsDscNative/AzDoProjectServices
      postCondition: result().InDesiredState -or (not (equals (variables 'Project_Ensure') 'Present'))
    ```

- __preExecutionScript__ / __postExecutionScript__: run arbitrary PowerShell immediately
  before, or after, the resource's `Test`/`Set` evaluation. Useful for preparing state a
  resource depends on, or for clean-up/state-change logic afterwards. Unlike a condition,
  these are not restricted to a predicate — see `AllowExecutionScripts` below, which gates
  their use. Unlike `properties`/`preCondition`/`postCondition`, these are not parsed through
  `ExpandString` or `Assert-SafeConditionExpression` — they run as plain PowerShell, with
  direct read access to the script-scope variable `Set-Variables` already created for each
  Datum variable, so there is no need to go through the `variables()` accessor here. A
  variable whose name matches a runner or PowerShell variable (for example `parameters` or
  `ErrorActionPreference`) is not created as a script variable and is only readable through
  `variables()`. Configuration variables are also exported as environment variables, but an
  environment variable that already existed before the run (such as `PATH`) is never overwritten.

    __Example:__

    ```yaml
    - name: Project
      type: AzureDevOpsDscNative/AzDoProject
      postExecutionScript: if ($Project_Ensure -eq 'Absent') { Stop-TaskProcessing }
    ```

- __AllowExecutionScripts__ (`PipelineRunnerSettings.AllowExecutionScripts`, default `false`):
  a configuration-level gate on `preExecutionScript`/`postExecutionScript`. Because an
  execution script runs unrestricted code in the runner's own process, a configuration must
  opt in explicitly before any resource may carry one; otherwise the run fails at PreParse
  time, naming every offending resource in one pass, before any resource is evaluated.

    ```yaml
    PipelineRunnerSettings:
      AllowExecutionScripts: true
    ```

- __resourceCredential__: a declarative way to inject a resolved credential into a resource's
  own properties (for example a resource's `-Credential` parameter) without the credential
  ever appearing in the configuration file. It resolves through the `Credential` action hook
  and, unlike `preExecutionScript`/`postExecutionScript`, works even when
  `AllowExecutionScripts` is off — it is declarative, not a script.

    __Example:__

    ```yaml
    - name: SQL Login
      type: SqlServerDsc/SqlLogin
      properties:
        InstanceName: MSSQLSERVER
      resourceCredential:
        action: SecretManagement   # a file in Actions/Credential/ (default: Environment)
        name: sql-service-account  # the secret name
        propertyName: Credential   # the properties key the resolved PSCredential is written to (default: Credential)
    ```

- __dependsOn__: This feature establishes a dependency chain, ensuring that resources are executed in a specific order. By defining dependencies, you can create a structured sequence of resource execution, where a resource will only run after its dependencies have successfully completed. This is particularly useful in complex configurations where the order of operations is critical.

    __Example:__

    ```yaml
    - name: Default Git Configuration Permissions
      type: AzureDevOpsDscNative/AzDoGitPermission
      dependsOn:
        - AzureDevOpsDscNative/AzDoProject/Project
        - AzureDevOpsDscNative/AzDoProjectGroup/CON Readers
        - AzureDevOpsDscNative/AzDoProjectGroup/CON Board Administrators
    ```

- __notify__ / __using()__: a Puppet/Chef-style relationship between two resources, combining an
  ordering guarantee with a data link. `notify` is a string or array of strings on the
  *notifying* resource, each naming a target resource by the same `Type/Name` identity
  `dependsOn` uses. The notifying resource is guaranteed to run first, and when it changes in a
  `Set` pass every resource it notifies is forced through its own `Set()`. A notified resource
  may read the notifying resource's `Get()` output with `using('Type/Name')`. Both halves are
  scoped to a single configuration file — see [docs/notify-and-using.md](docs/notify-and-using.md).

    __Example:__

    ```yaml
    resources:
      - name: Project
        type: AzureDevOpsDscNative/AzDoProject
        properties:
          ProjectName: Magenta
        notify:
          - AzureDevOpsDscNative/AzDoGitRepository/Default Repository

      - name: Default Repository
        type: AzureDevOpsDscNative/AzDoGitRepository
        properties:
          # Only readable here because 'Project' names this resource in its own notify list.
          ProjectId: $((using 'AzureDevOpsDscNative/AzDoProject/Project').Id)
    ```

- __parameter tokens__: A resource property whose value is exactly `<params=Name>` is replaced
  by the value of that pipeline parameter, with its type intact — a number stays a number, a
  hashtable stays a hashtable. Values come from the configuration's own `parameters` section
  (each parameter's `defaultValue`). Referencing a parameter that is not declared fails that
  resource and records it in the run report; it does not silently resolve to `$null`.

    __Example:__

    ```yaml
    parameters:
      ServiceName:
        defaultValue: Spooler

    resources:
      - name: Print Spooler
        type: PSDscResources/Service
        properties:
          Name: <params=ServiceName>
    ```

- __executionMethodOverride__: This feature lets a single resource pin its own execution method, overriding whatever `ConfigurationMode` the pipeline run is otherwise using for every other resource. The resource is still `Test`-ed first as normal; the override only changes what happens when that `Test` reports the resource is not in the desired state. Values are 'none', 'test' and 'set'. Setting the value to 'none' (the default) means the resource simply follows the run's overall mode, with no special treatment.

    - `executionMethodOverride: test` pins the resource to test-only, even during an `ApplyOnly` or `Enforce` run. Use this to exempt a specific resource from being changed while the rest of the configuration is enforced.
    - `executionMethodOverride: set` pins the resource to always apply changes, even during an `Audit` run. Use this to force a specific resource to self-heal every run regardless of the configured mode.

    __Syntax:__
    executionMethodOverride: ['none', 'test', 'set']

    __Example:__

    ```yaml
    - name: Default Git Configuration Permissions
      type: AzureDevOpsDscNative/AzDoGitPermission
      executionMethodOverride: test
      # Even if this run's ConfigurationMode is 'Enforce', this resource will only ever be tested, never set.
    ```

    ```yaml
    - name: Default Git Configuration Permissions
      type: AzureDevOpsDscNative/AzDoGitPermission
      executionMethodOverride: set
      # Even if this run's ConfigurationMode is 'Audit', this resource will still be applied if it drifts.
    ```

- __Stub (partial) resources__ (`merge_with`): a resource declared with `merge_with` merges its
  `properties` into another resource in the same compiled file, named by that resource's full
  `Module/ResourceName/Instance` identity. The target declares itself as a stub target with
  `mergable: true`; a missing, duplicated or unmarked target fails the run. The stub's values
  override the target's (later stubs win over earlier ones), list properties are combined
  without duplicates, and nested hashtables are merged.

    __Example:__

    ```yaml
    # ProjectPolicies/ProjectGroups.yml
    - name: CON Readers
      type: AzureDevOpsDscNative/AzDoProjectGroup
      mergable: true
      properties:
        ProjectName: $(variables('ProjectName'))
        GroupName: $(variables('ProjectGroups_Role_CONReaders'))

    # Projects/Present/Magenta.yml
    - name: Magenta Readers Group
      type: AzureDevOpsDscNative/AzDoProjectGroup
      merge_with: AzureDevOpsDscNative/AzDoProjectGroup/CON Readers
      properties:
        Ensure: Present
    ```

- __Composite resources__ (`type: composite/<Name>`): a resource whose type is `composite/<Name>`
  is replaced by the resources declared in `CompositeResources/<Name>.yml` in the configuration
  directory, before dependency ordering. The composite node's `properties` are passed in as the
  composite's parameters, overriding its declared defaults. Parameters and variables a composite
  declares apply only to its own resources; anything it does not declare resolves from the file
  that references it.

    __Example:__

    ```yaml
    # Projects/Present/Magenta.yml - expands into the resources in CompositeResources/ConfigurationRepository.yml
    - name: Configuration Repository
      type: composite/ConfigurationRepository
      properties:
        RepositoryName: $(variables('ProjectRepositoryName'))

    # CompositeResources/ConfigurationRepository.yml
    parameters:
      RepositoryName:
        defaultValue: Configuration

    resources:
      - name: Configuration Git Repository
        type: AzureDevOpsDscNative/AzDoGitRepository
        properties:
          ProjectName: $(variables('ProjectName'))
          RepositoryName: $(parameters('RepositoryName'))
    ```

    See the [Composite and Stub Resources](https://github.com/Akkodis-Solution-Engineering/DSC.PipelineRunner.Akkodis/wiki/Composite-and-Stub-Resources) wiki page.

These features collectively enhance the robustness and adaptability of DSC resources managed by the pipeline runner, allowing for more precise and context-sensitive configuration management.

### Configuration Specific Commands

In the realm of configuration, there are specialized commands designed to modify the pipeline runner execution process. These commands provide greater control over how configurations are applied and managed. The key commands include:

- _Stop-TaskProcessing_: This command halts the processing of tasks. When executed, any resources scheduled to run after this command will be bypassed, effectively skipping their execution. This is useful for scenarios where you need to prevent certain operations from taking place without altering the entire configuration. For Example:

    ```yaml
    - name: Project
      type: AzureDevOpsDscNative/AzDoProject
      postExecutionScript: if ($Project_Ensure -eq 'Absent') { Stop-TaskProcessing }
    ```

    In this scenario, when the project is set for deletion, it will remove the project and subsequently halt any further tasks from executing within the pipeline.

- _stopProcessing()_: the `postCondition`-only counterpart of `Stop-TaskProcessing`. It sets
  the same run-control flag, so the remaining resources in the file are skipped, but it is
  reachable from a `postCondition` expression (which cannot call arbitrary commands) rather
  than only from `preExecutionScript`/`postExecutionScript`:

    ```yaml
    - name: Print Spooler
      type: PSDscResources/Service
      postCondition: result().InDesiredState -or stopProcessing()
    ```

### Deep Dive: Configuration Merging and Executing Process

1. Datum merges the example configuration based on the resolution precedence.
1. Once the YAML file for the project has been generated, Datum will execute any `[x={ $Node.ProjectPresence }=]` script blocks within the `variables` property.
1. The pipeline runner ingests the configuration, loading and interpolating all variables and parameters into memory.
1. Stub resources are merged into their `merge_with` targets, and composite resources are replaced by the resources of the files they link to.
1. Each resource's `notify` property is expanded into an implicit `dependsOn` entry on every
   resource it names, so the notifying resource is guaranteed to run first.
1. The `Resources` are ordered according to the `dependsOn` property (including the implicit
   entries `notify` just added).
1. The runner executes the `Pre-Parse` and `Format` rules.
1. The runner iterates through each of the Resources and performs the following steps:
    1. Checks if `Stop-TaskProcessing`/`stopProcessing()` has been called; if so, the resource will be skipped.
    1. Checks for the `preCondition` property (the `condition` key still works, as a
       deprecated alias) and evaluates the expression. The resource executes when it is
       `$true`; a `$false` result skips the resource.
    1. Resolves the resource's properties in two passes. The first pass substitutes whole-value
       parameter tokens (`<params=Name>`), which keeps the parameter's type intact; the second
       pass interpolates variables and evaluates any calculated properties:

       ```yaml
       ServiceName: <params=ServiceName>
       Ensure: $( if ([string]::IsNullOrEmpty((variables 'Project_Ensure'))) { 'Present' } else { variables 'Project_Ensure' } )
       ```

    1. Resolves the resource's execution `target` (a per-resource override, falling back to
       `PipelineRunnerSettings.Target`, default `Local`) and its `resourceCredential`, if any,
       through the `Target`/`Credential` action hooks.
    1. If present, runs `preExecutionScript` before the engine call (gated by
       `AllowExecutionScripts`).
    1. Runs the engine's `Test` method. If the resource is already in the desired state **and**
       it was not forced to refresh by a `notify`, it is marked `OK` and Set is skipped.
       Otherwise, in `Enforce`/`ApplyOnly` mode (or with `executionMethodOverride: set`) it runs
       the engine's `Set` method; in `Audit` mode (or with `executionMethodOverride: test`),
       drift marks the resource `FAIL` instead. Under `Enforce`, a resource that was set is
       re-tested to verify the change landed. `Invoke-DscResource` drives `DscV2` (the default),
       `dsc.exe` drives `DscV3`.
    1. If `Set` reports `RebootRequired`: a remote target is restarted and the run continues
       once it is back; a local target fails the resource and stops the rest of the file, unless
       `PipelineRunnerSettings.Reboot: Ignore` is set.
    1. Checks for the `postCondition` property and evaluates it; a `$false` result marks the
       resource `FAIL` regardless of the engine's own outcome.
    1. Upon completion (even in case of an error), the runner checks for the `postExecutionScript` property and invokes the code if present.
    1. The runner calls the engine's `Get` method on the resource and stores the result in a references table, making it available to subsequent resources via the `reference` function, and to any resource this one notifies via the `using()` function.

## Getting Started

1. Clone the repository: `git clone 'https://github.com/ZanattaMichael/DSC.PipelineRunner.Akkodis' C:\Your-Path`
1. Using the `Example Configuration` Directory, create a custom datum directory structure following these guidelines:
   1. __Lower-Level Rules__ should be implemented first, such as organizational policies.
   1. __Intermediate-Level Rules__ apply to groups of projects. For example:

      _datum.yml_

      ```yaml
      ResolutionPrecedence:
          # This is a High-Level Policy
          - Projects\$($Node.ProjectPresence)\$($Node.Project)
          # This is an intermediate level policy. Note that $Node.ProjectArea dictates that there potentially are multiple projects that fall under a "Project Area"
          # These can be specified under a higher level policy.
          - ProjectPolicies\$(Node.ProjectArea)\GitPermissions            
          - ProjectPolicies\$(Node.ProjectArea)\GitRepositories
          - ProjectPolicies\$(Node.ProjectArea)\ProjectGroups
          # This is a Low-Level policy.
          - ProjectPolicies\Project
          - OrganizationPolicies\OrganizationGroups
          - OrganizationPolicies\Organization
      ```

      > __Please Note:__ Lower-level configurations take precedence over higher-level configurations. In the event of a conflict, datum will default to the lower-level settings.

      _`($Node.Project).yaml`_

      ```yaml
      # The Project Area can be specified within the end user yaml file.
      ProjectArea: CustomProjectArea

      parameters: {}

      variables: {
          ProjectDescription: 'Custom Magenta Project. Contact Name: John Doe.',
          ProjectRepositoryName: 'CON_Configuration',
          Project_Service_GitRepositories: 'enabled',
          Project_Service_BuildPipelines: 'enabled',
          Project_Service_AzureArtifact: 'enabled'
      }
      ```

   1. __Higher-Level Rules__ describe lower-level areas and project-specific settings.

      > __Note:__ Please keep changes within the project YAML configuration to a minimum. This ensures that the project does not become a 'snowflake' and remains consistent with established standards and practices. By minimizing deviations, we maintain uniformity across projects, facilitating easier maintenance, scalability, and collaboration among team members. This approach also reduces the risk of introducing unique complexities that could complicate future updates or integrations.

   1. Please note that any adjustments should adhere to the established hierarchy and rules.
   1. As a general guideline, __AVOID__ altering `lookup_options` unless you are fully aware of the implications.

1. __Store the Configuration within the Respective Code Environment:__

   - Ensure that all configuration files and settings are securely stored within the appropriate code environment to maintain consistency and security.
   - Use environment-specific directories or repositories to manage configurations, ensuring easy access and version control.

1. __Setup the pipeline runner using a Self-Hosted Agent within the Azure DevOps Pipeline:__

   - Follow the detailed instructions provided in the [Azure DevOps Agents Documentation](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/agents?view=azure-devops) to configure your self-hosted agent.
   - __If Using Managed Identity within Azure Arc:__
     - Verify that the Agent Pool service is executed under an administrator account to ensure proper permissions and functionality.
   - __Grant Permissions for Identity within Azure DevOps (AZDO):__
     - __Using Managed Identity (Virtual Machine):__  
       Refer to the [Managed Identities Overview](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview) for steps on enabling managed identity on virtual machines.
     - __Using Managed Identity for Azure Arc:__  
       Managed identity is already configured. Add the computer account into the Project Collection Administrators group to grant necessary permissions.
     - __If Using Personal Access Token (PAT):__  
       Add the custom identity to Azure DevOps and generate a PAT to authenticate and authorize actions within the pipeline.

1. __Deploy the Local Configuration Manager__

    Installation Script:

    ``` PowerShell
    #
    # Install Module Dependencies
    Install-Module PSDesiredStateConfiguration, Datum, Datum.InvokeCommand, powershell-yaml -Force -Scope AllUsers -SkipPublisherCheck
    Write-Host "Installing Dependencies Modules"

    #
    # Set Enviroment Variables

    # Define the directory paths
    $agentDir = "C:\Agent"
    $baseDir = "C:\AzureDevOpsDSC"
    $logsDir = "$baseDir\Logs"
    $cacheDir = "$baseDir\Cache"

    # Create the directories if they do not exist
    $null = New-Item -Path $logsDir -ItemType Directory -Force
    $null = New-Item -Path $cacheDir -ItemType Directory -Force
    $null = New-Item -Path $agentDire -ItemType Directory -Force

    # Define environment variable values
    $cacheEnvVar = "$cacheDir"
    $warningLogEnvVar = "$logsDir\WarningLog.txt"
    $errorLogEnvVar = "$logsDir\ErrorLog.txt"

    # Set the environment variables
    [System.Environment]::SetEnvironmentVariable("AZDODSC_CACHE_DIRECTORY", $cacheEnvVar, [System.EnvironmentVariableTarget]::Machine)
    [System.Environment]::SetEnvironmentVariable("AZDO_WARNINGLOGGING_FILEPATH", $warningLogEnvVar, [System.EnvironmentVariableTarget]::Machine)
    [System.Environment]::SetEnvironmentVariable("AZDO_ERRORLOGGING_FILEPATH", $errorLogEnvVar, [System.EnvironmentVariableTarget]::Machine)

    # Output to confirm creation
    Write-Host "Directories and environment variables have been created successfully."
    ```

1. __Ensure that the Agent Pools have required dependencies__

    Ensure that the Agent Pool is equipped with all necessary PowerShell module dependencies as specified in the module manifest file [`source\DSC.PipelineRunner.Akkodis.psd1`](.\source\DSC.PipelineRunner.Akkodis.psd1). These dependencies are crucial for the proper functioning of the pipeline runner within your Azure DevOps environment.

    To install these required modules, execute the following command for each module listed in the manifest:

    ```powershell
    Install-Module -Name ModuleName
    ```

    __Process:__

    1. __Review the Module Manifest:__
    - Open the `source\DSC.PipelineRunner.Akkodis.psd1` file to identify all modules listed under the `RequiredModules` section.
    - Take note of each module name and version specified.

    1. __Install Each Module:__
    - For every module identified, run the `Install-Module` command in a PowerShell session with administrative privileges. Replace `ModuleName` with the actual name of the module you wish to install.
    - Example:

        ```powershell
        Install-Module -Name ModuleName
        ```

    1. __Verify Installation:__
    - After installing each module, confirm its presence by running:

        ```powershell
        Get-Module -ListAvailable -Name ModuleName
        ```

    - This command will list the installed modules and their versions, ensuring they match those required by the manifest.

    1. __Update Modules if Necessary:__
    - If any module is outdated, update it using:

        ```powershell
        Update-Module -Name ModuleName
        ```

    1. __Check Compatibility:__
    - Ensure that the installed modules are compatible with your system and other installed software to prevent conflicts or errors during execution.

    By following these steps, you will ensure that your Agent Pool is fully prepared with all necessary PowerShell dependencies, facilitating seamless operation of your Azure DevOps pipelines.

    > Please Note: Maintaining the correct versioning is crucial to prevent pipeline runner compilation errors. Before proceeding with any updates, always verify that the `PipelineRunnerSettings` versions within Datum.yml are compatible. The pipeline runner will reject any configuration that does not meet the specified versioning criteria.

1. __Setup the Azure DevOps Pipeline:__

    __Template 1 - Classic__:

    The classic template utilizes a pipeline approach to derive the ConfigurationMode:

    ``` YAML
      # Starter pipeline
      # Start with a minimal pipeline that you can customize to build and deploy your code.
      # Add steps that build, run tests, deploy, and more:
      # https://aka.ms/yaml

      schedules: 
        - cron: '0 05-20 * * 1-5'
          displayName: Hourly Pipeline Runner Check (Test)
          always: true
          branches:
            include:
            - master
        - cron: '0 21 * * 1-5'
          displayName: Pipeline Runner Enforcement (Set)
          always: true
          branches:
            include:
            - master

      variables:
      - name: PipelineRunnerMethod
        ${{ if eq(variables['Build.CronSchedule.DisplayName'], 'Pipeline Runner Enforcement (Set)') }}:
          value: 'Enforce'
        ${{ else }}:
          value: 'Audit'
        readonly: true

      #container:
      pool:
        name: azdo_dsc_pipeline_runner

      steps:

        - pwsh: |
            Import-Module DSC.PipelineRunner.Akkodis, AzureDevOpsDscNative;
            Write-Host "Source: $(build.sourcesDirectory)"
            Write-Host "Method: $(PipelineRunnerMethod)"

            $params = @{
              AzureDevopsOrganizationName = 'AzDoManagmentOrg'
              exportConfigDir = 'C:\AzureDevOpsDSC\Configuration Export\'
              ConfigurationSourcePath = "$(build.sourcesDirectory)"
              JITToken = 'na'
              ConfigurationMode = "$(PipelineRunnerMethod)"
              ReportPath = 'C:\AzureDevOpsDSC\Reporting\'
            }
            Invoke-DscPipelineRunner @params
          displayName: Trigger the Pipeline Runner
          workingDirectory: "$(build.sourcesDirectory)"
          errorActionPreference: continue
    ```

    __Template 2 - Updated__:

    The updated template omits `-ConfigurationMode`, so the runner derives it from `PipelineConfigurationMode` in Datum.yml (for example `Scheduled` with `ChangeWindows`):

    ``` YAML
      # Starter pipeline
      # Start with a minimal pipeline that you can customize to build and deploy your code.
      # Add steps that build, run tests, deploy, and more:
      # https://aka.ms/yaml

      schedules: 
        - cron: '0 05-20 * * 1-5'
          displayName: Hourly Pipeline Runner Check
          always: true
          branches:
            include:
            - master

      #container:
      pool:
        name: azdo_dsc_pipeline_runner

      steps:

        - pwsh: |
            Import-Module DSC.PipelineRunner.Akkodis, AzureDevOpsDscNative;
            Write-Host "Source: $(build.sourcesDirectory)"

            $params = @{
              AzureDevopsOrganizationName = 'AzDoManagmentOrg'
              exportConfigDir = 'C:\AzureDevOpsDSC\Configuration Export\'
              ConfigurationSourcePath = "$(build.sourcesDirectory)"
              JITToken = 'na'
              ReportPath = 'C:\AzureDevOpsDSC\Reporting\'
            }
            Invoke-DscPipelineRunner @params
          displayName: Trigger the Pipeline Runner
          workingDirectory: "$(build.sourcesDirectory)"
          errorActionPreference: continue
    ```

    1. __Test to Ensure the Pipeline Runner is Running Correctly:__

    - __Set the Pipeline Runner Mode to Audit:__
        - Switch the pipeline runner to Audit mode to validate configuration changes without applying them immediately.
    - __Look for Runtime Errors:__
        - Monitor logs and outputs for any runtime errors or warnings that could indicate misconfigurations or issues needing resolution.
    - __Verify Expected Outcomes:__
        - Conduct thorough testing to confirm that the pipeline runner behaves as expected, making adjustments as necessary to address any discrepancies or failures.

## Using Invoke-DscRunner Directly (Non-Azure DevOps Consumers)

The pipeline runner's execution engine (Datum compilation, configuration validation, resource invocation) does not depend on Azure DevOps in any way — it invokes whatever DSC resource module the compiled configuration's `type:` fields reference. `Invoke-DscPipelineRunner` is a thin, Azure-DevOps-flavored wrapper around this engine: it authenticates to Azure DevOps and then delegates everything else to `Invoke-DscRunner`.

If your configuration targets a different (or no) authenticated backend, call `Invoke-DscRunner` directly. It requires no `AzureDevOpsDscNative` or `AzureDevOpsDsc.Common` install, needs no `AZDODSC_CACHE_DIRECTORY` environment variable (that's only read by the `AzureDevOpsDscNative` resources themselves), and performs no authentication of its own — authenticate to whatever your configuration's resources require using that module's own mechanism before calling it.

```powershell
Import-Module DSC.PipelineRunner.Akkodis

# Authenticate to whatever DSC resource module your configuration's `type:` fields reference,
# using that module's own mechanism, before calling Invoke-DscRunner.

$params = @{
    exportConfigDir         = 'C:\MyConfig\Export\'
    ConfigurationSourcePath = 'C:\MyConfigRepo'
    ConfigurationMode       = 'Audit'
}
Invoke-DscRunner @params
```

`Invoke-DscPipelineRunner` remains the recommended entry point for Azure DevOps DSC configurations — it now checks for `AzureDevOpsDsc.Common` when called, rather than requiring it at `Import-Module` time, so `Import-Module DSC.PipelineRunner.Akkodis` no longer fails in environments that only need the generic engine.
