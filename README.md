Amina S - SmartThings Edge Driver
This Edge Driver provides local Zigbee control for the Amina S EV Charger in SmartThings. It is designed to handle proprietary Amina clusters and attributes that are not natively supported by the standard SmartThings Lua SDK.

Features
Charging Control: Start and stop charging via standard Switch capability.

Amperage Limit: Set charging current between 6A and 32A using the Dimmer/Level control.

1% = 6A (Minimum)

100% = 32A (Maximum)

Metering: Reports active power (W), voltage (V), and current (A).

Energy Monitoring: Reports total lifetime energy consumption (kWh).

Session Data: Reports "Last Session Energy" to the device history log.

Diagnostics: Decodes proprietary bitmaps for Alarms and EV Statuses (e.g., "Welded Relay", "Derating") and pushes them as textual notifications to the device history.

Technical Implementation
This driver implements a specific workaround to communicate with the Amina proprietary cluster 0xFEE7. Standard SDK methods (cluster_base.read_attribute) cause runtime crashes with this firmware due to type validation errors.

Key implementation details:

Manual ZCL Construction: The driver bypasses the standard cluster library for 0xFEE7. Instead, it manually constructs the Zigbee ZCL payload using zcl_global.ReadAttribute.

Manufacturer Code Injection: The driver explicitly injects the Amina Manufacturer Code (0x143B) into the ZCL header. Without this code, the device ignores read requests to custom clusters.

Legacy Cluster Support: The driver uses the legacy clusters.Level definition rather than LevelControl to match the specific device fingerprint and behavior.

Project Structure
config.yml: Driver package definition and permissions.

fingerprints.yml: Device fingerprint matching Manufacturer "Amina Distribution AS" and Model "Amina S".

profiles/amina-profile.yml: Definition of device capabilities (Switch, Level, Measurements).

src/init.lua: Core logic, manual ZCL frame construction, and bitmap decoding.

Installation
Prerequisites
SmartThings Hub

SmartThings CLI installed and configured

Steps
Package the driver:

Bash

smartthings edge:drivers:package .
Install the driver to your Hub:

Bash

smartthings edge:drivers:install
Assign the driver to the device: If the device is already paired, switch the driver using the CLI. Replace the placeholders with your actual IDs.

Bash

smartthings edge:drivers:switch --hub <HUB_ID> --device-id <DEVICE_ID> --driver-id <DRIVER_ID>
Usage Notes
Status Updates: Standard electrical measurements (Voltage, Amps, Power) are configured for periodic reporting. Proprietary statuses (Alarms, specific EV states) are updated when a Refresh command is issued (pull-to-refresh in the app).

History Tab: Since SmartThings does not support custom UI tiles for arbitrary text, detailed status messages (e.g., specific alarm codes or session energy) are sent as events to the "History" tab of the device.

License
MIT License.
