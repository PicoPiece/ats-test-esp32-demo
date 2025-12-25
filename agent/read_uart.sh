#!/bin/bash
# Read UART logs from ESP32
# Usage: read_uart.sh <port> <timeout_seconds> <output_file>

set -e

ESP_PORT="${1:-/dev/ttyUSB0}"
TIMEOUT="${2:-10}"
OUTPUT_FILE="${3:-uart.log}"

if [ ! -e "$ESP_PORT" ]; then
    echo "❌ UART port not found: $ESP_PORT"
    exit 1
fi

echo "📡 [ATS] Reading UART from $ESP_PORT (timeout: ${TIMEOUT}s)"

# Configure serial port
stty -F "$ESP_PORT" 115200 cs8 -cstopb -parenb

# Read UART with timeout
timeout "$TIMEOUT" cat "$ESP_PORT" > "$OUTPUT_FILE" 2>&1 || {
    # timeout command returns 124 on timeout (which is expected)
    if [ $? -eq 124 ]; then
        echo "✅ UART read completed (timeout reached)"
    else
        echo "⚠️  UART read ended with error"
    fi
}

if [ -f "$OUTPUT_FILE" ]; then
    echo "📄 UART log saved to: $OUTPUT_FILE"
    echo "📊 Log size: $(wc -l < "$OUTPUT_FILE") lines"
    echo "--- First 20 lines ---"
    head -20 "$OUTPUT_FILE"
    echo "--- Last 10 lines ---"
    tail -10 "$OUTPUT_FILE"
fi

