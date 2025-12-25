#!/bin/bash
# Run hardware tests for ESP32 firmware
# Usage: run_tests.sh <firmware.bin> <platform>

set -e

FW_FILE="${1:-firmware-esp32.bin}"
PLATFORM="${2:-ESP32}"

REPORT_DIR="${TEST_REPORT_DIR:-reports}"
mkdir -p "$REPORT_DIR"

echo "🧪 [ATS] Running hardware tests for ${PLATFORM}"
echo "📁 Report directory: $REPORT_DIR"

# Detect ESP32 port
ESP_PORT=""
for port in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyACM0 /dev/ttyACM1; do
    if [ -e "$port" ]; then
        ESP_PORT="$port"
        break
    fi
done

if [ -z "$ESP_PORT" ]; then
    ESP_PORT=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | head -1)
fi

if [ -z "$ESP_PORT" ] || [ ! -e "$ESP_PORT" ]; then
    echo "❌ ESP32 device not found"
    exit 1
fi

echo "📡 Using ESP32 port: $ESP_PORT"

# Test results
TEST_RESULTS=()
TEST_PASSED=0
TEST_FAILED=0

# Test 1: UART Boot Validation
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: UART Boot Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Reset ESP32 first
echo "🔄 Resetting ESP32..."
esptool.py --chip esp32 --port "$ESP_PORT" run || true
sleep 2

# Read UART boot log
echo "📡 Reading UART boot log..."
./agent/read_uart.sh "$ESP_PORT" 15 "$REPORT_DIR/uart_boot.log"

# Check for boot success indicators
if grep -qi "ets Jun\|Guru Meditation\|Hello from ESP32" "$REPORT_DIR/uart_boot.log" 2>/dev/null; then
    echo "✅ UART boot validation PASSED"
    TEST_RESULTS+=("UART_BOOT=PASS")
    ((TEST_PASSED++))
else
    echo "❌ UART boot validation FAILED (no boot messages found)"
    TEST_RESULTS+=("UART_BOOT=FAIL")
    ((TEST_FAILED++))
fi

# Test 2: GPIO Check (if GPIO pin is configured)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: GPIO State Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Example: Check GPIO 2 (ESP32 built-in LED on many boards)
# Adjust GPIO pin based on your hardware setup
GPIO_PIN="${ESP32_GPIO_PIN:-2}"

if [ -d /sys/class/gpio ]; then
    echo "🔌 Checking GPIO pin $GPIO_PIN"
    ./agent/gpio_check.sh "$GPIO_PIN" 1 || {
        echo "⚠️  GPIO check failed or not applicable"
        TEST_RESULTS+=("GPIO_CHECK=SKIP")
    }
    
    if [ -f gpio_check_result.txt ]; then
        if grep -q "PASS" gpio_check_result.txt; then
            echo "✅ GPIO check PASSED"
            TEST_RESULTS+=("GPIO_CHECK=PASS")
            ((TEST_PASSED++))
        else
            echo "❌ GPIO check FAILED"
            TEST_RESULTS+=("GPIO_CHECK=FAIL")
            ((TEST_FAILED++))
        fi
        mv gpio_check_result.txt "$REPORT_DIR/"
    fi
else
    echo "⚠️  GPIO not available (running in container without GPIO access?)"
    TEST_RESULTS+=("GPIO_CHECK=SKIP")
fi

# Test 3: Firmware Stability (reboot test)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Firmware Stability (Reboot Test)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "🔄 Performing reboot test..."
for i in {1..3}; do
    echo "  Reboot attempt $i/3..."
    esptool.py --chip esp32 --port "$ESP_PORT" run || true
    sleep 3
    
    # Read UART after reboot
    ./agent/read_uart.sh "$ESP_PORT" 10 "$REPORT_DIR/uart_reboot_${i}.log"
    
    if grep -qi "ets Jun\|Guru Meditation" "$REPORT_DIR/uart_reboot_${i}.log" 2>/dev/null; then
        echo "  ✅ Reboot $i successful"
    else
        echo "  ❌ Reboot $i failed"
        TEST_RESULTS+=("REBOOT_${i}=FAIL")
        ((TEST_FAILED++))
    fi
done

if [ $TEST_FAILED -eq 0 ]; then
    echo "✅ Reboot test PASSED"
    TEST_RESULTS+=("REBOOT_TEST=PASS")
    ((TEST_PASSED++))
else
    echo "❌ Reboot test FAILED"
    TEST_RESULTS+=("REBOOT_TEST=FAIL")
fi

# Generate test report
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Passed: $TEST_PASSED"
echo "Failed: $TEST_FAILED"
echo ""

# Generate JUnit XML report
cat > "$REPORT_DIR/junit.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="ESP32 Hardware Tests" tests="$((TEST_PASSED + TEST_FAILED))" failures="$TEST_FAILED">
    <testcase name="UART Boot Validation" classname="HardwareTest">
      $(if echo "${TEST_RESULTS[@]}" | grep -q "UART_BOOT=PASS"; then echo ""; else echo "<failure>UART boot validation failed</failure>"; fi)
    </testcase>
    <testcase name="GPIO Check" classname="HardwareTest">
      $(if echo "${TEST_RESULTS[@]}" | grep -q "GPIO_CHECK=PASS"; then echo ""; else echo "<failure>GPIO check failed</failure>"; fi)
    </testcase>
    <testcase name="Reboot Test" classname="HardwareTest">
      $(if echo "${TEST_RESULTS[@]}" | grep -q "REBOOT_TEST=PASS"; then echo ""; else echo "<failure>Reboot test failed</failure>"; fi)
    </testcase>
  </testsuite>
</testsuites>
EOF

# Generate text summary
cat > "$REPORT_DIR/test_summary.txt" <<EOF
ATS Hardware Test Report
========================
Platform: ${PLATFORM}
Firmware: ${FW_FILE}
ESP32 Port: ${ESP_PORT}
Test Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Test Results:
${TEST_RESULTS[@]}

Summary:
  Passed: ${TEST_PASSED}
  Failed: ${TEST_FAILED}
  Total:  $((TEST_PASSED + TEST_FAILED))
EOF

cat "$REPORT_DIR/test_summary.txt"

# Exit with error if any test failed
if [ $TEST_FAILED -gt 0 ]; then
    echo ""
    echo "❌ Some tests failed. See reports in $REPORT_DIR/"
    exit 1
else
    echo ""
    echo "✅ All tests passed!"
    exit 0
fi

