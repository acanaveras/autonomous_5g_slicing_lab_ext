#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Continuous traffic generation script for 5G Lab
# Runs iperf3 clients indefinitely and logs to both Kinetica and InfluxDB

import os
import re
import subprocess
import threading
from datetime import datetime
from typing import Dict, Pattern
import gpudb
from gpudb import GPUdb, GPUdbColumnProperty as cp, GPUdbRecordColumn as rc
import logging
import time

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s: %(message)s'
)
logger = logging.getLogger(__name__)

# Configure Kinetica connection
os.environ["KINETICA_HOST"] = "localhost:9191"
os.environ["KINETICA_USERNAME"] = "admin"
os.environ["KINETICA_PASSWORD"] = "Admin123!"
os.environ["KINETICA_SCHEMA"] = "nvidia_gtc_dli_2025"

kdbc_options = GPUdb.Options()
kdbc_options.username = os.environ.get("KINETICA_USERNAME")
kdbc_options.password = os.environ.get("KINETICA_PASSWORD")
kdbc_options.disable_auto_discovery = True

kdbc = GPUdb(
    host=os.environ.get("KINETICA_HOST"),
    options=kdbc_options
)

# Use fixed table name
FIXED_TABLE_NAME = "nvidia_gtc_dli_2025.iperf3_logs"

# Ensure table exists
if not kdbc.has_table(table_name=FIXED_TABLE_NAME).table_exists:
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
    kdbc_table = gpudb.GPUdbTable(
        _type=schema,
        name=FIXED_TABLE_NAME,
        db=kdbc
    )
    logger.info(f"Created table: {FIXED_TABLE_NAME}")
else:
    kdbc_table = gpudb.GPUdbTable(name=FIXED_TABLE_NAME, db=kdbc)
    logger.info(f"Using existing table: {FIXED_TABLE_NAME}")

# Initialize InfluxDB client
try:
    from influxdb_client import InfluxDBClient, Point
    from influxdb_client.client.write_api import SYNCHRONOUS

    influx_url = os.getenv("INFLUXDB_URL", "http://localhost:9001")
    influx_token = os.getenv("INFLUXDB_TOKEN", "5g-lab-token")
    influx_org = os.getenv("INFLUXDB_ORG", "5g-lab")
    influx_bucket = os.getenv("INFLUXDB_BUCKET", "5g-metrics")

    influx_client = InfluxDBClient(url=influx_url, token=influx_token, org=influx_org)
    influx_write_api = influx_client.write_api(write_options=SYNCHRONOUS)
    logger.info(f"Connected to InfluxDB at {influx_url}")
except Exception as e:
    logger.warning(f"InfluxDB not available: {e}")
    influx_write_api = None

# Regex pattern to parse iperf3 output
filter_regex = (
    r'^\[ *([0-9]+)\] +([0-9]+\.[0-9]+)-([0-9]+\.[0-9]+) +sec +'
    r'([0-9\.]+) +MBytes +([0-9\.]+) +Mbits/sec +([0-9\.]+) +ms +'
    r'([0-9]+)/([0-9]+) +\(([0-9\.]+)%\)$'
)
pattern: Pattern[str] = re.compile(filter_regex)


def write_to_influxdb(ue_name: str, record: dict):
    """Write metrics to InfluxDB for Grafana visualization"""
    if influx_write_api is None:
        return

    try:
        point = Point("iperf3_metrics") \
            .tag("ue", ue_name) \
            .field("bitrate", float(record["bitrate"])) \
            .field("jitter", float(record["jitter"])) \
            .field("loss_percentage", float(record["loss_percentage"])) \
            .field("lost_packets", int(record["lost_packets"])) \
            .field("total_packets", int(record["total_packets"])) \
            .field("data_transferred", float(record["data_transferred"]))

        influx_write_api.write(bucket=influx_bucket, org=influx_org, record=point)
    except Exception as e:
        logger.error(f"Failed to write to InfluxDB: {e}")


def iperf_runner_continuous(
    ue_container: str,
    ue_name: str,
    bind_host: str,
    server_host: str,
    udp_port: int,
    bandwidth: str,
    test_length_secs: int,
    kdbc_table: gpudb.GPUdbTable,
    pattern: Pattern[str],
    log_file: str
) -> None:
    """
    Runs iperf3 client continuously from UE container, parses output and inserts into Kinetica and InfluxDB.
    """
    iteration = 0
    while True:
        iteration += 1
        try:
            iperf_cmd = (
                f"docker exec {ue_container} "
                f"iperf3 -B {bind_host} -c {server_host} -p {udp_port} "
                f"-R -u -b {bandwidth} -t {test_length_secs}"
            )

            logger.info(f"[{ue_name}] Iteration {iteration}: Starting traffic test with {bandwidth} for {test_length_secs}s")

            proc = subprocess.Popen(
                iperf_cmd.split(),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                bufsize=1
            )

            for line in proc.stdout:
                line = line.strip()
                match = pattern.match(line)
                if match:
                    # Create record from parsed line
                    record = {
                        "ue": ue_name,
                        "stream": int(match.group(1)),
                        "interval_start": float(match.group(2)),
                        "interval_end": float(match.group(3)),
                        "data_transferred": float(match.group(4)),
                        "bitrate": float(match.group(5)),
                        "jitter": float(match.group(6)),
                        "lost_packets": int(match.group(7)),
                        "total_packets": int(match.group(8)),
                        "loss_percentage": float(match.group(9)),
                        "duration": float(match.group(3)) - float(match.group(2))
                    }

                    # Insert into Kinetica (don't include 'id' - let DB auto-generate)
                    try:
                        kdbc_table.insert_records([record])
                    except Exception as e:
                        logger.error(f"Failed to insert to Kinetica: {e}")

                    # Write to InfluxDB
                    write_to_influxdb(ue_name, record)

                    # Write to log file
                    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    with open(log_file, "a") as f:
                        f.write(f"[{ue_name}] [{timestamp}] {line}\n")

            proc.wait()
            logger.info(f"[{ue_name}] Iteration {iteration} completed. Starting next iteration in 2 seconds...")
            time.sleep(2)  # Brief pause between iterations

        except Exception as e:
            logger.error(f"Error in {ue_name} iteration {iteration}: {e}")
            time.sleep(5)  # Wait before retrying on error


# Traffic generation parameters
bandwidth_ue1 = "30M"
bandwidth_ue2 = "120M"
server_host = "192.168.70.135"  # oai-ext-dn IP

test_length_secs = 60  # Each test runs for 60 seconds

logger.info("="*60)
logger.info("Starting CONTINUOUS traffic generation")
logger.info("UE1: oai-ue-slice1, binding to 12.1.1.2, port 5201, bandwidth: alternating 30M/120M")
logger.info("UE2: oai-ue-slice2 (if available), binding to 12.1.1.130, port 5202, bandwidth: alternating 120M/30M")
logger.info("="*60)

# Check if UE2 exists
ue2_exists = subprocess.run(["docker", "ps", "-q", "-f", "name=oai-ue-slice2"], capture_output=True).stdout.strip()

# Start continuous traffic generation for UE1
t1 = threading.Thread(
    target=iperf_runner_continuous,
    args=(
        "oai-ue-slice1",
        "UE1",
        "12.1.1.2",
        server_host,
        5201,
        bandwidth_ue1,
        test_length_secs,
        kdbc_table,
        pattern,
        "/home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/logs/UE1_iperfc.log"
    ),
    daemon=False  # Keep running
)

threads = [t1]
t1.start()

# Start UE2 if it exists
if ue2_exists:
    t2 = threading.Thread(
        target=iperf_runner_continuous,
        args=(
            "oai-ue-slice2",
            "UE2",
            "12.1.1.130",
            server_host,
            5202,
            bandwidth_ue2,
            test_length_secs,
            kdbc_table,
            pattern,
            "/home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/logs/UE2_iperfc.log"
        ),
        daemon=False
    )
    threads.append(t2)
    t2.start()
    logger.info("Started traffic generation for UE1 and UE2")
else:
    logger.info("Started traffic generation for UE1 only (UE2 not found)")

# Keep main thread alive
try:
    for t in threads:
        t.join()
except KeyboardInterrupt:
    logger.info("Stopping traffic generation...")
    if influx_write_api:
        influx_client.close()
