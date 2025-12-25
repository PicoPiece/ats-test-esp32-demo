#!/bin/bash
# Check GPIO state on Raspberry Pi
# This script checks GPIO pins connected to ESP32
# Usage: gpio_check.sh <gpio_pin> [expected_state]

set -e

GPIO_PIN="${1}"
EXPECTED_STATE="${2:-1}"

if [ -z "$GPIO_PIN" ]; then
    echo "❌ GPIO pin number required"
    echo "Usage: gpio_check.sh <gpio_pin> [expected_state]"
    exit 1
fi

echo "🔌 [ATS] Checking GPIO pin $GPIO_PIN"

# Check if running on Raspberry Pi
if [ ! -d /sys/class/gpio ]; then
    echo "⚠️  GPIO not available (not running on Raspberry Pi?)"
    echo "   Creating dummy GPIO check result"
    echo "GPIO_${GPIO_PIN}=UNKNOWN" > gpio_check_result.txt
    exit 0
fi

# Export GPIO pin
if [ ! -d "/sys/class/gpio/gpio${GPIO_PIN}" ]; then
    echo "$GPIO_PIN" > /sys/class/gpio/export 2>/dev/null || {
        echo "⚠️  Failed to export GPIO $GPIO_PIN (may already be exported)"
    }
    sleep 0.1
fi

# Set as input
echo "in" > "/sys/class/gpio/gpio${GPIO_PIN}/direction" 2>/dev/null || {
    echo "⚠️  Failed to set GPIO $GPIO_PIN direction"
}

# Read GPIO value
GPIO_VALUE=$(cat "/sys/class/gpio/gpio${GPIO_PIN}/value" 2>/dev/null || echo "0")

echo "📊 GPIO $GPIO_PIN state: $GPIO_VALUE (expected: $EXPECTED_STATE)"

# Compare with expected state
if [ "$GPIO_VALUE" = "$EXPECTED_STATE" ]; then
    echo "✅ GPIO check PASSED"
    echo "GPIO_${GPIO_PIN}=PASS" > gpio_check_result.txt
    exit 0
else
    echo "❌ GPIO check FAILED (got $GPIO_VALUE, expected $EXPECTED_STATE)"
    echo "GPIO_${GPIO_PIN}=FAIL" > gpio_check_result.txt
    exit 1
fi

