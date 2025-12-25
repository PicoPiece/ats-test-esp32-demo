#!/bin/bash
# Check GPIO state on Raspberry Pi with retry logic
# This script checks GPIO pins connected to ESP32
# Usage: gpio_check.sh <gpio_pin> [expected_state] [max_retries]

set -e

GPIO_PIN="${1}"
EXPECTED_STATE="${2:-1}"
MAX_RETRIES="${3:-3}"

if [ -z "$GPIO_PIN" ]; then
    echo "❌ GPIO pin number required"
    echo "Usage: gpio_check.sh <gpio_pin> [expected_state] [max_retries]"
    exit 1
fi

echo "🔌 [ATS] Checking GPIO pin $GPIO_PIN (expected: $EXPECTED_STATE, max retries: $MAX_RETRIES)"

# Check if running on Raspberry Pi
if [ ! -d /sys/class/gpio ]; then
    echo "⚠️  GPIO not available (not running on Raspberry Pi?)"
    echo "   Creating dummy GPIO check result"
    echo "GPIO_${GPIO_PIN}=UNKNOWN" > gpio_check_result.txt
    exit 0
fi

# Retry logic
RETRY_COUNT=0
SUCCESS=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ $SUCCESS -eq 0 ]; do
    if [ $RETRY_COUNT -gt 0 ]; then
        echo "🔄 Retry attempt $RETRY_COUNT/$((MAX_RETRIES-1))..."
        sleep 0.5
    fi
    
    # Export GPIO pin
    if [ ! -d "/sys/class/gpio/gpio${GPIO_PIN}" ]; then
        echo "$GPIO_PIN" > /sys/class/gpio/export 2>/dev/null || {
            echo "⚠️  Failed to export GPIO $GPIO_PIN (may already be exported)"
        }
        sleep 0.2
    fi
    
    # Set as input
    echo "in" > "/sys/class/gpio/gpio${GPIO_PIN}/direction" 2>/dev/null || {
        echo "⚠️  Failed to set GPIO $GPIO_PIN direction, retrying..."
        RETRY_COUNT=$((RETRY_COUNT + 1))
        continue
    }
    
    # Read GPIO value with multiple samples for stability
    SAMPLE_COUNT=3
    SAMPLE_VALUES=()
    for i in $(seq 1 $SAMPLE_COUNT); do
        VALUE=$(cat "/sys/class/gpio/gpio${GPIO_PIN}/value" 2>/dev/null || echo "0")
        SAMPLE_VALUES+=("$VALUE")
        sleep 0.1
    done
    
    # Use most common value (simple majority)
    GPIO_VALUE=$(printf '%s\n' "${SAMPLE_VALUES[@]}" | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
    
    echo "📊 GPIO $GPIO_PIN state: $GPIO_VALUE (expected: $EXPECTED_STATE, samples: ${SAMPLE_VALUES[*]})"
    
    # Compare with expected state
    if [ "$GPIO_VALUE" = "$EXPECTED_STATE" ]; then
        SUCCESS=1
        echo "✅ GPIO check PASSED"
        echo "GPIO_${GPIO_PIN}=PASS" > gpio_check_result.txt
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "⚠️  GPIO check failed (got $GPIO_VALUE, expected $EXPECTED_STATE), retrying..."
        fi
    fi
done

if [ $SUCCESS -eq 0 ]; then
    echo "❌ GPIO check FAILED after $MAX_RETRIES attempts (got $GPIO_VALUE, expected $EXPECTED_STATE)"
    echo "GPIO_${GPIO_PIN}=FAIL" > gpio_check_result.txt
    exit 1
fi

exit 0
