#!/bin/bash
# Read UART logs from ESP32 with retry logic
# Usage: read_uart.sh <port> <timeout_seconds> <output_file> [max_retries]

set -e

ESP_PORT="${1:-/dev/ttyUSB0}"
TIMEOUT="${2:-10}"
OUTPUT_FILE="${3:-uart.log}"
MAX_RETRIES="${4:-3}"

if [ ! -e "$ESP_PORT" ]; then
    echo "❌ UART port not found: $ESP_PORT"
    exit 1
fi

echo "📡 [ATS] Reading UART from $ESP_PORT (timeout: ${TIMEOUT}s, max retries: ${MAX_RETRIES})"

# Configure serial port
stty -F "$ESP_PORT" 115200 cs8 -cstopb -parenb 2>/dev/null || {
    echo "⚠️  Warning: Could not configure serial port, continuing anyway..."
}

# Retry logic
RETRY_COUNT=0
SUCCESS=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ $SUCCESS -eq 0 ]; do
    if [ $RETRY_COUNT -gt 0 ]; then
        echo "🔄 Retry attempt $RETRY_COUNT/$((MAX_RETRIES-1))..."
        sleep 1
    fi
    
    # Clear any stale data
    timeout 0.5 cat "$ESP_PORT" > /dev/null 2>&1 || true
    
    # Read UART with timeout
    if timeout "$TIMEOUT" cat "$ESP_PORT" > "$OUTPUT_FILE" 2>&1; then
        EXIT_CODE=0
    else
        EXIT_CODE=$?
    fi
    
    # Check if we got data (timeout is expected, but we want some content)
    if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
        LINE_COUNT=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
        if [ "$LINE_COUNT" -gt 0 ]; then
            SUCCESS=1
            echo "✅ UART read successful (${LINE_COUNT} lines)"
        elif [ $EXIT_CODE -eq 124 ]; then
            # Timeout is OK if we got some data
            SUCCESS=1
            echo "✅ UART read completed (timeout reached, got some data)"
        fi
    fi
    
    if [ $SUCCESS -eq 0 ]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $EXIT_CODE -eq 124 ]; then
            echo "⚠️  UART read timeout (no data received), retrying..."
        else
            echo "⚠️  UART read failed (exit code: $EXIT_CODE), retrying..."
        fi
    fi
done

if [ $SUCCESS -eq 0 ]; then
    echo "❌ UART read failed after $MAX_RETRIES attempts"
    exit 1
fi

if [ -f "$OUTPUT_FILE" ]; then
    echo "📄 UART log saved to: $OUTPUT_FILE"
    echo "📊 Log size: $(wc -l < "$OUTPUT_FILE") lines"
    if [ -s "$OUTPUT_FILE" ]; then
        echo "--- First 20 lines ---"
        head -20 "$OUTPUT_FILE"
        echo "--- Last 10 lines ---"
        tail -10 "$OUTPUT_FILE"
    fi
fi
