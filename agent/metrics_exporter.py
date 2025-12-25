#!/usr/bin/env python3
"""
Prometheus Metrics Exporter for ATS Test Framework
Exposes test metrics via HTTP endpoint for Prometheus scraping
"""

import os
import json
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread
from pathlib import Path

# Metrics storage
metrics = {
    'ats_test_pass_total': 0,
    'ats_test_fail_total': 0,
    'ats_test_duration_seconds': 0.0,
    'ats_fw_version': '',
    'ats_test_last_run_timestamp': 0,
    'ats_test_in_progress': 0,
}

METRICS_FILE = os.getenv('METRICS_FILE', '/app/reports/metrics.json')
METRICS_PORT = int(os.getenv('METRICS_PORT', '8080'))


class MetricsHandler(BaseHTTPRequestHandler):
    """HTTP handler for /metrics endpoint"""
    
    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; version=0.0.4')
            self.end_headers()
            
            # Load latest metrics from file if available
            self.load_metrics_from_file()
            
            # Format metrics in Prometheus format
            response = self.format_prometheus_metrics()
            self.wfile.write(response.encode('utf-8'))
        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'healthy'}).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        """Suppress default logging"""
        pass
    
    def load_metrics_from_file(self):
        """Load metrics from JSON file if it exists"""
        global metrics
        try:
            if os.path.exists(METRICS_FILE):
                with open(METRICS_FILE, 'r') as f:
                    file_metrics = json.load(f)
                    metrics.update(file_metrics)
        except Exception as e:
            print(f"Warning: Could not load metrics from file: {e}")
    
    def format_prometheus_metrics(self):
        """Format metrics in Prometheus text format"""
        lines = []
        
        # Test pass counter
        lines.append(f"# HELP ats_test_pass_total Total number of passed tests")
        lines.append(f"# TYPE ats_test_pass_total counter")
        lines.append(f"ats_test_pass_total {metrics['ats_test_pass_total']}")
        
        # Test fail counter
        lines.append(f"# HELP ats_test_fail_total Total number of failed tests")
        lines.append(f"# TYPE ats_test_fail_total counter")
        lines.append(f"ats_test_fail_total {metrics['ats_test_fail_total']}")
        
        # Test duration
        lines.append(f"# HELP ats_test_duration_seconds Duration of last test run in seconds")
        lines.append(f"# TYPE ats_test_duration_seconds gauge")
        lines.append(f"ats_test_duration_seconds {metrics['ats_test_duration_seconds']}")
        
        # Firmware version
        lines.append(f"# HELP ats_fw_version Firmware version under test")
        lines.append(f"# TYPE ats_fw_version gauge")
        fw_version = metrics['ats_fw_version'] or 'unknown'
        # Prometheus labels need to be numeric or quoted strings
        lines.append(f'ats_fw_version{{version="{fw_version}"}} 1')
        
        # Last run timestamp
        lines.append(f"# HELP ats_test_last_run_timestamp Unix timestamp of last test run")
        lines.append(f"# TYPE ats_test_last_run_timestamp gauge")
        lines.append(f"ats_test_last_run_timestamp {metrics['ats_test_last_run_timestamp']}")
        
        # Test in progress
        lines.append(f"# HELP ats_test_in_progress Whether a test is currently running (1) or not (0)")
        lines.append(f"# TYPE ats_test_in_progress gauge")
        lines.append(f"ats_test_in_progress {metrics['ats_test_in_progress']}")
        
        return '\n'.join(lines) + '\n'


def update_metrics(passed=0, failed=0, duration=0.0, fw_version='', in_progress=0):
    """Update metrics and save to file"""
    global metrics
    
    metrics['ats_test_pass_total'] += passed
    metrics['ats_test_fail_total'] += failed
    metrics['ats_test_duration_seconds'] = duration
    if fw_version:
        metrics['ats_fw_version'] = fw_version
    metrics['ats_test_in_progress'] = in_progress
    metrics['ats_test_last_run_timestamp'] = int(time.time())
    
    # Save to file
    try:
        os.makedirs(os.path.dirname(METRICS_FILE), exist_ok=True)
        with open(METRICS_FILE, 'w') as f:
            json.dump(metrics, f, indent=2)
    except Exception as e:
        print(f"Warning: Could not save metrics to file: {e}")


def start_metrics_server(port=METRICS_PORT):
    """Start the metrics HTTP server in a background thread"""
    server = HTTPServer(('0.0.0.0', port), MetricsHandler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    print(f"✅ Metrics exporter started on port {port}")
    print(f"   Metrics endpoint: http://0.0.0.0:{port}/metrics")
    print(f"   Health endpoint: http://0.0.0.0:{port}/health")
    return server, thread


if __name__ == '__main__':
    print("Starting ATS Metrics Exporter...")
    server, thread = start_metrics_server()
    
    # Keep main thread alive
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down metrics exporter...")
        server.shutdown()
