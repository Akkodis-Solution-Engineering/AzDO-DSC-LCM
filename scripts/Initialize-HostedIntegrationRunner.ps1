<#
.SYNOPSIS
Provisions a GitHub-hosted runner (windows-latest or ubuntu-latest) so every Integration suite
runs instead of skipping.

.DESCRIPTION
Several Integration suites probe for a live dependency and skip themselves with a warning when it
is missing (Get-LiveVaultSkipReason, Get-SshRemotingSkipReason, Get-WinRMSkipReason and the
in-test readiness checks). On a developer machine that is the right behaviour; in CI it means
the coverage those suites exist to provide silently does not happen. This script installs and
configures each dependency on the hosted runner, so the workflow can then run tests.ps1 with
PIPELINERUNNER_REQUIRE_INTEGRATION_DEPENDENCIES=true and fail on any skip.

  * Credential/SecretManagement - installs Microsoft.PowerShell.SecretManagement and
    Microsoft.PowerShell.SecretStore and opts in to PIPELINERUNNER_ALLOW_SECRETSTORE_RESET. The
    reset erases the account's existing SecretStore, which is safe only because a hosted runner
    is ephemeral: this script refuses to run anywhere else.
  * Target/WinRM (Windows) - runs scripts/Enable-SelfHostedWinRM.ps1, which registers the
    PowerShell.7 endpoint the remote DSC v2 evaluation needs.
  * Engine/DscV3 over SSH - installs dsc where the REMOTE side of an SSH session finds it (the
    machine PATH on Windows, /usr/local/bin on Linux); the job's $GITHUB_PATH does not reach it.
  * Target/SSH - installs the OpenSSH server, registers a 'powershell' subsystem, authorises a
    fresh key for the runner account and trusts localhost's host key, then proves the loopback
    works before any test runs.

Unlike Enable-SelfHostedWinRM.ps1, every failure here is fatal: a dependency that cannot be
provisioned should turn the job red at this step, not show up later as a skipped suite.

Values later steps need are exported through $GITHUB_ENV.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if (-not ($IsWindows -or $IsLinux)) {
    throw 'Initialize-HostedIntegrationRunner.ps1 provisions a GitHub-hosted Windows or Linux runner only.'
}
if ($env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    # The SecretStore reset and the machine-wide sshd/PATH changes are only acceptable on a
    # throwaway machine.
    throw "Refusing to run: RUNNER_ENVIRONMENT is [$env:RUNNER_ENVIRONMENT], not 'github-hosted'."
}

function Set-JobEnvironment {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Value)
    Set-Item -Path "env:$Name" -Value $Value
    if ($env:GITHUB_ENV) { Add-Content -LiteralPath $env:GITHUB_ENV -Value "$Name=$Value" }
}

function Invoke-Native {
    # Runs a native command and throws on a non-zero exit, which $ErrorActionPreference does not.
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$ArgumentList = @())
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) { throw "[$FilePath $($ArgumentList -join ' ')] exited with $LASTEXITCODE." }
}

# ---------------------------------------------------------------------------------------------
# Credential/SecretManagement
# ---------------------------------------------------------------------------------------------
Write-Host '[Initialize] SecretManagement + SecretStore'
foreach ($module in 'Microsoft.PowerShell.SecretManagement', 'Microsoft.PowerShell.SecretStore') {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Install-Module -Name $module -Force -Scope CurrentUser -AllowClobber
    }
}
Set-JobEnvironment -Name 'PIPELINERUNNER_ALLOW_SECRETSTORE_RESET' -Value 'true'

# ---------------------------------------------------------------------------------------------
# Target/WinRM (listener + PowerShell.7 endpoint)
# ---------------------------------------------------------------------------------------------
if ($IsWindows) {
    Write-Host '[Initialize] WinRM'
    & (Join-Path $PSScriptRoot 'Enable-SelfHostedWinRM.ps1')
}

# ---------------------------------------------------------------------------------------------
# DSC v3, reachable from the remote side of an SSH session. Installed before sshd is
# (re)started so the sessions it spawns see the updated PATH.
# ---------------------------------------------------------------------------------------------
Write-Host '[Initialize] DSC v3'
if ($IsWindows) {
    $dsc = & (Join-Path $PSScriptRoot 'Install-DscV3.ps1') -InstallDirectory (Join-Path $env:ProgramFiles 'dsc')
    $dscDirectory = Split-Path -Parent $dsc
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (($machinePath -split ';') -notcontains $dscDirectory) {
        [Environment]::SetEnvironmentVariable('Path', "$machinePath;$dscDirectory", 'Machine')
    }
}
else {
    $dsc = & (Join-Path $PSScriptRoot 'Install-DscV3.ps1')
    # dsc finds its resource manifests next to the executable, so copy the whole directory.
    Invoke-Native sudo @('cp', '-r', "$(Split-Path -Parent $dsc)/.", '/usr/local/bin/')
}

# ---------------------------------------------------------------------------------------------
# Target/SSH: loopback sshd with a PowerShell subsystem
# ---------------------------------------------------------------------------------------------
Write-Host '[Initialize] OpenSSH server'
$sshDirectory = Join-Path $HOME '.ssh'
New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
$keyPath = Join-Path $sshDirectory 'id_ed25519'
if (-not (Test-Path -LiteralPath $keyPath)) {
    Invoke-Native ssh-keygen @('-q', '-t', 'ed25519', '-N', '', '-f', $keyPath)
}
$publicKey = (Get-Content -LiteralPath "$keyPath.pub" -Raw).Trim()

if ($IsWindows) {
    if (-not (Get-Service -Name sshd -ErrorAction SilentlyContinue)) {
        Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
    }
    # The first start generates the host keys and the default sshd_config.
    Set-Service -Name sshd -StartupType Automatic
    Start-Service -Name sshd

    $sshdConfigPath = Join-Path $env:ProgramData 'ssh\sshd_config'
    $sshdConfig = @(Get-Content -LiteralPath $sshdConfigPath)
    if (-not ($sshdConfig -match '^\s*Subsystem\s+powershell\s')) {
        # sshd_config cannot take a path with spaces here, so use the 8.3 short path to pwsh.
        # The line must also come BEFORE the first 'Match' block: Windows' default config ends
        # with 'Match Group administrators', and Subsystem is not allowed inside a Match block.
        $shortPwsh = (New-Object -ComObject Scripting.FileSystemObject).GetFile((Get-Command pwsh).Source).ShortPath
        $subsystemLine = "Subsystem powershell $shortPwsh -sshs -NoLogo"

        $firstMatch = [array]::FindIndex([string[]]$sshdConfig, [Predicate[string]] { param($line) $line -match '^\s*Match\s' })
        $updated = if ($firstMatch -gt 0) {
            $sshdConfig[0..($firstMatch - 1)] + $subsystemLine + $sshdConfig[$firstMatch..($sshdConfig.Count - 1)]
        }
        elseif ($firstMatch -eq 0) {
            @($subsystemLine) + $sshdConfig
        }
        else {
            $sshdConfig + $subsystemLine
        }
        Set-Content -LiteralPath $sshdConfigPath -Value $updated -Encoding ascii
    }
    Restart-Service -Name sshd

    # The hosted runner account is a local administrator, and for administrators Windows OpenSSH
    # reads ONLY administrators_authorized_keys - which it ignores unless the ACL is restricted
    # to Administrators and SYSTEM.
    $authorizedKeysPath = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
    if (-not ((Test-Path -LiteralPath $authorizedKeysPath) -and (@(Get-Content -LiteralPath $authorizedKeysPath) -contains $publicKey))) {
        Add-Content -LiteralPath $authorizedKeysPath -Value $publicKey -Encoding ascii
    }
    Invoke-Native icacls.exe @($authorizedKeysPath, '/inheritance:r', '/grant', '*S-1-5-32-544:F', '/grant', '*S-1-5-18:F')
}
else {
    if (-not (Get-Command -Name sshd -CommandType Application -ErrorAction SilentlyContinue) -and -not (Test-Path /usr/sbin/sshd)) {
        Invoke-Native sudo @('apt-get', 'update')
        Invoke-Native sudo @('apt-get', 'install', '-y', 'openssh-server')
    }

    $pwshPath = (Get-Command pwsh).Source
    & sudo grep -qE '^\s*Subsystem\s+powershell\s' /etc/ssh/sshd_config
    if ($LASTEXITCODE -ne 0) {
        # Appended, so it must not land inside a Match block; Ubuntu's default has none active.
        "Subsystem powershell $pwshPath -sshs -NoLogo" | & sudo tee -a /etc/ssh/sshd_config | Out-Null
    }
    Invoke-Native sudo @('systemctl', 'enable', 'ssh')
    Invoke-Native sudo @('systemctl', 'restart', 'ssh')

    $authorizedKeysPath = Join-Path $sshDirectory 'authorized_keys'
    if (-not ((Test-Path -LiteralPath $authorizedKeysPath) -and (@(Get-Content -LiteralPath $authorizedKeysPath) -contains $publicKey))) {
        Add-Content -LiteralPath $authorizedKeysPath -Value $publicKey
    }
    Invoke-Native chmod @('700', $sshDirectory)
    Invoke-Native chmod @('600', $authorizedKeysPath)
}

# Host-key checking stays on (see Get-SshRemotingSkipReason): trust localhost explicitly.
$hostKeys = & ssh-keyscan -H localhost 2>$null
if (-not $hostKeys) { throw 'ssh-keyscan returned no host keys for localhost.' }
Add-Content -LiteralPath (Join-Path $sshDirectory 'known_hosts') -Value $hostKeys -Encoding ascii

Set-JobEnvironment -Name 'PIPELINERUNNER_SSH_TARGET' -Value 'localhost'
Set-JobEnvironment -Name 'PIPELINERUNNER_SSH_KEY' -Value $keyPath

# Prove the loopback here: a broken one would otherwise surface later as a skipped suite.
Invoke-Native ssh @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', 'localhost', 'exit 0')
$probe = New-PSSession -HostName localhost -SSHTransport
try {
    $remoteDsc = Invoke-Command -Session $probe -ScriptBlock { (Get-Command dsc -CommandType Application -ErrorAction SilentlyContinue).Source }
    if (-not $remoteDsc) { throw 'The SSH loopback session cannot find dsc on its PATH.' }
    Write-Host "[Initialize] SSH loopback OK; remote dsc: $remoteDsc"
}
finally {
    Remove-PSSession -Session $probe
}
