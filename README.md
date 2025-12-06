# Amina S driver
Copyright (c) 2025 Kristian Kleiveland  
Licensed under the MIT License.

## Overview

This SmartThings Zigbee driver integrates the Amina S EV charger using endpoint 10 and Level Control semantics mapped directly to amps. It provides:

- Switch on/off
- Slider to set charging current (switchLevel)
- Current, power, and voltage readings
- Presence indication based on active power
- Manual refresh to fetch actual device state

Design goals:
- Stable UI without automatic reads or configure reporting
- Immediate feedback for amps when you send a command
- Authoritative slider updates only when the device reports back

## Installation

1. Package the driver and profile (init.lua, config.yml) into a SmartThings Edge driver bundle.
2. Install the driver on your SmartThings hub (via CLI or channel).
3. Pair the Amina S EV charger; the device should expose endpoint 10 with Level/OnOff/ElectricalMeasurement.
4. Assign the “amina-profile” to the device.

No automatic reporting or reads are configured. You can manually refresh to fetch current values.

## Slider mapping: percentage → amps

- Range: 6 A (minimum) to your maxCurrent preference (default: 32 A).
- Mapping: percent 0–100 scales linearly from 6 A to maxCurrent.
- Example:
  - 0% → 6 A
  - 50% → ~19 A (with maxCurrent = 32)
  - 100% → 32 A (with maxCurrent = 32)

We emit currentMeasurement immediately when you set the slider or turn the switch on. The slider (switchLevel) itself is updated only when the device reports its confirmed CurrentLevel value.

## Switch on/off behavior

- On: Sends On to the charger, then restores the last set amps (or maxCurrent if none is stored). Emits currentMeasurement immediately. The slider updates after the device reports CurrentLevel.
- Off: Sends Off and updates the switch capability to off. No amps are changed.

## Refresh

- Manual refresh reads:
  - ElectricalMeasurement.ActivePower (W)
  - Level.CurrentLevel (amps)
  - ElectricalMeasurement.RMSVoltage (V)

Use refresh to synchronize the UI to the device’s actual limits (e.g., if the charger physically caps at 10 A, the device will report 10 A, and the slider will update accordingly).

## Changing maxCurrent

- Open the device in SmartThings and adjust the “Max Charging Current (A)” preference.
- Range: 6–32 A
- Default: 32 A
- This preference sets the upper bound for slider mapping and for restores when you turn the switch on.

## Notes on behavior

- No automatic configure reporting is used. This prevents unsolicited UI churn and ensures that you remain in control via manual refresh.
- If you request a current above a physical cap (e.g., charger limited to 10 A), the device will report back its actual CurrentLevel (10 A). After a manual refresh (or device report), the slider will update to reflect 10 A.

## License

MIT License © 2025 Kristian Kleiveland
