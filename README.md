# Amina S driver

## SmartThings Edge Driver for Amina S EV Charger

**Author:** Kristian Kleiveland  
**Version:** 1.0.0  
**License:** MIT License  
**Copyright:** (c) 2025 Kristian Kleiveland

---

## 1. Functional Specification

This document details the SmartThings Edge Driver developed for the Amina S Electric Vehicle (EV) Charger. The driver facilitates local operation and state synchronization via the Zigbee protocol, replacing the generic switch profile assigned by the SmartThings platform.

### 1.1 Implemented Capabilities

| Capability | Function | Protocol Implementation |
| :--- | :--- | :--- |
| **Switch** | Arming and disarming of charging functionality. | Zigbee Cluster 0x0006 (On/Off) |
| **Charge Limit Control** | Configuration of the maximum charging current (6A–32A). | Zigbee Cluster 0x0008 (Level Control) mapped to Ampere calculation. |
| **Power Measurement** | Real-time reporting of active power, voltage, and current. | Zigbee Cluster 0x0B04 (Electrical Measurement) |
| **Energy Consumption** | Retrieval of total lifetime energy usage (kWh). | Custom Zigbee Cluster 0xFEE7. |

### 1.2 Accuracy Note

Measurement attributes received via Cluster 0x0B04 are scaled utilizing the Multiplier/Divisor parameters transmitted by the device, ensuring the reported values (V, A, W) adhere to standard SI units.

---

## 2. Deployment Procedure

Deployment of this driver requires the use of the **SmartThings Command Line Interface (CLI)** for packaging, validation, and installation onto the local Hub environment.

### 2.1 Environment Setup (Windows)

1.  **Node.js Installation:** Install the current Node.js LTS distribution.
2.  **CLI Installation:** Install the SmartThings CLI globally using npm:
    ```bash
    npm install -g @smartthings/cli
    ```
3.  **Authentication:** Authenticate the CLI session with your SmartThings Developer Account:
    ```bash
    smartthings login
    ```

### 2.2 Code Acquisition and Packaging

1.  **Clone Repository:** Execute the following command in the terminal to retrieve the source code:
    ```bash
    git clone [https://github.com/Kleiveland/amina-s-driver.git](https://github.com/Kleiveland/amina-s-driver.git)
    ```
2.  **Directory Navigation:** Navigate into the newly created project directory:
    ```bash
    cd amina-s-driver
    ```
3.  **Driver Validation and Package Creation:** Execute the packaging command. This verifies syntax correctness and bundles the driver.
    ```bash
    smartthings edge:drivers:package .
    ```

### 2.3 Installation and Device Enrollment

1.  **Channel Establishment:** If a distribution channel is not established, execute `smartthings edge:channels:create`.
2.  **Driver Installation:** Install the package to the designated channel and push it to the target Hub:
    ```bash
    smartthings edge:drivers:install
    ```
3.  **Device Disenrollment:** If the Amina S unit is currently paired, it must be disassociated from the platform to ensure the new driver is selected.
4.  **Re-enrollment (Pairing):** Initiate the device discovery process (e.g., power cycle the charger to enter pairing mode). The Hub will match the device fingerprint to this custom driver.

---

## 3. Repository Management and Distribution

### 3.1 Distribution

The driver is distributed via a SmartThings Channel. To generate an invitation link for community sharing, execute:
```bash
smartthings edge:channels:invite
