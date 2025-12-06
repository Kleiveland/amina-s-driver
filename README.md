# Amina S driver
Copyright (c) 2025 Kristian Kleiveland  
Licensed under the MIT License.

## Overview

This SmartThings Zigbee driver integrates the Amina S EV charger using endpoint 10 and Level Control mapped directly to amps. It provides:

- Switch on/off
- Slider to set charging current (switchLevel)
- Current, power, and voltage readings
- Presence indication based on active power
- Manual refresh to fetch actual device state

Design goals:
- Stable UI without automatic reads or configure reporting
- Immediate feedback for amps when you send a command
- Authoritative slider updates only when the device reports back

---

## Files

- **init.lua**  
  Contains the driver logic. Handles commands, maps slider % to amps, and processes device reports.

- **config.yml**  
  Defines the SmartThings profile (capabilities, categories, preferences). Includes the `maxCurrent` preference (default 32 A).

Place both files in your driver source folder when packaging.

---

## Installation

1. **Prepare driver bundle**  
   - Put `init.lua` and `config.yml` into your SmartThings Edge driver project folder.  
   - Add a `package.yml` if required by your CLI setup.

2. **Build and install**  
   - Use the SmartThings CLI:  
     ```bash
     smartthings edge:drivers:package .
     smartthings edge:drivers:install <driverId> --hub <hubId>
     ```
   - Alternatively, publish via your SmartThings channel.

3. **Pair the charger**  
   - Reset/pair the Amina S EV charger with your SmartThings hub.  
   - Assign the `amina-profile` to the device.

---

## Slider mapping: percentage → amps

- Range: 6 A (minimum) to your `maxCurrent` preference (default: 32 A).
- Mapping: percent 0–100 scales linearly from 6 A to maxCurrent.
- Example (maxCurrent = 32 A):
  - 0% → 6 A  
  - 50% → ~19 A  
  - 100% → 32 A  

The driver emits `currentMeasurement` immediately when you set the slider. The slider (`switchLevel`) itself updates only when the device reports its confirmed `CurrentLevel`.

---

## Switch on/off behavior

- **On**: Sends On to the charger, then restores the last set amps (or maxCurrent if none stored). Emits `currentMeasurement` immediately. Slider updates after the device reports `CurrentLevel`.  
- **Off**: Sends Off and updates the switch capability to off. No amps are changed.

---

## Refresh

Manual refresh reads:
- ElectricalMeasurement.ActivePower (W)
- Level.CurrentLevel (amps)
- ElectricalMeasurement.RMSVoltage (V)

Use refresh to synchronize the UI to the device’s actual limits (e.g., if the charger is physically capped at 10 A, the device will report 10 A, and the slider will update accordingly).

---

## Changing maxCurrent

- Open the device in SmartThings and adjust the **Max Charging Current (A)** preference.  
- Range: 6–32 A  
- Default: 32 A  

This preference sets the upper bound for slider mapping and for restores when you turn the switch on.

---

## Automation with % for load sharing

You can use SmartThings automations or Rules to set the **switchLevel** capability in percent. The driver maps this percent to amps relative to your configured `maxCurrent`.

### Example: Load sharing between two chargers

- Charger A and Charger B both have `maxCurrent = 32 A`.  
- You want them to split available load dynamically.

Automation rule:
- If total load > threshold, set Charger A to 50% and Charger B to 50%.  
- Driver maps 50% → ~19 A each.  
- If load drops, set both back to 100% (32 A each).

### Example: Relative scaling

- With `maxCurrent = 16 A` (preference changed),  
  - 50% → ~11 A  
  - 100% → 16 A  

This allows you to write automations in **percent** without hardcoding absolute amps. The driver automatically scales based on the configured maxCurrent.

---

## Notes

- No automatic configure reporting is used. Manual refresh ensures you stay in control.  
- If you request a current above the physical cap (e.g., charger limited to 10 A), the device will report back its actual `CurrentLevel`. After a manual refresh (or device report), the slider will update to reflect 10 A.  
- For load sharing, always use **percent values** in automations. This keeps rules portable across chargers with different maxCurrent settings.

---

## License

MIT License © 2025 Kristian Kleiveland
