# Raspberry Pi Setup Guide for ATS Test Node

This guide explains how to set up a Raspberry Pi as an ATS test node to run hardware tests for ESP32 firmware.

## Prerequisites

- Raspberry Pi 4 (recommended) or Raspberry Pi 3B+
- MicroSD card (16GB+)
- ESP32 development board
- USB cable to connect ESP32 to Raspberry Pi
- (Optional) GPIO connections for GPIO testing

## 1. Install Raspberry Pi OS

1. Flash Raspberry Pi OS (64-bit) to microSD card
2. Enable SSH: Create empty file `ssh` in boot partition
3. Boot Raspberry Pi and connect via SSH

## 2. Install Docker

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group (logout/login required)
sudo usermod -aG docker $USER

# Verify installation
docker --version
```

## 3. Configure USB/Serial Access

```bash
# Add user to dialout group for serial port access
sudo usermod -aG dialout $USER

# Create udev rules for ESP32 devices
sudo tee /etc/udev/rules.d/99-esp32.rules > /dev/null <<EOF
# ESP32 devices
SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", MODE="0666", GROUP="dialout"
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", MODE="0666", GROUP="dialout"
SUBSYSTEM=="tty", ATTRS{idVendor}=="303a", MODE="0666", GROUP="dialout"
EOF

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Logout and login again for group changes to take effect
```

## 4. Install Jenkins Agent

### Option A: SSH Agent (Recommended)

1. On Jenkins Master, add new node:
   - Name: `ats-pi-01` (or your preferred name)
   - Type: Permanent Agent
   - Remote root directory: `/home/pi/jenkins-agent`
   - Launch method: Launch agents via SSH
   - Host: `<raspberry-pi-ip>`
   - Credentials: SSH username/password or key
   - Labels: `ats-node`

2. On Raspberry Pi:
```bash
mkdir -p ~/jenkins-agent
# Jenkins will automatically connect via SSH
```

### Option B: Inbound Agent (Alternative)

```bash
# Download agent JAR from Jenkins
wget http://<jenkins-master>:8080/jnlpJars/agent.jar

# Run agent (replace with your secret)
java -jar agent.jar -jnlpUrl http://<jenkins-master>:8080/computer/ats-pi-01/slave-agent.jnlp -secret <secret>
```

## 5. Test Hardware Access

```bash
# Check USB devices
ls -la /dev/ttyUSB* /dev/ttyACM*

# Check GPIO access
ls -la /sys/class/gpio/

# Test Docker with hardware
docker run --rm --privileged --device=/dev/ttyUSB0 alpine ls -la /dev/ttyUSB0
```

## 6. Build Test Container

```bash
# Clone test framework
git clone https://github.com/PicoPiece/ats-test-esp32-demo.git
cd ats-test-esp32-demo

# Build Docker image
docker build -t ats-test-runner:esp32 .

# Test container
docker run --rm --privileged \
  --device=/dev/ttyUSB0 \
  -v $(pwd):/app \
  -w /app \
  ats-test-runner:esp32 \
  esptool.py --chip esp32 --port /dev/ttyUSB0 chip_id
```

## 7. Verify Jenkins Connection

1. Go to Jenkins UI → Manage Jenkins → Nodes
2. Check that `ats-pi-01` is connected (green)
3. Test by running a simple pipeline job

## Troubleshooting

### USB Device Not Found

```bash
# Check USB devices
lsusb

# Check udev rules
cat /etc/udev/rules.d/99-esp32.rules

# Check permissions
ls -la /dev/ttyUSB*
```

### GPIO Access Denied

```bash
# Check GPIO permissions
ls -la /sys/class/gpio/
ls -la /dev/gpiomem

# Run container with privileged mode
docker run --rm --privileged -v /sys/class/gpio:/sys/class/gpio:ro ...
```

### Docker Permission Denied

```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Logout and login again
```

## Hardware Connections

### ESP32 to Raspberry Pi

- **USB**: Connect ESP32 via USB cable to Raspberry Pi USB port
- **GPIO** (optional): Connect ESP32 GPIO pins to Raspberry Pi GPIO for testing

### GPIO Pin Mapping (Example)

- ESP32 GPIO2 → Raspberry Pi GPIO18 (for LED test)
- ESP32 GND → Raspberry Pi GND
- ESP32 3.3V → Raspberry Pi 3.3V (if needed)

**Note**: Adjust GPIO pins based on your hardware setup.

## Next Steps

Once setup is complete:

1. Jenkins pipeline will automatically:
   - Checkout test framework
   - Build Docker container
   - Flash firmware to ESP32
   - Run hardware tests
   - Collect test reports

2. Monitor test execution in Jenkins UI

3. Check test reports in Jenkins build artifacts

