# Amina S EV Charger - SmartThings Edge Driver

This Edge Driver provides local Zigbee control for the Amina S EV Charger, utilizing a custom ZCL messaging technique to ensure robust, full feature support and advanced automation capabilities in SmartThings.

## Functionality

* **Switch Control:** Basic on/off control of the charger.
* **Current Limit:** Adjust charging current (Amperes) using the Level control slider (6A to 32A).
* **Real-time Metering:** Voltage (V), Current (A), Active power (W), and Total consumption (kWh).
* **Error Handling:** Alerts for critical faults and alarms are reported via the Tamper Alert capability and app notifications.
* **Enhanced Automation:** Converts the charger's status bits into standard SmartThings sensors for use in routines.

## Status to SmartThings Sensors

This table shows the mapping of proprietary EV status bits to standard SmartThings capabilities, making them direct triggers for automation.

| Bit | Status Type | Capability Mapping |
| :---: | :--- | :--- |
| **0** | EV Connected | `contactSensor` (closed/open) |
| **2** | Power Delivered | `motionSensor` (active/inactive) |
| **4** | EV Ready | `presenceSensor` (present/not present) |
| **15** | Derating (High Temp) | `temperatureAlarm` (heat/cleared) |

## Installation and Presentation

### Trinn 1: Package and Install Driver

1.  **Package the driver:**
    ```bash
    smartthings edge:drivers:package .
    ```

2.  **Install to Hub:**
    ```bash
    smartthings edge:drivers:install
    ```

### Trinn 2: Generate and Assign Visual Presentation (VID)

To ensure the new sensors and controls are displayed correctly in the SmartThings App UI, you must generate a Device Presentation.

1.  **Generate Presentation Configuration:** Run this command to create the necessary visual metadata:
    ```bash
    smartthings presentation:device-config:generate -p amina-profile -n "Amina S Charger" -m "Amina Distribution AS"
    ```

2.  **Assign the Driver:** If the device is already added to SmartThings, update it to use your new driver ID:
    ```bash
    smartthings edge:drivers:switch --hub <HUB_ID> --device-id <DEVICE_ID> --driver-id <YOUR_NEW_DRIVER_ID>
    ```

## License

MIT License.
