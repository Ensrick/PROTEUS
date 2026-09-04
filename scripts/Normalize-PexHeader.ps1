[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-UInt16BigEndian {
    param(
        [byte[]]$Bytes,
        [ref]$Offset
    )

    if ($Offset.Value + 2 -gt $Bytes.Length) {
        throw 'Unexpected end of PEX header while reading a string length.'
    }

    $value = ([int]$Bytes[$Offset.Value] -shl 8) -bor [int]$Bytes[$Offset.Value + 1]
    $Offset.Value += 2
    return $value
}

function Skip-PexString {
    param(
        [byte[]]$Bytes,
        [ref]$Offset
    )

    $length = Read-UInt16BigEndian -Bytes $Bytes -Offset $Offset
    if ($Offset.Value + $length -gt $Bytes.Length) {
        throw 'Unexpected end of PEX header while reading a string.'
    }
    $Offset.Value += $length
}

function Write-PexString {
    param(
        [System.IO.BinaryWriter]$Writer,
        [string]$Value
    )

    $encoded = [System.Text.Encoding]::UTF8.GetBytes($Value)
    if ($encoded.Length -gt [uint16]::MaxValue) {
        throw "PEX header string is too long: $Value"
    }

    $Writer.Write([byte](($encoded.Length -shr 8) -band 0xFF))
    $Writer.Write([byte]($encoded.Length -band 0xFF))
    $Writer.Write($encoded)
}

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$bytes = [System.IO.File]::ReadAllBytes($resolvedInput)

if ($bytes.Length -lt 24) {
    throw "File is too short to be a PEX file: $resolvedInput"
}

$expectedMagic = [byte[]](0xFA, 0x57, 0xC0, 0xDE)
for ($index = 0; $index -lt $expectedMagic.Length; $index++) {
    if ($bytes[$index] -ne $expectedMagic[$index]) {
        throw "Unsupported PEX magic in: $resolvedInput"
    }
}

# Skyrim PEX header: magic/version/game (8), compile timestamp (8), then
# source/user/computer as big-endian uint16-length-prefixed UTF-8 strings.
$offset = 16
Skip-PexString -Bytes $bytes -Offset ([ref]$offset)
Skip-PexString -Bytes $bytes -Offset ([ref]$offset)
Skip-PexString -Bytes $bytes -Offset ([ref]$offset)

$outputDirectory = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$stream = [System.IO.MemoryStream]::new()
$writer = [System.IO.BinaryWriter]::new($stream, [System.Text.Encoding]::UTF8, $true)
try {
    $writer.Write($bytes, 0, 8)
    $writer.Write([byte[]](0, 0, 0, 0, 0, 0, 0, 0))
    Write-PexString -Writer $writer -Value 'ProteusMCMScript.psc'
    Write-PexString -Writer $writer -Value 'reproducible'
    Write-PexString -Writer $writer -Value 'reproducible'
    $writer.Write($bytes, $offset, $bytes.Length - $offset)
    $writer.Flush()
    [System.IO.File]::WriteAllBytes($resolvedOutput, $stream.ToArray())
}
finally {
    $writer.Dispose()
    $stream.Dispose()
}

$hash = (Get-FileHash -LiteralPath $resolvedOutput -Algorithm SHA256).Hash
[pscustomobject]@{
    Path = $resolvedOutput
    SHA256 = $hash
    Bytes = (Get-Item -LiteralPath $resolvedOutput).Length
}
