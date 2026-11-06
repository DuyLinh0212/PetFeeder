$ErrorActionPreference = 'Stop'
$backendDir = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\petfeeder_backend')
)
$repoDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

try {
    if (-not (Test-Path -LiteralPath (Join-Path $backendDir 'package.json'))) {
        throw "Could not find the backend project at: $backendDir"
    }

    foreach ($commandName in @('node', 'npm.cmd')) {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            throw "$commandName is not installed or is not available in PATH."
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $backendDir 'node_modules\express'))) {
        throw 'Backend dependencies are missing. Open petfeeder_backend and run: npm ci'
    }

    $originalLocation = Get-Location
    $hadHost = Test-Path Env:HOST
    $originalHost = $env:HOST
    $hadDatabaseUrl = Test-Path Env:DATABASE_URL
    $originalDatabaseUrl = $env:DATABASE_URL
    try {
        Set-Location -LiteralPath $backendDir
        $env:HOST = '0.0.0.0'
        if (-not $env:DATABASE_URL) {
            $keyPath = Join-Path $repoDir 'PetFeeder\Key.txt'
            if (-not (Test-Path -LiteralPath $keyPath)) {
                throw "Set DATABASE_URL or place the Neon connection URL in $keyPath"
            }

            $connectionString = (Get-Content -LiteralPath $keyPath -Raw).Trim()
            $databaseUri = [System.UriBuilder]::new($connectionString)
            $databaseUri.Path = '/petfeeder'
            $env:DATABASE_URL = $databaseUri.Uri.AbsoluteUri
        }
        Write-Host 'Starting PetFeeder backend for access from your Wi-Fi network. Press Ctrl+C to stop.'
        & npm.cmd start
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Backend exited with code $LASTEXITCODE." -ForegroundColor Red
        }
    }
    finally {
        Set-Location -LiteralPath $originalLocation.Path
        if ($hadHost) {
            $env:HOST = $originalHost
        }
        else {
            Remove-Item Env:HOST -ErrorAction SilentlyContinue
        }
        if ($hadDatabaseUrl) {
            $env:DATABASE_URL = $originalDatabaseUrl
        }
        else {
            Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
        }
    }
}
catch {
    Write-Host "Could not start the PetFeeder backend: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host 'Press Enter to close'
    return
}
