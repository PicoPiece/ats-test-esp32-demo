#!/bin/bash
# Flash ESP32 firmware
# Usage: flash_fw.sh <firmware.bin> <platform>

set -e

FW_FILE="${1:-firmware-esp32.bin}"
PLATFORM="${2:-ESP32}"

if [ ! -f "$FW_FILE" ]; then
    echo "❌ Firmware file not found: $FW_FILE"
    exit 1
fi

echo "🔌 [ATS] Flashing ${PLATFORM} firmware: $FW_FILE"

# Detect ESP32 port
# Try common USB serial ports
ESP_PORT=""
for port in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyACM0 /dev/ttyACM1; do
    if [ -e "$port" ]; then
        # Check if it's an ESP32 device
        if udevadm info "$port" 2>/dev/null | grep -q "ID_SERIAL_SHORT"; then
            ESP_PORT="$port"
            break
        fi
    fi
done

# If no port found, try to detect
if [ -z "$ESP_PORT" ]; then
    echo "⚠️  Auto-detecting ESP32 port..."
    ESP_PORT=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | head -1)
fi

if [ -z "$ESP_PORT" ] || [ ! -e "$ESP_PORT" ]; then
    echo "❌ ESP32 device not found"
    echo "   Please connect ESP32 via USB"
    echo "   Available ports:"
    ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo "   None found"
    exit 1
fi

echo "📡 Using port: $ESP_PORT"

# Flash firmware using esptool
# ESP32 flash layout:
# 0x1000  bootloader.bin
# 0x8000   partition-table.bin
# 0x10000  firmware.bin

echo "📤 Flashing firmware to ESP32..."

# For now, flash only the app partition (0x10000)
# In production, you might want to flash bootloader and partition table too
esptool.py --chip esp32 \
    --port "$ESP_PORT" \
    --baud 460800 \
    --before default_reset \
    --after hard_reset \
    write_flash \
    --flash_mode dio \
    --flash_freq 40m \
    --flash_size detect \
    0x10000 "$FW_FILE"

if [ $? -eq 0 ]; then
    echo "✅ Firmware flashed successfully"
    echo "🔄 Resetting ESP32..."
    esptool.py --chip esp32 --port "$ESP_PORT" run
else
    echo "❌ Firmware flash failed"
    exit 1
fi

