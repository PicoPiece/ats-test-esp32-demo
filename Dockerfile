# Dockerfile for ATS Test Runner on Raspberry Pi
# This container runs on ATS nodes (Raspberry Pi) to execute hardware tests

FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    wget \
    curl \
    build-essential \
    python3-pip \
    python3-dev \
    pyserial \
    minicom \
    screen \
    usbutils \
    udev \
    && rm -rf /var/lib/apt/lists/*

# Install esptool for ESP32 flashing
RUN pip3 install --no-cache-dir \
    esptool \
    pyserial \
    RPi.GPIO \
    pytest \
    pytest-html

# Create working directory
WORKDIR /app

# Create directories for scripts and reports
RUN mkdir -p /app/agent /app/reports

# Copy agent scripts (will be mounted or copied at runtime)
# The scripts will be available from the checked-out repo

# Set up udev rules for USB devices (ESP32)
RUN echo 'SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", MODE="0666"' > /etc/udev/rules.d/99-esp32.rules && \
    echo 'SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", MODE="0666"' >> /etc/udev/rules.d/99-esp32.rules && \
    echo 'SUBSYSTEM=="tty", ATTRS{idVendor}=="303a", MODE="0666"' >> /etc/udev/rules.d/99-esp32.rules

# Grant permissions for GPIO access (Raspberry Pi)
# Note: Container needs to run with --privileged or specific device mounts
# GPIO access requires /dev/gpiomem or /sys/class/gpio

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV ESPTOOL_PORT=/dev/ttyUSB0
ENV ESPTOOL_BAUD=460800

# Default command (will be overridden by Jenkins pipeline)
CMD ["/bin/bash"]

