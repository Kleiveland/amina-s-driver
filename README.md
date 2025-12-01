# Amina S driver

## SmartThings Edge Driver for Amina S EV Charger

**Author:** Kristian Kleiveland  
**Version:** 1.0.0  
**License:** MIT License  
**Copyright:** (c) 2025 Kristian Kleiveland

---

## 1. Functional Specification and Capabilities

This Edge Driver provides full local control and enhanced data monitoring for the Amina S EV Charger, replacing the default, limited SmartThings 'switch' profile. The driver runs locally on the SmartThings Hub for maximum speed and reliability.

### 1.1 Key Features and Control

| Capability | User Action / Practical Function |
| :--- | :--- |
| **Switch** | Enables and disables the charger's readiness state (Controls power relay). |
| **Charge Limit Control** | Configuration of the maximum charging current (6A–32A). |
| **Power Measurement** | Real-time reporting of active power, voltage, and current. |
| **Energy Consumption** | Retrieval of total lifetime energy usage (kWh). |
| **Alarm / Notification** | Reports critical hardware errors, safety warnings (e.g., leakage, overvoltage), and processing issues via SmartThings Notifications. |
| **Status Tracking** | Detailed tracking of charger state (EV Connected, Power Delivered, Derating, Paused). |

### 1.2 Accuracy and Robustness

Measurement attributes are scaled using device-specific factors, ensuring the reported Volt, Ampere, and Watt values are precise. The driver is configured to request automatic data reporting from the charger, guaranteeing instant status updates without constant polling.

---

## 2. Deployment Procedure

Deployment requires the **SmartThings Command Line Interface (CLI)** to validate, package, and install the driver onto your local Hub.

### 2.1 Environment Setup (Cross-Platform)

The CLI tool requires **Node.js (LTS)** and **npm** to be installed.

1.  **Node.js Installation:** Install the Node.js LTS distribution. Utiliser plattform-spesifikke pakkeadministratorer (f.eks. Homebrew på macOS, `apt` på Linux) eller last ned direkte fra [nodejs.org](https://nodejs.org/).

    *Example (Linux/Debian-based):*
    ```bash
    sudo apt update
    sudo apt install nodejs npm
    ```

2.  **Install SmartThings CLI:** Installer CLI globalt ved å bruke npm:
    ```bash
    npm install -g @smartthings/cli
    ```

3.  **Authentication:** Autentiser CLI-sesjonen med din SmartThings utviklerkonto:
    ```bash
    smartthings login
    ```

### 2.2 Code Acquisition and Packaging

1.  **Clone Repository:** Utfør følgende kommando i terminalen for å hente kildekoden:
    ```bash
    git clone [https://github.com/Kleiveland/amina-s-driver.git](https://github.com/Kleiveland/amina-s-driver.git)
    ```
2.  **Directory Navigation:** Naviger inn i den nyopprettede prosjektmappen:
    ```bash
    cd amina-s-driver
    ```
3.  **Driver Validation and Package Creation:** Utfør pakkekommandoen for å verifisere syntaks og samle driveren.
    ```bash
    smartthings edge:drivers:package .
    ```

### 2.3 Installation and Device Enrollment

1.  **Channel Establishment:** Hvis en distribusjonskanal ikke er etablert, utfør `smartthings edge:channels:create`.
2.  **Driver Installation:** Installer pakken til den utpekte kanalen og push den til mål-Huben:
    ```bash
    smartthings edge:drivers:install
    ```
3.  **Device Disenrollment:** Hvis Amina S-enheten er paret, fjern den fra SmartThings-appen for å sikre at den nye driveren velges.
4.  **Re-enrollment (Pairing):** Start enhetens oppdagelsesprosess (f.eks. slå av og på laderen for å gå inn i paringsmodus). Huben vil matche enhetens fingeravtrykk og bruke denne tilpassede driveren.

Driveren distribueres via en SmartThings Channel. For å generere en invitasjonslenke for deling i fellesskapet, utfør:
```bash
smartthings edge:channels:invite
