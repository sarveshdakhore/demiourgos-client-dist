<#
.SYNOPSIS
Installs the Demiourgos CLI client on Windows.

.DESCRIPTION
Downloads the latest release from GitHub, extracts it, and updates the PATH.
#>

$ErrorActionPreference = "Stop"

$Repo = $env:DEMIOURGOS_RELEASE_REPO
if ([string]::IsNullOrWhiteSpace($Repo)) {
    $Repo = "sarveshdakhore/demiourgos-client-dist"
}

$Version = $env:DEMIOURGOS_VERSION
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = "latest"
}

$InstallDir = $env:DEMIOURGOS_INSTALL_DIR
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = "$env:USERPROFILE\AppData\Local\demiourgos\bin"
}

function Write-Log {
    param([string]$Message)
    Write-Host "[demiourgos-install] $Message"
}

function Get-LatestVersion {
    $ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"
    $Release = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing
    return $Release.tag_name.TrimStart('v')
}

if ($Version -eq "latest") {
    $Version = Get-LatestVersion
} else {
    $Version = $Version.TrimStart('v')
}

$Platform = "windows-amd64"
$Asset = "demiourgos-$Version-$Platform.tar.gz"
$Url = "https://github.com/$Repo/releases/download/v$Version/$Asset"
$ShaUrl = "$Url.sha256"

$TmpDir = Join-Path $env:TEMP "demiourgos-install-$([guid]::NewGuid())"
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null

try {
    Write-Log "Installing demiourgos v$Version for $Platform"
    
    $ArchiveFile = Join-Path $TmpDir $Asset
    $ChecksumFile = Join-Path $TmpDir "$Asset.sha256"

    Invoke-WebRequest -Uri $Url -OutFile $ArchiveFile -UseBasicParsing
    Invoke-WebRequest -Uri $ShaUrl -OutFile $ChecksumFile -UseBasicParsing

    $ExpectedSha = (Get-Content $ChecksumFile).Split(' ')[0]
    $FileHash = (Get-FileHash $ArchiveFile -Algorithm SHA256).Hash.ToLower()

    if ($ExpectedSha -ne $FileHash) {
        throw "SHA256 mismatch for $Asset. Expected: $ExpectedSha, Actual: $FileHash"
    }

    # Use tar command which is available in Windows 10/11
    tar -xzf $ArchiveFile -C $TmpDir

    $ExePath = Join-Path $TmpDir "demiourgos.exe"
    if (-not (Test-Path $ExePath)) {
        # Check inside a folder if tar extracted it there
        $ExePath = Join-Path $TmpDir "demiourgos\demiourgos.exe"
        if (-not (Test-Path $ExePath)) {
            throw "Archive did not contain demiourgos.exe"
        }
    }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $TargetExe = Join-Path $InstallDir "demiourgos.exe"
    Copy-Item -Path $ExePath -Destination $TargetExe -Force

    # Write install channel marker
    $ConfigDir = Join-Path $env:APPDATA "demiourgos"
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    $MarkerFile = Join-Path $ConfigDir "install_channel.json"
    '{"channel":"powershell"}' | Out-File -FilePath $MarkerFile -Encoding utf8

    # Update PATH if needed
    $UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not ($UserPath -split ';' | Where-Object { $_ -eq $InstallDir })) {
        [Environment]::SetEnvironmentVariable("PATH", "$UserPath;$InstallDir", "User")
        Write-Log "Added $InstallDir to user PATH. Restart your terminal for changes to take effect."
    }

    Write-Log "Successfully installed to $TargetExe"
    Write-Log "Run: demiourgos --version"

} finally {
    Remove-Item -Path $TmpDir -Recurse -Force -ErrorAction Ignore
}
