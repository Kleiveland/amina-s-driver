# Amina S EV Charger - SmartThings Edge Driver

This repository contains a SmartThings Edge Driver for the Amina S Electric Vehicle Charger. It enables local Zigbee control and monitoring directly from a SmartThings Hub, bypassing cloud dependencies.

The driver is specifically engineered to handle the Amina proprietary Zigbee cluster (`0xFEE7`) which is not natively supported by the standard SmartThings Lua SDK.

## Features

* **Charging Control:** Start and stop charging sessions via the standard Switch capability.
* **Amperage Limit:** Set charging current between 6A and 32A using the Dimmer/Level control.
    * 1% = 6A (Minimum)
    * 100% = 32A (Maximum)
* **Metering:** Reports Active Power (W), RMS Voltage (V), and RMS Current (A).
* **Energy Monitoring:** Reports Total Lifetime Energy consumption (kWh).
* **Session Data:** Reports "Last Session Energy" to the device history log.
* **Diagnostics:** Decodes proprietary bitmaps for Alarms and EV Statuses (e.g., "Welded Relay", "Derating", "EV Connected") and pushes them as textual notifications to the device history.

## Technical Implementation

This driver addresses specific compatibility issues between the SmartThings Edge SDK and the Amina S firmware.

### 1. Manual ZCL Construction
The standard SmartThings SDK method `cluster_base.read_attribute` causes runtime crashes when targeting the proprietary cluster `0xFEE7` due to internal type validation logic.

To resolve this, the driver bypasses the high-level library and manually constructs the Zigbee Cluster Library (ZCL) payload using `zcl_global.ReadAttribute`.

### 2. Manufacturer Code Injection
The Amina S firmware requires the Manufacturer Code (`0x143B`) to be present in the ZCL header for operations on custom clusters. The driver explicitly injects this code into the frame control header. Without this, the device ignores read requests to `0xFEE7`.

### 3. Legacy Cluster Support
The driver utilizes the legacy `clusters.Level` definition and command structure instead of the newer `LevelControl` specification to match the specific device fingerprint and behavior observed during testing.

## Project Structure

* `config.yml`: Defines the driver package identity and permissions.
* `fingerprints.yml`: Device fingerprint matching Manufacturer "Amina Distribution AS" and Model "Amina S".
* `profiles/amina-profile.yml`: Definition of device capabilities (Switch, Level, PowerMeter, EnergyMeter, Voltage, Current, Notification).
* `src/init.lua`: Contains the core logic, including the manual ZCL frame construction, bitmap decoding, and event emission.

## Installation

### Prerequisites
* SmartThings Hub
* SmartThings CLI installed and authenticated

### Deployment

1.  **Package the driver:**
    ```bash
    smartthings edge:drivers:package .
    ```

2.  **Install the driver to the Hub:**
    ```bash
    smartthings edge:drivers:install
    ```

3.  **Assign the driver:**
    If the device is already paired as a generic Zigbee device, switch the driver using the CLI. Replace placeholders with actual IDs found via `smartthings devices`.
    ```bash
    smartthings edge:drivers:switch --hub <HUB_ID> --device-id <DEVICE_ID> --driver-id <DRIVER_ID>
    ```

## Usage Notes

**Custom Statuses:**
Standard electrical measurements are configured for periodic reporting. Proprietary statuses (Alarms, specific EV states) are updated when a **Refresh** command is issued (pull-to-refresh in the SmartThings app).

**History Tab:**
SmartThings does not support custom UI tiles for dynamic text strings. Therefore, detailed status messages (e.g., specific alarm codes or session energy stats) are emitted as events to the "History" tab of the device.

## License

MIT License.
