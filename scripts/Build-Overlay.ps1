[CmdletBinding()]
param(
    [string]$CapricaPath,
    [string]$SkyUiSourceRoot,
    [string]$SkseSourceRoot,
    [string]$GamePath,
    [string]$ChampollionPath,
    [string]$ArtifactsRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$lockPath = Join-Path $repoRoot 'dependencies.lock.json'
$sourcePath = Join-Path $repoRoot 'ProteusMCMScript.psc'
$normalizerPath = Join-Path $PSScriptRoot 'Normalize-PexHeader.ps1'
$instanceRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repoRoot '..\..\mo2-instances\skyrim-se')
)

if ([string]::IsNullOrWhiteSpace($CapricaPath)) {
    $CapricaPath = [System.IO.Path]::GetFullPath(
        (Join-Path $repoRoot '..\..\skyrim-tools-builds\Caprica-0.3.0\Caprica\Release\Caprica.exe')
    )
}
if ([string]::IsNullOrWhiteSpace($SkyUiSourceRoot)) {
    $SkyUiSourceRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $repoRoot '..\SkyUI-Community-6.11\source\scripts')
    )
}
if ([string]::IsNullOrWhiteSpace($SkseSourceRoot)) {
    $SkseSourceRoot = Join-Path $instanceRoot 'mods\SKSE64 Scripts\Scripts\Source'
}
if ([string]::IsNullOrWhiteSpace($GamePath)) {
    $mo2Ini = Join-Path $instanceRoot 'ModOrganizer.ini'
    if (Test-Path -LiteralPath $mo2Ini) {
        $gamePathLine = Get-Content -LiteralPath $mo2Ini |
            Where-Object { $_ -match '^gamePath=@ByteArray\((.*)\)$' } |
            Select-Object -First 1
        if ($gamePathLine -match '^gamePath=@ByteArray\((.*)\)$') {
            $GamePath = [System.Text.RegularExpressions.Regex]::Unescape($Matches[1])
        }
    }
    if ([string]::IsNullOrWhiteSpace($GamePath)) {
        $GamePath = 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition'
    }
}
if ([string]::IsNullOrWhiteSpace($ChampollionPath)) {
    $ChampollionPath = [System.IO.Path]::GetFullPath(
        (Join-Path $repoRoot '..\..\skyrim-tools-builds\Champollion-1.3.2\Champollion\Release\Champollion.exe')
    )
}
if ([string]::IsNullOrWhiteSpace($ArtifactsRoot)) {
    $ArtifactsRoot = Join-Path $repoRoot 'artifacts'
}

function Resolve-RequiredFile {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label was not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-RequiredDirectory {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label was not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Assert-Sha256 {
    param([string]$Path, [string]$Expected, [string]$Label)
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected) {
        throw "$Label hash mismatch. Expected $Expected; found $actual at $Path"
    }
}

function Assert-StaticHotkeys {
    param([string]$Path)

    $source = Get-Content -LiteralPath $Path -Raw
    if ($source.Contains('SetKeyMapOptionValueST')) {
        throw 'State-option SetKeyMapOptionValueST remains in ProteusMCMScript.psc.'
    }

    $activeLines = $source -split "`r?`n" |
        Where-Object { -not $_.TrimStart().StartsWith(';') }
    $activeSource = $activeLines -join "`n"
    $functionMatch = [regex]::Match(
        $activeSource,
        '(?ims)^\s*function\s+OnOptionKeyMapChange\b.*?^\s*endFunction\s*$'
    )
    if (-not $functionMatch.Success) {
        throw 'OnOptionKeyMapChange was not found.'
    }

    $body = $functionMatch.Value
    $expected = @(
        'castK1', 'castK3', 'castK5', 'castK6', 'castK7', 'castK8',
        'castK9', 'castK10', 'castK11', 'castK12', 'castK13', 'castK14'
    )
    $branchMatches = [regex]::Matches(
        $body,
        '(?im)^\s*(?:if|elseif)\s+option\s*==\s*(castK\d+)\s*$'
    )
    $actual = @($branchMatches | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
    $wanted = @($expected | Sort-Object)
    if (($actual -join ',') -ne ($wanted -join ',')) {
        throw "Unexpected active hotkey branches. Expected $($wanted -join ','); found $($actual -join ',')"
    }

    $calls = [regex]::Matches(
        $body,
        '\bself\.SetKeyMapOptionValue\(option,\s*keyCode,\s*false\)'
    )
    if ($calls.Count -ne 12) {
        throw "Expected 12 indexed keymap updates; found $($calls.Count)."
    }
}

function Assert-CompiledHotkeys {
    param([string]$PexPath, [string]$DecompilerPath, [string]$OutputDirectory)

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    & $DecompilerPath -p $OutputDirectory $PexPath | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Champollion failed with exit code $LASTEXITCODE."
    }

    $decompiledPath = Join-Path $OutputDirectory 'ProteusMCMScript.psc'
    $decompiled = Get-Content -LiteralPath $decompiledPath -Raw
    if ($decompiled.Contains('SetKeyMapOptionValueST')) {
        throw 'Compiled PEX still references SetKeyMapOptionValueST.'
    }
    $calls = [regex]::Matches(
        $decompiled,
        '(?i)\bSelf\.SetKeyMapOptionValue\(option,\s*keyCode,\s*False\)'
    )
    if ($calls.Count -ne 12) {
        throw "Expected 12 indexed calls in the decompiled PEX; found $($calls.Count)."
    }
}

function New-DeterministicZip {
    param([string]$SourceDirectory, [string]$DestinationPath)

    Add-Type -AssemblyName System.IO.Compression
    $destinationDirectory = Split-Path -Parent $DestinationPath
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null

    $fileStream = [System.IO.File]::Open(
        $DestinationPath,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    $archive = [System.IO.Compression.ZipArchive]::new(
        $fileStream,
        [System.IO.Compression.ZipArchiveMode]::Create,
        $false,
        [System.Text.Encoding]::UTF8
    )
    try {
        $epoch = [System.DateTimeOffset]::new(
            1980, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero
        )
        $sourcePrefix = [System.IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\') + '\'
        $files = Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File |
            Sort-Object { $_.FullName.Substring($sourcePrefix.Length).Replace('\', '/') }

        foreach ($file in $files) {
            $entryName = $file.FullName.Substring($sourcePrefix.Length).Replace('\', '/')
            $entry = $archive.CreateEntry(
                $entryName,
                [System.IO.Compression.CompressionLevel]::Optimal
            )
            $entry.LastWriteTime = $epoch
            $entryStream = $entry.Open()
            $inputStream = [System.IO.File]::OpenRead($file.FullName)
            try {
                $inputStream.CopyTo($entryStream)
            }
            finally {
                $inputStream.Dispose()
                $entryStream.Dispose()
            }
        }
    }
    finally {
        $archive.Dispose()
        $fileStream.Dispose()
    }
}

function Remove-VerifiedWorkDirectory {
    param([string]$Path, [string]$Root)

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $resolvedTarget = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolvedTarget.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove work directory outside artifact root: $resolvedTarget"
    }
    if (Test-Path -LiteralPath $resolvedTarget) {
        Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
    }
}

$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
$CapricaPath = Resolve-RequiredFile -Path $CapricaPath -Label 'Caprica compiler'
$ChampollionPath = Resolve-RequiredFile -Path $ChampollionPath -Label 'Champollion validator'
$SkyUiSourceRoot = Resolve-RequiredDirectory -Path $SkyUiSourceRoot -Label 'SkyUI source root'
$SkseSourceRoot = Resolve-RequiredDirectory -Path $SkseSourceRoot -Label 'SKSE source root'
$GamePath = Resolve-RequiredDirectory -Path $GamePath -Label 'Skyrim game path'
$vanillaSourceRoot = Resolve-RequiredDirectory `
    -Path (Join-Path $GamePath 'Data\Source\Scripts') `
    -Label 'Creation Kit script source root'
$flagsPath = Resolve-RequiredFile `
    -Path (Join-Path $vanillaSourceRoot 'TESV_Papyrus_Flags.flg') `
    -Label 'Papyrus flags file'

Assert-Sha256 -Path $CapricaPath -Expected $lock.compiler.sha256 -Label 'Caprica'
Assert-Sha256 -Path $ChampollionPath -Expected $lock.validator.sha256 -Label 'Champollion'
foreach ($property in $lock.skyui.files.psobject.Properties) {
    Assert-Sha256 `
        -Path (Join-Path $SkyUiSourceRoot $property.Name) `
        -Expected $property.Value `
        -Label "SkyUI $($property.Name)"
}
foreach ($property in $lock.skseScripts.files.psobject.Properties) {
    Assert-Sha256 `
        -Path (Join-Path $SkseSourceRoot $property.Name) `
        -Expected $property.Value `
        -Label "SKSE $($property.Name)"
}
foreach ($property in $lock.creationKitSources.files.psobject.Properties) {
    Assert-Sha256 `
        -Path (Join-Path $vanillaSourceRoot $property.Name) `
        -Expected $property.Value `
        -Label "Creation Kit $($property.Name)"
}
Assert-Sha256 -Path $sourcePath -Expected $lock.expected.patchedSourceSha256 -Label 'Patched source'
Assert-StaticHotkeys -Path $sourcePath

$ArtifactsRoot = [System.IO.Path]::GetFullPath($ArtifactsRoot)
New-Item -ItemType Directory -Path $ArtifactsRoot -Force | Out-Null
$workRoot = Join-Path $ArtifactsRoot ('.work-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
$result = $null

try {
    $imports = "$repoRoot;$SkyUiSourceRoot;$SkseSourceRoot;$vanillaSourceRoot"
    $normalizedOutputs = @()

    foreach ($run in 1..2) {
        $rawOutput = Join-Path $workRoot "compile-$run\raw"
        $normalizedOutput = Join-Path $workRoot "compile-$run\normalized"
        New-Item -ItemType Directory -Path $rawOutput,$normalizedOutput -Force | Out-Null

        & $CapricaPath `
            --ignorecwd `
            --quiet `
            --game skyrim `
            --import $imports `
            --flags $flagsPath `
            --strict=1 `
            --all-warnings-as-errors `
            --disable-warning 4004 `
            --enable-ck-optimizations=1 `
            --enable-debug-info=0 `
            --output $rawOutput `
            $sourcePath | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Caprica compile $run failed with exit code $LASTEXITCODE."
        }

        $rawPex = Join-Path $rawOutput 'ProteusMCMScript.pex'
        $normalizedPex = Join-Path $normalizedOutput 'ProteusMCMScript.pex'
        & $normalizerPath -InputPath $rawPex -OutputPath $normalizedPex | Out-Null
        $normalizedOutputs += $normalizedPex

        if ($run -eq 1) {
            Start-Sleep -Milliseconds 1200
        }
    }

    $firstHash = (Get-FileHash -LiteralPath $normalizedOutputs[0] -Algorithm SHA256).Hash
    $secondHash = (Get-FileHash -LiteralPath $normalizedOutputs[1] -Algorithm SHA256).Hash
    if ($firstHash -ne $secondHash) {
        throw "Double compilation was not reproducible: $firstHash != $secondHash"
    }
    if ($firstHash -ne $lock.expected.normalizedPexSha256) {
        throw "Compiled PEX does not match the lock: expected $($lock.expected.normalizedPexSha256); found $firstHash"
    }

    Assert-CompiledHotkeys `
        -PexPath $normalizedOutputs[0] `
        -DecompilerPath $ChampollionPath `
        -OutputDirectory (Join-Path $workRoot 'decompiled')

    $version = (Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()
    $packageRoot = Join-Path $workRoot 'package'
    $packageScripts = Join-Path $packageRoot 'Scripts'
    $packageSources = Join-Path $packageRoot 'Source\Scripts'
    New-Item -ItemType Directory -Path $packageScripts,$packageSources -Force | Out-Null

    Copy-Item -LiteralPath $normalizedOutputs[0] -Destination (Join-Path $packageScripts 'ProteusMCMScript.pex')
    Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $packageSources 'ProteusMCMScript.psc')
    foreach ($fileName in @('LICENSE', 'NOTICE.md', 'PROVENANCE.json', 'README.md', 'VERSION')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $fileName) -Destination (Join-Path $packageRoot $fileName)
    }

    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    $manifest = [ordered]@{
        schemaVersion = 1
        name = 'Proteus MCM Indexed Hotkeys'
        version = $version
        files = [ordered]@{
            'Scripts/ProteusMCMScript.pex' = $firstHash
            'Source/Scripts/ProteusMCMScript.psc' = $sourceHash
        }
        build = [ordered]@{
            compiler = "Caprica $($lock.compiler.version)"
            compilerSha256 = $lock.compiler.sha256
            validator = "Champollion $($lock.validator.version)"
            validatorSha256 = $lock.validator.sha256
            skyuiCommit = $lock.skyui.commit
            skseVersion = $lock.skseScripts.version
            skyrimRuntime = $lock.skseScripts.runtime
            deterministicDoubleCompile = $true
            pexHeaderNormalized = $true
            debugInfo = $false
            ckOptimizations = $true
        }
    }
    $manifestPath = Join-Path $packageRoot 'BUILD-MANIFEST.json'
    $manifestJson = $manifest | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText(
        $manifestPath,
        $manifestJson + "`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    $artifactPath = Join-Path $ArtifactsRoot "Proteus-MCM-Indexed-Hotkeys-$version.zip"
    New-DeterministicZip -SourceDirectory $packageRoot -DestinationPath $artifactPath
    $artifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash

    $result = [pscustomobject]@{
        Version = $version
        Artifact = $artifactPath
        ArtifactSHA256 = $artifactHash
        PexSHA256 = $firstHash
        SourceSHA256 = $sourceHash
        Reproducible = $true
    }
}
finally {
    Remove-VerifiedWorkDirectory -Path $workRoot -Root $ArtifactsRoot
}

$result
