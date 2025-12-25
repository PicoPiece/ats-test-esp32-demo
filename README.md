# ATS Test ESP32 Demo

> **ESP32 ATS Test Runner - Hardware test execution framework**

This repository contains the automated test execution framework for validating ESP32 firmware using real hardware as part of the ATS (Automation Test System) platform.

It is designed to run on ATS nodes (Raspberry Pi / Mini PC) and focuses on execution, observation, and validation, not firmware building.

**This repository is intentionally decoupled from firmware source code.**

---

## 📁 Repository Structure

```
ats-test-esp32-demo/
├── README.md
├── agent/
│   ├── flash_fw.sh
│   ├── run_tests.sh
│   ├── read_uart.sh
│   └── gpio_check.sh
├── reports/
├── Dockerfile
└── README.md
```

---

## ✅ What This Repository Is Responsible For

- ✅ **Pure test execution logic** (hardware-agnostic)
- ✅ Reading test parameters from `ats-manifest.yaml`
- ✅ Executing automated hardware tests (assuming firmware is already flashed)
- ✅ Observing firmware behavior via:
  - UART logs (from serial port)
  - GPIO state (from environment variables)
  - Visual indicators (LED / OLED)
- ✅ Producing structured test results:
  - `ats-summary.json`
  - `junit.xml`
  - `serial.log`
  - `meta.yaml`
- ✅ Integrating with Jenkins-based test pipelines

**This repository contains NO hardware interaction logic** (flashing, USB detection) — that belongs to `ats-ats-node`.

---

## ❌ What This Repository Does NOT Do

- ❌ Build firmware → `ats-fw-esp32-demo`
- ❌ Modify firmware source code → `ats-fw-esp32-demo`
- ❌ Manage CI orchestration → `ats-ci-infra`
- ❌ Own artifact generation → `ats-fw-esp32-demo`
- ❌ Flash firmware → `ats-ats-node`
- ❌ Detect USB/hardware → `ats-ats-node`
- ❌ Control GPIO directly → `ats-ats-node` (uses env vars instead)

**This repository is hardware-agnostic and assumes firmware is already flashed and ready for testing.**

---

## 🏗️ Intended Execution Environment

This test runner is expected to run inside a Docker container on ATS nodes.

**Typical ATS node setup:**

- Raspberry Pi / Mini PC
- Docker Engine
- Jenkins agent (SSH / inbound)

**All test logic runs inside the container, not on the host OS.**

---

## 🔄 High-Level Test Flow

1. **Jenkins test pipeline schedules a test job on ATS node**
2. **ATS Node (`ats-ats-node`):**
   - Pulls firmware artifact (`firmware-esp32.bin`) and manifest (`ats-manifest.yaml`)
   - Runs `ats-node-test` Docker container
   - Container flashes firmware to ESP32
   - Container invokes test runner (`ats-test-esp32-demo`)
3. **Test Runner (`ats-test-esp32-demo`):**
   - Reads `ats-manifest.yaml` for test parameters
   - Assumes firmware is already flashed
   - Executes test logic (UART read, GPIO check, etc.)
   - Generates structured results
4. **ATS Node collects results:**
   - `ats-summary.json`
   - `junit.xml`
   - `serial.log`
   - `meta.yaml`
5. **Results are archived and reported back to CI**

---

## 📋 Manifest-Driven Execution

Test execution is driven by a manifest (`ats-manifest.yaml`) generated during the firmware build pipeline.

**Manifest Schema:** [ATS Manifest Specification v1](../ats-platform-docs/architecture/ats-manifest-spec-v1.md)

**Example fields consumed:**

- `build.artifact.name` - Firmware artifact filename
- `build.git.commit` - Commit hash
- `test_plan` - List of tests to execute
- `device.target` - Device target (e.g., `esp32`)
- `device.board` - Board identifier

**This allows:**

- Full traceability
- Reproducible test runs
- Clean separation between build and test
- Hardware-agnostic test logic

---

## 🧪 Supported Test Types (Initial)

- UART boot validation
- GPIO / LED behavior
- Firmware stability (reboot / timing)
- Visual validation (optional, future)

---

## 🔗 Relationship to Other Repositories

- **Firmware source:** `ats-fw-esp32-demo`
- **CI infrastructure:** `ats-ci-infra`
- **Platform documentation:** `ats-platform-docs`
- **Hardware access tools:** `ats-ats-node`

---

## 📊 Project Status

This repository is under active development and serves as:

- A reference implementation
- A base for scaling ATS test nodes
- A foundation for future test farm automation

---

## 👤 Author

**Hai Dang Son**  
Senior Embedded / IoT Engineer
