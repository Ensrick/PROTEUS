# Release candidate 0.1.0

- Artifact: `Proteus-MCM-Indexed-Hotkeys-0.1.0.zip`
- Artifact SHA-256: `F502270AADAEFB9CFAC07F7D463124D0AB8EBA872844CA577CDFCDA1489C2D6E`
- PEX SHA-256: `8EA0FC06CA21EEC16A450EAF8BD45D7F9A6D0EF2578A63ED0684B72655735FE8`
- Patched source SHA-256: `A4A2B04113CEA38298FEE25D4ED3AC7CFA18CEE4A020DC6AE6133234C9306BE1`

Verification completed:

- Twelve active `OnOptionKeyMapChange` branches use `SetKeyMapOptionValue(option, keyCode, false)`.
- No `SetKeyMapOptionValueST` reference remains.
- Two independent Caprica compilations normalize to identical PEX bytes.
- Rebuilding the complete ZIP produces the same artifact hash.
- Champollion decompilation finds twelve indexed calls and no state-option call.

Outstanding acceptance:

- Install as a separate MO2 overlay on a disposable profile/save.
- Rebind one Proteus MCM action, close and reopen MCM, and confirm the displayed binding persists.
- Invoke the rebound action outside menus.
- Save a Proteus character and confirm its `JCUser/Proteus` data is created.

The candidate has not been installed into the live MO2 profile.
