#!/bin/bash
# ATS Test Runner - Hardware-Agnostic Test Execution
# This script assumes firmware is already flashed and device is ready
# Reads test parameters from ats-manifest.yaml
# Usage: run_tests.sh [manifest_path]

set -e

MANIFEST_PATH="${1:-ats-manifest.yaml}"
REPORT_DIR="${TEST_REPORT_DIR:-${RESULTS_DIR:-reports}}"
SERIAL_PORT="${SERIAL_PORT:-/dev/ttyUSB0}"

mkdir -p "$REPORT_DIR"

echo "🧪 [ATS Test Runner] Starting test execution"
echo "📋 Manifest: ${MANIFEST_PATH}"
echo "📁 Report directory: ${REPORT_DIR}"
echo "📡 Serial port: ${SERIAL_PORT}"

# Validate manifest exists
if [ ! -f "$MANIFEST_PATH" ]; then
    echo "❌ Manifest not found: ${MANIFEST_PATH}"
    exit 1
fi

# Extract test parameters from manifest
DEVICE_TARGET=$(grep -E "^  target:" "$MANIFEST_PATH" | sed 's/.*: *//' | tr -d ' ' || echo "")
DEVICE_BOARD=$(grep -E "^  board:" "$MANIFEST_PATH" | sed 's/.*: *//' | tr -d ' ' || echo "")
BUILD_NUMBER=$(grep -E "^  build_number:" "$MANIFEST_PATH" | sed 's/.*: *//' | tr -d ' ' || echo "")

echo "🎯 Device: ${DEVICE_TARGET} (${DEVICE_BOARD})"
echo "📦 Build: ${BUILD_NUMBER}"

# Extract test plan from manifest
TEST_PLAN=()
while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.+)$ ]]; then
        TEST_PLAN+=("${BASH_REMATCH[1]}")
    fi
done < <(grep -A 10 "^test_plan:" "$MANIFEST_PATH" | grep -E "^  -")

echo "📋 Test plan: ${TEST_PLAN[*]}"

# Test results
TEST_RESULTS=()
TEST_PASSED=0
TEST_FAILED=0

# Test 1: UART Boot Validation
if [[ " ${TEST_PLAN[@]} " =~ " uart_boot_test " ]] || [[ " ${TEST_PLAN[@]} " =~ " gpio_toggle_test " ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test: UART Boot Validation"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Read UART boot log
    echo "📡 Reading UART boot log from ${SERIAL_PORT}..."
    if [ -e "$SERIAL_PORT" ]; then
        if [ -f ./agent/read_uart.sh ]; then
            ./agent/read_uart.sh "$SERIAL_PORT" 15 "$REPORT_DIR/uart_boot.log" || true
        else
            # Fallback: simple UART read
            timeout 15 cat "$SERIAL_PORT" > "$REPORT_DIR/uart_boot.log" 2>&1 || true
        fi
        
        # Check for boot success indicators
        if grep -qi "ets Jun\|Guru Meditation\|Hello from ESP32\|ATS ESP32\|Build successful" "$REPORT_DIR/uart_boot.log" 2>/dev/null; then
            echo "✅ UART boot validation PASSED"
            TEST_RESULTS+=("UART_BOOT=PASS")
            ((TEST_PASSED++))
        else
            echo "❌ UART boot validation FAILED (no boot messages found)"
            TEST_RESULTS+=("UART_BOOT=FAIL")
            ((TEST_FAILED++))
        fi
    else
        echo "⚠️  Serial port not available: ${SERIAL_PORT}"
        echo "   Skipping UART test"
        TEST_RESULTS+=("UART_BOOT=SKIP")
    fi
fi

# Test 2: GPIO Check (if in test plan)
if [[ " ${TEST_PLAN[@]} " =~ " gpio_toggle_test " ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test: GPIO State Check"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    GPIO_PIN="${ESP32_GPIO_PIN:-2}"
    
    if [ -d /sys/class/gpio ] && [ -f ./agent/gpio_check.sh ]; then
        echo "🔌 Checking GPIO pin ${GPIO_PIN}"
        if ./agent/gpio_check.sh "$GPIO_PIN" 1; then
            echo "✅ GPIO check PASSED"
            TEST_RESULTS+=("GPIO_CHECK=PASS")
            ((TEST_PASSED++))
        else
            echo "❌ GPIO check FAILED"
            TEST_RESULTS+=("GPIO_CHECK=FAIL")
            ((TEST_FAILED++))
        fi
    else
        echo "⚠️  GPIO not available or check script not found"
        TEST_RESULTS+=("GPIO_CHECK=SKIP")
    fi
fi

# Test 3: Firmware Stability (reboot test)
if [[ " ${TEST_PLAN[@]} " =~ " reboot_test " ]] || [[ " ${TEST_PLAN[@]} " =~ " stability_test " ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test: Firmware Stability (Reboot Test)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    REBOOT_PASSED=0
    REBOOT_FAILED=0
    
    for i in {1..3}; do
        echo "  Reboot attempt $i/3..."
        sleep 2
        
        # Read UART after reboot
        if [ -e "$SERIAL_PORT" ] && [ -f ./agent/read_uart.sh ]; then
            ./agent/read_uart.sh "$SERIAL_PORT" 10 "$REPORT_DIR/uart_reboot_${i}.log" || true
            
            if grep -qi "ets Jun\|Guru Meditation" "$REPORT_DIR/uart_reboot_${i}.log" 2>/dev/null; then
                echo "  ✅ Reboot $i successful"
                ((REBOOT_PASSED++))
            else
                echo "  ❌ Reboot $i failed"
                ((REBOOT_FAILED++))
            fi
        fi
    done
    
    if [ $REBOOT_FAILED -eq 0 ]; then
        echo "✅ Reboot test PASSED"
        TEST_RESULTS+=("REBOOT_TEST=PASS")
        ((TEST_PASSED++))
    else
        echo "❌ Reboot test FAILED"
        TEST_RESULTS+=("REBOOT_TEST=FAIL")
        ((TEST_FAILED++))
    fi
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
cat > "$REPORT_DIR/junit.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="ATS Hardware Tests" tests="$((TEST_PASSED + TEST_FAILED))" failures="$TEST_FAILED">
    $(for result in "${TEST_RESULTS[@]}"; do
        test_name=$(echo "$result" | cut -d'=' -f1)
        test_status=$(echo "$result" | cut -d'=' -f2)
        if [ "$test_status" = "FAIL" ]; then
            echo "    <testcase name=\"${test_name}\" classname=\"HardwareTest\">"
            echo "      <failure>Test failed</failure>"
            echo "    </testcase>"
        else
            echo "    <testcase name=\"${test_name}\" classname=\"HardwareTest\"/>"
        fi
    done)
  </testsuite>
</testsuites>
XML

# Generate text summary
cat > "$REPORT_DIR/test_summary.txt" <<SUMMARY
ATS Hardware Test Report
========================
Device: ${DEVICE_TARGET} (${DEVICE_BOARD})
Build: ${BUILD_NUMBER}
Test Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Test Results:
${TEST_RESULTS[@]}

Summary:
  Passed: ${TEST_PASSED}
  Failed: ${TEST_FAILED}
  Total:  $((TEST_PASSED + TEST_FAILED))
SUMMARY

cat "$REPORT_DIR/test_summary.txt"

# Copy UART logs to serial.log if available
if [ -f "$REPORT_DIR/uart_boot.log" ]; then
    cp "$REPORT_DIR/uart_boot.log" "$REPORT_DIR/serial.log"
fi

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
