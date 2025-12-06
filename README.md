# Amina S EV Charger – SmartThings Edge Driver

## Overview

This driver integrates the **Amina S EV charger** seamlessly with SmartThings, providing full control and monitoring directly within the SmartThings app. It is designed to deliver a stable user experience by showing immediate feedback when you adjust the charging current, and accurately reflecting the current limits set by the charger.

***

## Key Features

### Current Management (Slider Control)
* **Adjust charging current** using the SmartThings slider (the "Dimmer" field).
* The slider supports whole Ampere values from **6 A** up to your configured maximum limit (default 32 A).
* **Immediate UI Feedback:** When you adjust the slider, the app immediately displays the requested value (e.g., 17 A / 44%).
* **Accurate Reflection:** The driver ensures that the current measurement and slider position are updated to the **actual charging current** confirmed by the charger (e.g., if you set 17 A but the charger limits to 10 A, the UI will reflect 10 A / ~15%).

### Basic Control and Measurements
* **On/Off Control:** Turn charging on or off directly from the app. When turned on, the charger restores the last used current value.
* **Measurements:**
    * **Current (A):** Actual charging current.
    * **Power (W):** Active power consumption.
    * **Voltage (V):** Supply voltage.
* **Presence Sensor:** Shows "Present" when the charging power exceeds approximately 10 W (indicating active charging).
* **Manual Refresh:** Press Refresh to update all values (current, power, voltage) from the charger.

***

## Installation and Usage

### Installation

This is a SmartThings **Edge Driver**. It must be installed either through the SmartThings CLI or via a Channel Invitation Link that you add to your Hub.

1.  **Add Channel:** Follow the instructions to add the driver's Channel to your SmartThings Hub.
2.  **Pair the Device:** Put the Amina S charger into pairing mode. The SmartThings Hub will automatically discover the device and assign this driver.

### Usage Instructions
1.  **Set Maximum Current:** If you need to restrict the upper limit of the slider, you can set your preferred maximum current (A) in the device settings within the SmartThings app.
2.  **Adjust Current:** Use the slider to set the desired charging current.
3.  **Monitor Status:** The app confirms the final charging current, ensuring the display reflects the actual current permitted by the charger.

### Automations
* Use **percentage values** in routines for load balancing.
* *Example:* "If total household consumption exceeds 10 kW, set charger to 50%."

***

## User Experience
* **Stable Control:** Commands execute reliably.
* **Accurate Feedback:** The app always reflects the real charging current reported by the charger.
* **Flexible Control:** Full control over all whole Ampere values between 6 A and your maximum configuration.
