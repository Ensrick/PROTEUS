# Proteus MCM Indexed Hotkeys

This is a narrowly scoped compatibility overlay for [Proteus 3.4.0](https://www.nexusmods.com/skyrimspecialedition/mods/62934). It corrects the MCM callback used when a Proteus hotkey is rebound.

Proteus creates ordinary indexed SkyUI options with `AddKeyMapOption`, but its 3.4.0 `OnOptionKeyMapChange` handler calls the state-option-only `SetKeyMapOptionValueST`. This overlay changes each of the twelve active branches to:

```papyrus
self.SetKeyMapOptionValue(option, keyCode, false)
```

The overlay does not change Proteus defaults, assign keys, replace `PROTEUS.esp`, or replace `Proteus.dll`. The repeated `9999` defaults remain intentionally unbound. Proteus's normal primary entry point remains the `Proteus - Wheel` lesser power.

## Status

Version 0.1.0 is a build-verified test candidate. Static source tests, deterministic double compilation, PEX-header normalization, and compiled-code decompilation checks pass. In-game MCM persistence and character switching still require a disposable-save acceptance test before release.

## Requirements

- Original Proteus 3.4.0
- SkyUI Community 6.11
- SKSE scripts appropriate for the running Skyrim version

The packaged overlay contains only the corrected script source, compiled PEX, license, notice, and provenance. It does not bundle Proteus's ESP/DLL or any SkyUI, SKSE, Creation Kit, or Bethesda dependency.

## Build

On the maintained Windows build host, the script auto-discovers the pinned local Caprica, SkyUI Community, MO2, and Skyrim installations. Every path can also be supplied explicitly:

```powershell
pwsh -File scripts/Build-Overlay.ps1 `
  -CapricaPath C:\path\to\Caprica.exe `
  -SkyUiSourceRoot C:\path\to\SkyUI-Community\source\scripts `
  -SkseSourceRoot C:\path\to\SKSE\Scripts\Source `
  -GamePath 'C:\path\to\Skyrim Special Edition' `
  -ChampollionPath C:\path\to\Champollion.exe
```

The build:

1. verifies the pinned compiler and source dependencies;
2. checks all twelve hotkey branches and rejects any remaining state-option call;
3. compiles twice with Caprica 0.3.0;
4. normalizes non-functional PEX header metadata;
5. requires the two compiled outputs to be byte-identical;
6. decompiles the candidate and verifies the indexed calls survived compilation; and
7. creates a deterministic MO2-ready ZIP in `artifacts/`.

Run the portable source checks with:

```powershell
python -m unittest discover -s tests -v
```

## Installation candidate

After review, install the generated ZIP as its own MO2 mod below Proteus so its single `Scripts/ProteusMCMScript.pex` wins. Do not copy it into the vendor mod. No live profile has been changed by this repository.

Tracked by [Ensrick/skyrim-mod-assistant#216](https://github.com/Ensrick/skyrim-mod-assistant/issues/216).
