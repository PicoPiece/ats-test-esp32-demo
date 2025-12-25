# ats-test-esp32-demo
ESP32 ATS Test Runner
Overview
This repository contains the automated test execution framework for validating ESP32 firmware using real hardware as part of the ATS (Automation Test System) platform.
It is designed to run on ATS nodes (Raspberry Pi / Mini PC) and focuses on execution, observation, and validation, not firmware building.
This repository is intentionally decoupled from firmware source code.
What This Repository Is Responsible For
Flashing ESP32 firmware artifacts produced by CI
Executing automated hardware tests
Observing firmware behavior via:
UART logs
GPIO state
Visual indicators (LED / OLED)
Producing test reports and metrics
Integrating with Jenkins-based test pipelines
What This Repository Does NOT Do
Build firmware
Modify firmware source code
Manage CI orchestration
Own artifact generation
Those responsibilities belong to:
ats-fw-esp32-demo (firmware)
ats-ci-infra (CI orchestration)
Intended Execution Environment
This test runner is expected to run inside a Docker container on ATS nodes.
Typical ATS node setup:
Raspberry Pi / Mini PC
Docker Engine
Jenkins agent (SSH / inbound)
All test logic runs inside the container, not on the host OS.
High-Level Test Flow
Jenkins test pipeline schedules a test job
The test job:
Pulls firmware artifact (firmware.bin)
Pulls execution manifest (ats-manifest.yaml)
The test runner:
Flashes firmware to ESP32
Reboots the device
Observes runtime behavior
Test results are collected as:
Logs
Pass/Fail status
Metrics
Results are archived and reported back to CI
Repository Structure
  ats-test-esp32-demo/
  ├── agent/
  │   ├── flash_fw.sh
  │   ├── run_tests.sh
  │   ├── read_uart.sh
  │   └── gpio_check.sh
  ├── reports/
  ├── Dockerfile
  └── README.md
Manifest-Driven Execution
Test execution is driven by a manifest generated during the firmware build pipeline.
Example fields consumed:
Firmware artifact name
Commit hash
Test plan
Target device
This allows:
Full traceability
Reproducible test runs
Clean separation between build and test
Supported Test Types (Initial)
UART boot validation
GPIO / LED behavior
Firmware stability (reboot / timing)
Visual validation (optional, future)
Relationship to Other Repositories
Firmware source: ats-fw-esp32-demo
CI infrastructure: ats-ci-infra
Platform documentation: ats-platform-docs
Project Status
This repository is under active development and serves as:
A reference implementation
A base for scaling ATS test nodes
A foundation for future test farm automation

Author
Hai Dang Son
Senior Embedded / IoT Engineer


Hai Dang Son
Senior Embedded / IoT Engineer
