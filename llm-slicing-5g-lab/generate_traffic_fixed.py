#!/usr/bin/env python3
"""
5G Network Traffic Generator - Fixed Version
Based on original DLI_Lab_Setup.ipynb implementation

This version uses network namespaces for multiple UEs and runs REAL iperf3
traffic for both UE1 and UE3 - NO SIMULATION!

Architecture:
- UE1: Network namespace "ue1" with IP 12.1.1.2
- UE3: Network namespace "ue3" with IP 12.1.1.130
- Both run real iperf3 clients measuring actual packet loss
"""

import os
import re
import subprocess
import threading
import time
import logging
from datetime import datetime
from typing import Pattern, Dict, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s: %(message)s'
)
logger = logging.getLogger(__name__)

# ============================================================================
# Database Configuration
# ============================================================================

# Configure Kinetica (optional - will continue without it)
kdbc = None
kdbc_table = None
FIXED_TABLE_NAME = None

try:
    from gpudb import GPUdb, GPUdbTable
    from gpudb import GPUdbColumnProperty as cp
    from gpudb import GPUdbRecordColumn as rc

    kdbc_options = GPUdb.Options()
    kdbc_options.username = os.getenv("KINETICA_USERNAME", "admin")
    kdbc_options.password = os.getenv("KINETICA_PASSWORD", "Admin123!")
    kdbc_options.disable_auto_discovery = True

    kdbc = GPUdb(
        host=os.getenv("KINETICA_HOST", "localhost:9191"),
        options=kdbc_options
    )

    FIXED_TABLE_NAME = "nvidia_gtc_dli_2025.iperf3_logs"
    logger.info("✅ Connected to Kinetica")

    # Create schema if needed
    target_schema = "nvidia_gtc_dli_2025"
    try:
        kdbc.create_schema(schema_name=target_schema)
        logger.info(f"✅ Created schema: {target_schema}")
    except Exception as e:
        if "already exists" in str(e).lower():
            logger.info(f"✅ Schema exists: {target_schema}")
        else:
            logger.warning(f"⚠️  Schema creation warning: {e}")

    # Create or get table reference
    if not kdbc.has_table(table_name=FIXED_TABLE_NAME)['table_exists']:
        logger.info(f"Creating Kinetica table: {FIXED_TABLE_NAME}")
        schema = [
            ["id",               rc._ColumnType.STRING, cp.UUID,     cp.PRIMARY_KEY, cp.INIT_WITH_UUID],
            ["ue",               rc._ColumnType.STRING, cp.CHAR8,    cp.DICT],
            ["timestamp",        rc._ColumnType.STRING, cp.DATETIME, cp.INIT_WITH_NOW],
            ["stream",           rc._ColumnType.INT,    cp.INT8,     cp.DICT],
            ["interval_start",   rc._ColumnType.FLOAT],
            ["interval_end",     rc._ColumnType.FLOAT],
            ["duration",         rc._ColumnType.FLOAT],
            ["data_transferred", rc._ColumnType.FLOAT],
            ["bitrate",          rc._ColumnType.FLOAT],
            ["jitter",           rc._ColumnType.FLOAT],
            ["lost_packets",     rc._ColumnType.INT],
            ["total_packets",    rc._ColumnType.INT],
            ["loss_percentage",  rc._ColumnType.FLOAT]
        ]
        kdbc_table = GPUdbTable(_type=schema, name=FIXED_TABLE_NAME, db=kdbc)
        logger.info(f"✅ Created Kinetica table: {FIXED_TABLE_NAME}")
    else:
        kdbc_table = GPUdbTable(name=FIXED_TABLE_NAME, db=kdbc)
        logger.info(f"✅ Using existing Kinetica table: {FIXED_TABLE_NAME}")

except Exception as e:
    logger.warning(f"⚠️  Kinetica not available: {e}")
    logger.info("   Continuing without Kinetica - data will only be logged")

# Initialize InfluxDB (optional)
influx_write_api = None
try:
    from influxdb_client import InfluxDBClient, Point
    from influxdb_client.client.write_api import SYNCHRONOUS

    influx_client = InfluxDBClient(
        url=os.getenv("INFLUXDB_URL", "http://localhost:9001"),
        token=os.getenv("INFLUXDB_TOKEN", "5g-lab-token"),
        org=os.getenv("INFLUXDB_ORG", "5g-lab")
    )
    influx_write_api = influx_client.write_api(write_options=SYNCHRONOUS)
    logger.info("✅ Connected to InfluxDB")
except Exception as e:
    logger.warning(f"⚠️  InfluxDB not available: {e}")
    logger.info("   Continuing without InfluxDB")

# ============================================================================
# Helper Functions
# ============================================================================

def write_to_influxdb(ue_name: str, record: Dict) -> None:
    """Write metrics to InfluxDB"""
    if influx_write_api is None:
        return

    try:
        point = Point("network_metrics") \
            .tag("ue", ue_name) \
            .field("bitrate", float(record["bitrate"])) \
            .field("jitter", float(record["jitter"])) \
            .field("lost_packets", int(record["lost_packets"])) \
            .field("total_packets", int(record["total_packets"])) \
            .field("loss_percentage", float(record["loss_percentage"]))

        influx_write_api.write(
            bucket=os.getenv("INFLUXDB_BUCKET", "5g-metrics"),
            record=point
        )
    except Exception as e:
        logger.error(f"❌ InfluxDB write error: {e}")

# ============================================================================
# Traffic Generation Functions
# ============================================================================

# Precompiled regex pattern to parse iperf3 output
# Example line: "[  5]   0.00-1.00   sec  14.2 MBytes  119 Mbits/sec  0.845 ms  87/10123 (0.86%)"
filter_regex = (
    r'^\[ *([0-9]+)\] +([0-9]+\.[0-9]+)-([0-9]+\.[0-9]+) +sec +'
    r'([0-9\.]+) +MBytes +([0-9\.]+) +Mbits/sec +([0-9\.]+) +ms +'
    r'([0-9]+)/([0-9]+) +\(([0-9\.]+)%\)$'
)
pattern: Pattern[str] = re.compile(filter_regex)


def iperf_runner(
    namespace: str,
    ue_name: str,
    bind_host: str,
    server_host: str,
    udp_port: int,
    bandwidth: str,
    test_length_secs: int,
    log_file: str
) -> None:
    """
    Run iperf3 in a network namespace and parse real-time output.

    This function runs REAL iperf3 traffic - no simulation!

    Args:
        namespace: Network namespace name (e.g., "ue1", "ue3")
        ue_name: UE identifier for logging (e.g., "UE1", "UE3")
        bind_host: IP address to bind to (e.g., "12.1.1.2")
        server_host: iperf3 server IP (e.g., "192.168.70.135")
        udp_port: Server port (e.g., 5201, 5202)
        bandwidth: Target bandwidth (e.g., "30M", "120M")
        test_length_secs: Test duration in seconds
        log_file: Path to log file for this UE
    """
    try:
        # Build iperf3 command
        iperf_cmd = (
            f"stdbuf -oL iperf3 "
            f"-B {bind_host} "
            f"-c {server_host} "
            f"-p {udp_port} "
            f"-R -u "
            f"-b {bandwidth} "
            f"-t {test_length_secs}"
        )

        # Execute in network namespace
        cmd = ["sudo", "ip", "netns", "exec", namespace, "bash", "-c", iperf_cmd]

        logger.info(f"🚀 [{ue_name}] Starting iperf3 test in namespace '{namespace}'")
        logger.info(f"   Bandwidth: {bandwidth}, Duration: {test_length_secs}s")

        # Start subprocess
        with subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1
        ) as proc:

            records_inserted = 0

            for line in proc.stdout:
                line = line.strip()
                match = pattern.match(line)

                if match:
                    # Parse real iperf3 output - NO SIMULATION!
                    record = {
                        "ue": ue_name,
                        "stream": int(match.group(1)),
                        "interval_start": float(match.group(2)),
                        "interval_end": float(match.group(3)),
                        "data_transferred": float(match.group(4)),
                        "bitrate": float(match.group(5)),
                        "jitter": float(match.group(6)),
                        "lost_packets": int(match.group(7)),      # ✅ Real from network
                        "total_packets": int(match.group(8)),     # ✅ Real from network
                        "loss_percentage": float(match.group(9)), # ✅ Real from network
                        "duration": float(match.group(3)) - float(match.group(2))
                    }

                    # Insert into Kinetica
                    if kdbc is not None and kdbc_table is not None:
                        try:
                            kdbc_table.insert_records(record)
                            kdbc_table.flush_data_to_server()
                            records_inserted += 1

                            # Log progress every 10 records
                            if records_inserted % 10 == 0:
                                logger.info(f"   📊 [{ue_name}] {records_inserted} records inserted...")
                        except Exception as e:
                            if records_inserted == 0:
                                logger.error(f"❌ [{ue_name}] Kinetica insert failed: {e}")

                    # Write to InfluxDB
                    write_to_influxdb(ue_name, record)

                    # Write to log file
                    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    with open(log_file, "a") as f:
                        f.write(f"[{ue_name}] [{timestamp}] {line}\n")

            proc.wait()
            logger.info(f"✅ [{ue_name}] Test completed - {records_inserted} records inserted")

    except Exception as e:
        logger.error(f"❌ Error running {ue_name}: {e}")


# ============================================================================
# Main Execution
# ============================================================================

def main():
    """Main traffic generation loop"""

    logger.info("=" * 70)
    logger.info("🚀 5G TRAFFIC GENERATOR - FIXED VERSION (Real iperf3 for Both UEs)")
    logger.info("=" * 70)
    logger.info("")
    logger.info("📝 Architecture:")
    logger.info("   - UE1: Network namespace 'ue1' (IP: 12.1.1.2)")
    logger.info("   - UE3: Network namespace 'ue3' (IP: 12.1.1.130)")
    logger.info("   - Both UEs: REAL iperf3 traffic with actual packet measurements")
    logger.info("   - NO SIMULATION - All data is real network traffic!")
    logger.info("")

    # Fixed IP addresses for UEs in network namespaces
    bind_host_ue1 = "12.1.1.2"
    bind_host_ue3 = "12.1.1.130"
    server_host = "192.168.70.135"
    udp_port_ue1 = 5201
    udp_port_ue3 = 5202

    # Initial bandwidth settings (will alternate)
    bandwidth_ue1 = "30M"
    bandwidth_ue3 = "120M"  # Opposite of UE1 to demonstrate slicing
    test_length_secs = 100  # Each test runs for 100 seconds

    # Number of iterations
    test_iterations = 25
    current_iteration = 0

    logger.info("🔄 Bandwidth alternation pattern:")
    logger.info("   - UE1 and UE3 will alternate between 30M and 120M")
    logger.info("   - Pattern demonstrates dynamic bandwidth slicing")
    logger.info(f"   - Running {test_iterations} iterations")
    logger.info("")

    # Verify network namespaces exist
    logger.info("🔍 Verifying network namespaces...")
    try:
        result = subprocess.run(
            ["sudo", "ip", "netns", "list"],
            capture_output=True,
            text=True,
            timeout=5
        )
        namespaces = result.stdout.strip()

        if "ue1" not in namespaces:
            logger.error("❌ Network namespace 'ue1' not found!")
            logger.error("   Please run: sudo ./multi_ue.sh -c1")
            return

        if "ue3" not in namespaces:
            logger.error("❌ Network namespace 'ue3' not found!")
            logger.error("   Please run: sudo ./multi_ue.sh -c3")
            return

        logger.info("✅ Network namespaces 'ue1' and 'ue3' exist")
        logger.info("")
    except Exception as e:
        logger.error(f"❌ Failed to verify namespaces: {e}")
        return

    # Create logs directory
    os.makedirs("logs", exist_ok=True)

    # Main traffic generation loop
    while current_iteration < test_iterations:
        logger.info("=" * 70)
        logger.info(f"🔄 ITERATION {current_iteration + 1}/{test_iterations}")
        logger.info(f"   UE1: {bandwidth_ue1} | UE3: {bandwidth_ue3}")
        logger.info("=" * 70)

        current_iteration += 1

        # Create threads for both UEs
        # Thread 1: REAL iperf3 for UE1
        t1 = threading.Thread(
            target=iperf_runner,
            args=(
                "ue1",                 # Network namespace
                "UE1",                 # UE name
                bind_host_ue1,         # 12.1.1.2
                server_host,           # 192.168.70.135
                udp_port_ue1,          # 5201
                bandwidth_ue1,         # Alternates 30M/120M
                test_length_secs,      # 100 seconds
                "logs/UE1_iperfc.log"  # Log file
            ),
            daemon=True
        )

        # Thread 2: REAL iperf3 for UE3 (NOT SIMULATED!)
        t2 = threading.Thread(
            target=iperf_runner,
            args=(
                "ue3",                 # Network namespace
                "UE3",                 # UE name
                bind_host_ue3,         # 12.1.1.130
                server_host,           # 192.168.70.135
                udp_port_ue3,          # 5202
                bandwidth_ue3,         # Alternates 120M/30M (opposite of UE1)
                test_length_secs,      # 100 seconds
                "logs/UE2_iperfc.log"  # Log file
            ),
            daemon=True
        )

        # Start both threads
        t1.start()
        t2.start()

        # Wait for both to complete
        t1.join()
        t2.join()

        logger.info("")
        logger.info(f"✅ Iteration {current_iteration} completed")
        logger.info("")

        # Alternate bandwidth for next iteration
        bandwidth_ue1 = "120M" if bandwidth_ue1 == "30M" else "30M"
        bandwidth_ue3 = "120M" if bandwidth_ue3 == "30M" else "30M"

    logger.info("=" * 70)
    logger.info("🎉 All iterations completed!")
    logger.info("=" * 70)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        logger.info("")
        logger.info("⚠️  Interrupted by user")
    except Exception as e:
        logger.error(f"❌ Fatal error: {e}")
        raise
