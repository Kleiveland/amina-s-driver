# Amina S driver

**Author:** Kristian Kleiveland
**Version:** 1.0.0
**License:** MIT License

A robust SmartThings Edge Driver for the Amina S EV Charger, providing local control and accurate power/energy measurements over the Zigbee protocol. This driver overrides the generic SmartThings 'switch' driver.

## Features

* **Local Control:** All functions run locally on your SmartThings Hub.
* **Switch:** Arm/Disarm charging (On/Off).
* **Charge Limit:** Set charging current (6A–32A) using the Level Control slider (0–100%).
* **Accurate Measurements:** Power (W), Voltage (V), Current (A), and Total Energy (kWh) using scaling factors retrieved directly from the device.

## Installation and Setup

[Se fullstendige instruksjoner i den store veiledningen]

## Technical Details

* **Manufacturer:** Amina Distribution AS
* **Model:** amina S
* **Custom Cluster Handled:** 0xFEE7 (for Energy)
* **Measurement Cluster:** 0x0B04 (Handled with scaling factors for accuracy)