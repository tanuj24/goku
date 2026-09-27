# Goku installer for Windows (formerly Mimir) - https://tanuj24.github.io/goku/
#
#   irm https://tanuj24.github.io/goku/install.ps1 | iex
#
# Installs the goku CLI (goku.exe, verified against the release's SHA-256 checksums) and mimir.exe,
# the command's former name (deprecated), next to it, in %LOCALAPPDATA%\Programs\Goku\bin, and adds
# that directory to your user PATH. Re-running it upgrades in place. Works in Windows PowerShell 5.1
# and PowerShell 7. Goku itself runs in Docker Desktop (Linux containers).
#
#   $env:GOKU_VERSION        install this release (e.g. 0.3.0) instead of the latest
#   $env:GOKU_DOWNLOAD_BASE  where the release files are (goku_windows_<arch>.exe, checksums.txt);
#                            default: the GitHub release. A file:// URL works too.
#   $env:GOKU_INSTALL_DIR    install into this directory

# Everything runs inside a function: piped into Invoke-Expression, an `exit` would close the
# user's PowerShell window, so failures are thrown instead.
function Install-Goku {
    $ErrorActionPreference = 'Stop'

    $releases = 'https://github.com/tanuj24/goku/releases'

    # --- which binary ---------------------------------------------------------------------------
    $arch = $null
    try {
        $os = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        switch ($os) { 'X64' { $arch = 'amd64' } 'Arm64' { $arch = 'arm64' } }
    } catch { }
    if (-not $arch) {
        $native = $env:PROCESSOR_ARCHITEW6432
        if (-not $native) { $native = $env:PROCESSOR_ARCHITECTURE }
        switch ($native) { 'AMD64' { $arch = 'amd64' } 'ARM64' { $arch = 'arm64' } }
    }
    if (-not $arch) {
        throw "install: no goku binary for this processor ($env:PROCESSOR_ARCHITECTURE); goku runs on 64-bit Windows (x64 or ARM64)."
    }
    $asset = "goku_windows_$arch.exe"

    if ($env:GOKU_DOWNLOAD_BASE) {
        $base = $env:GOKU_DOWNLOAD_BASE.TrimEnd('/')
    } elseif ($env:GOKU_VERSION) {
        $base = "$releases/download/v$($env:GOKU_VERSION.TrimStart('v'))"
    } else {
        $base = "$releases/latest/download"
    }

    if ($env:GOKU_INSTALL_DIR) {
        # A relative directory is taken from PowerShell's current location.
        $dir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($env:GOKU_INSTALL_DIR)
    } else {
        $dir = Join-Path $env:LOCALAPPDATA 'Programs\Goku\bin'
    }

    # --- download and verify into a temporary directory: nothing is installed before this passes ---
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('goku-install-' + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $exe = Join-Path $tmp 'goku.exe'
        $sums = Join-Path $tmp 'checksums.txt'
        Write-Host "downloading goku CLI ($asset)..."
        Get-GokuFile "$base/$asset" $exe
        Get-GokuFile "$base/checksums.txt" $sums

        $want = $null
        foreach ($line in Get-Content -LiteralPath $sums) {
            $fields = $line.Trim() -split '\s+'
            if ($fields.Count -ge 2 -and $fields[1].TrimStart('*') -eq $asset) { $want = $fields[0].ToLowerInvariant(); break }
        }
        if (-not $want) { throw "install: checksums.txt has no entry for $asset; nothing was installed." }
        $got = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($got -ne $want) {
            throw "install: checksum mismatch for $asset (expected $want, got $got); nothing was installed."
        }
        # The download must run here: its version line proves it is a working goku for this machine.
        $version = $null
        try {
            $output = @(& $exe version)
            if ($LASTEXITCODE -eq 0 -and $output.Count -gt 0) { $version = [string]$output[0] }
        } catch { }
        if (-not ("$version" -like 'goku CLI *')) {
            throw "install: the downloaded goku.exe does not run on this machine; nothing was installed."
        }

        # --- install: stage both files next to the old ones, then swap them in ---------------------
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $goku = Join-Path $dir 'goku.exe'
        $mimir = Join-Path $dir 'mimir.exe'
        $upgrading = Test-Path -LiteralPath $goku
        Remove-GokuLeftovers $dir
        $moved = @()
        try {
            Copy-Item -LiteralPath $exe -Destination "$goku.new" -Force
            Copy-Item -LiteralPath $exe -Destination "$mimir.new" -Force
            foreach ($target in @($goku, $mimir)) {
                if (Test-Path -LiteralPath $target) {
                    # A running goku.exe cannot be overwritten, but it can be renamed.
                    Move-Item -LiteralPath $target -Destination "$target.old" -Force
                    $moved += $target
                }
                Move-Item -LiteralPath "$target.new" -Destination $target -Force
            }
        } catch {
            foreach ($target in $moved) {
                if (Test-Path -LiteralPath "$target.old") { Move-Item -LiteralPath "$target.old" -Destination $target -Force }
            }
            Remove-Item -LiteralPath "$goku.new", "$mimir.new" -Force -ErrorAction SilentlyContinue
            throw "install: could not install into ${dir}: $($_.Exception.Message)"
        }
        Remove-GokuLeftovers $dir
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    # --- PATH: the user PATH in the registry (kept unexpanded), and this session -----------------
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $userPath = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $entries = @($userPath -split ';' | Where-Object { $_ -ne '' })
        $present = $entries | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ieq $dir.TrimEnd('\') }
        if (-not $present) {
            $key.SetValue('Path', (($entries + $dir) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
            # Tell Explorer (and new terminals) that the environment changed.
            [Environment]::SetEnvironmentVariable('GOKU_INSTALL_REFRESH', '1', 'User')
            [Environment]::SetEnvironmentVariable('GOKU_INSTALL_REFRESH', $null, 'User')
            Write-Host "added $dir to your user PATH"
        }
    } finally {
        $key.Close()
    }
    $sessionPath = @($env:Path -split ';' | Where-Object { $_ -ne '' })
    if (-not ($sessionPath | Where-Object { $_.TrimEnd('\') -ieq $dir.TrimEnd('\') })) {
        $env:Path = "$dir;$env:Path"
    }

    # --- Docker Desktop ----------------------------------------------------------------------------
    $dockerNote = $null
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        $dockerNote = "Goku runs in Docker Desktop, which is not installed: https://docs.docker.com/desktop/setup/install/windows-install/ (or: winget install Docker.DockerDesktop)"
    } else {
        $osType = $null
        # Windows PowerShell 5.1 turns a redirected stderr line into an error; docker may print warnings.
        $eap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $osType = @(& docker info --format '{{.OSType}}' 2>$null)[0] } catch { } finally { $ErrorActionPreference = $eap }
        if (-not $osType) {
            $dockerNote = "Docker Desktop is installed but not running: start it before 'goku start'."
        } elseif ("$osType".Trim() -eq 'windows') {
            $dockerNote = "Docker Desktop is set to Windows containers: right-click its icon and choose 'Switch to Linux containers...'."
        }
    }

    # --- done ----------------------------------------------------------------------------------------
    $installed = @(& $goku version)[0]
    Write-Host ''
    if ($upgrading) { Write-Host "upgraded goku in $dir" }
    Write-Host "Installed goku (and mimir, deprecated) in $dir"
    Write-Host "  $goku   $installed"
    Write-Host "  $mimir  the former name; it prints a deprecation note (`$env:GOKU_NO_DEPRECATION_NOTICE = '1' hides it)"
    if ($dockerNote) {
        Write-Host ''
        Write-Warning $dockerNote
    }
    Write-Host ''
    Write-Host 'Get started (new terminals find goku on PATH; this one already does):'
    Write-Host '  goku start                          # run the local cloud'
    Write-Host '  goku env | Invoke-Expression        # point the AWS CLI / SDKs at it'
    Write-Host '  goku help                           # snapshots, chaos, iam, lambda debug, logs...'
    Write-Host ''
    $dataDir = Join-Path $env:LOCALAPPDATA 'Goku\data'
    Write-Host "Goku keeps everything it saves in $dataDir ('goku data' shows it; GOKU_DATA_DIR moves it)."
    Write-Host "Update later with 'goku update' (Goku) and 'goku update --cli' (this command)."
}

# Get-GokuFile downloads a URL (https:// or file://) to a file.
function Get-GokuFile([string]$Url, [string]$OutFile) {
    try {
        $uri = [System.Uri]$Url
        if ($uri.IsFile) {
            Copy-Item -LiteralPath $uri.LocalPath -Destination $OutFile -Force
            return
        }
        # Windows PowerShell 5.1 does not offer TLS 1.2 by default everywhere.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $progress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'  # the progress bar makes 5.1 downloads crawl
        try {
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
        } finally {
            $ProgressPreference = $progress
        }
    } catch {
        throw "install: download failed ($Url): $($_.Exception.Message)"
    }
}

# Remove-GokuLeftovers deletes the .old / .new files of an earlier run (an .old one stays while
# that goku.exe is still running; the next install removes it).
function Remove-GokuLeftovers([string]$Dir) {
    foreach ($name in 'goku.exe.old', 'mimir.exe.old', 'goku.exe.new', 'mimir.exe.new') {
        $path = Join-Path $Dir $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
}

try {
    Install-Goku
} finally {
    # Piped into Invoke-Expression the functions would stay in the caller's session.
    Remove-Item -Path Function:\Install-Goku, Function:\Get-GokuFile, Function:\Remove-GokuLeftovers -ErrorAction SilentlyContinue
}
