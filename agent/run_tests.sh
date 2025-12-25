#!/bin/bash
# Run hardware tests for ESP32 firmware
# Usage: run_tests.sh <firmware.bin> <platform>

set -e

FW_FILE="${1:-firmware-esp32.bin}"
PLATFORM="${2:-ESP32}"

REPORT_DIR="${TEST_REPORT_DIR:-reports}"
mkdir -p "$REPORT_DIR"

# Start metrics exporter in background
METRICS_PORT="${METRICS_PORT:-8080}"
export METRICS_FILE="$REPORT_DIR/metrics.json"
if [ -f ./agent/metrics_exporter.py ]; then
    echo "📊 Starting metrics exporter on port $METRICS_PORT..."
    python3 ./agent/metrics_exporter.py &
    METRICS_PID=$!
    sleep 1  # Give metrics server time to start
    # Update metrics: test in progress
    python3 -c "
from agent.metrics_exporter import update_metrics
update_metrics(in_progress=1)
" 2>/dev/null || true
else
    echo "⚠️  Metrics exporter not found, continuing without metrics"
    METRICS_PID=""
fi

# Track test start time
TEST_START_TIME=$(date +%s)

echo "🧪 [ATS] Running hardware tests for ${PLATFORM}"
echo "📁 Report directory: $REPORT_DIR"

# Extract firmware version from manifest if available
FW_VERSION=""
if [ -f ats-manifest.yaml ]; then
    FW_VERSION=$(grep -E "commit:|build_number:" ats-manifest.yaml | head -1 | sed 's/.*: *//' | tr -d ' ' || echo "")
fi

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
    echo "   Checked ports: /dev/ttyUSB0, /dev/ttyUSB1, /dev/ttyACM0, /dev/ttyACM1"
    echo "   Available USB devices:"
    ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo "   None found"
    echo "   Troubleshooting:"
    echo "   - Ensure ESP32 is connected via USB"
    echo "   - Check USB cable and port"
    echo "   - Verify device permissions (user should be in dialout group)"
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

# Read UART boot log with retry
echo "📡 Reading UART boot log..."
if ./agent/read_uart.sh "$ESP_PORT" 15 "$REPORT_DIR/uart_boot.log" 3; then
    # Check for boot success indicators
    if grep -qi "ets Jun\|Guru Meditation\|Hello from ESP32\|ATS ESP32\|Build successful" "$REPORT_DIR/uart_boot.log" 2>/dev/null; then
        echo "✅ UART boot validation PASSED"
        TEST_RESULTS+=("UART_BOOT=PASS")
        ((TEST_PASSED++))
    else
        echo "❌ UART boot validation FAILED (no boot messages found)"
        echo "   Last 20 lines of UART log:"
        tail -20 "$REPORT_DIR/uart_boot.log" 2>/dev/null || echo "   (log file empty or not readable)"
        TEST_RESULTS+=("UART_BOOT=FAIL")
        ((TEST_FAILED++))
    fi
else
    echo "❌ UART boot validation FAILED (could not read UART)"
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
    echo "🔌 Checking GPIO pin $GPIO_PIN (with retry logic)"
    if ./agent/gpio_check.sh "$GPIO_PIN" 1 3; then
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
        echo "❌ GPIO check FAILED (retries exhausted)"
        TEST_RESULTS+=("GPIO_CHECK=FAIL")
        ((TEST_FAILED++))
        [ -f gpio_check_result.txt ] && mv gpio_check_result.txt "$REPORT_DIR/" || true
    fi
else
    echo "⚠️  GPIO not available (running in container without GPIO access?)"
    echo "   Ensure container has access to /sys/class/gpio and /dev/gpiomem"
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
    
    # Read UART after reboot with retry
    if ./agent/read_uart.sh "$ESP_PORT" 10 "$REPORT_DIR/uart_reboot_${i}.log" 2; then
        if grep -qi "ets Jun\|Guru Meditation\|Hello from ESP32" "$REPORT_DIR/uart_reboot_${i}.log" 2>/dev/null; then
            echo "  ✅ Reboot $i successful"
        else
            echo "  ❌ Reboot $i failed (no boot messages in log)"
            TEST_RESULTS+=("REBOOT_${i}=FAIL")
            ((TEST_FAILED++))
        fi
    else
        echo "  ❌ Reboot $i failed (could not read UART)"
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

# Test validation and flakiness detection
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Validate test results
VALIDATION_FAILED=0
if [ $TEST_PASSED -eq 0 ] && [ $TEST_FAILED -eq 0 ]; then
    echo "⚠️  WARNING: No tests executed (all tests were skipped)"
    VALIDATION_FAILED=1
fi

# Check for flaky test patterns (tests that pass then fail, or vice versa)
FLAKY_TESTS=()
for result in "${TEST_RESULTS[@]}"; do
    TEST_NAME=$(echo "$result" | cut -d'=' -f1)
    TEST_STATUS=$(echo "$result" | cut -d'=' -f2)
    
    # Check if this test has inconsistent results in reboot tests
    if [[ "$TEST_NAME" == REBOOT_* ]]; then
        REBOOT_NUM=$(echo "$TEST_NAME" | sed 's/REBOOT_//')
        if [ "$TEST_STATUS" = "FAIL" ]; then
            echo "⚠️  Reboot test $REBOOT_NUM failed - potential stability issue"
        fi
    fi
done

# Generate test report
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Passed: $TEST_PASSED"
echo "Failed: $TEST_FAILED"
echo "Total:  $((TEST_PASSED + TEST_FAILED))"

if [ ${#FLAKY_TESTS[@]} -gt 0 ]; then
    echo ""
    echo "⚠️  Potential flaky tests detected: ${FLAKY_TESTS[*]}"
fi

# Calculate success rate
if [ $((TEST_PASSED + TEST_FAILED)) -gt 0 ]; then
    SUCCESS_RATE=$((TEST_PASSED * 100 / (TEST_PASSED + TEST_FAILED)))
    echo "Success Rate: ${SUCCESS_RATE}%"
    
    if [ $SUCCESS_RATE -lt 80 ]; then
        echo "⚠️  WARNING: Low success rate (< 80%) - investigate test reliability"
    fi
fi
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
  Success Rate: ${SUCCESS_RATE}%

Test Results:
$(printf '%s\n' "${TEST_RESULTS[@]}")
EOF

cat "$REPORT_DIR/test_summary.txt"

# Calculate test duration
TEST_END_TIME=$(date +%s)
TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))

# Update metrics with final results
if [ -f ./agent/metrics_exporter.py ]; then
    python3 -c "
from agent.metrics_exporter import update_metrics
import sys
update_metrics(
    passed=$TEST_PASSED,
    failed=$TEST_FAILED,
    duration=$TEST_DURATION,
    fw_version='$FW_VERSION',
    in_progress=0
)
" 2>/dev/null || echo "⚠️  Could not update metrics"
    echo "📊 Metrics updated: Pass=$TEST_PASSED, Fail=$TEST_FAILED, Duration=${TEST_DURATION}s"
fi

# Exit with error if any test failed
if [ $TEST_FAILED -gt 0 ]; then
    echo ""
    echo "❌ Some tests failed. See reports in $REPORT_DIR/"
    # Clean up metrics exporter if running
    [ -n "$METRICS_PID" ] && kill $METRICS_PID 2>/dev/null || true
    exit 1
else
    echo ""
    echo "✅ All tests passed!"
    # Clean up metrics exporter if running
    [ -n "$METRICS_PID" ] && kill $METRICS_PID 2>/dev/null || true
    exit 0
fi

