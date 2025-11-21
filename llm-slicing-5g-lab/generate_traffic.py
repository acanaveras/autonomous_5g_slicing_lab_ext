#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Traffic generation script for 5G Lab
# Runs iperf3 clients and logs to Kinetica database

import os
import re
import subprocess
import threading
from datetime import datetime
from typing import Dict, Pattern
import gpudb
from gpudb import GPUdb
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s: %(message)s'
)
logger = logging.getLogger(__name__)

# Configure Kinetica connection (using localhost since script runs on host)
os.environ["KINETICA_HOST"] = "localhost:9191"
os.environ["KINETICA_USERNAME"] = "admin"
os.environ["KINETICA_PASSWORD"] = "admin"
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
    from gpudb import GPUdbColumnProperty as cp
    from gpudb import GPUdbRecordColumn as rc

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

# Regex pattern to parse iperf3 output
filter_regex = (
    r'^\[ *([0-9]+)\] +([0-9]+\.[0-9]+)-([0-9]+\.[0-9]+) +sec +'
    r'([0-9\.]+) +MBytes +([0-9\.]+) +Mbits/sec +([0-9\.]+) +ms +'
    r'([0-9]+)/([0-9]+) +\(([0-9\.]+)%\)$'
)
pattern: Pattern[str] = re.compile(filter_regex)


def iperf_runner(
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
    Runs iperf3 client from UE container, parses output and inserts into Kinetica.
    """
    try:
        iperf_cmd = (
            f"docker exec {ue_container} "
            f"iperf3 -B {bind_host} -c {server_host} -p {udp_port} "
            f"-R -u -b {bandwidth} -t {test_length_secs}"
        )

        logger.info(f"Starting {ue_name}: {iperf_cmd}")

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

                # Insert into Kinetica
                kdbc_table.insert_records(record)
                kdbc_table.flush_data_to_server()

                # Write to log file
                timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                with open(log_file, "a") as f:
                    f.write(f"[{ue_name}] [{timestamp}] {line}\n")

                logger.info(f"{ue_name}: {match.group(9)}% loss, {match.group(5)} Mbits/sec")

    except Exception as e:
        logger.error(f"Error in {ue_name}: {e}")


# Traffic generation parameters
bandwidth_ue1 = "30M"
server_host = "192.168.70.135"  # oai-ext-dn IP

test_length_secs = 100
test_iterations = 25

logger.info(f"Starting traffic generation for {test_iterations} iterations")
logger.info("UE1: oai-ue-slice1, binding to 12.1.1.2, port 5201")

current_iteration = 0

while current_iteration < test_iterations:
    logger.info(f"=== ITERATION {current_iteration + 1}/{test_iterations} ===")
    current_iteration += 1

    # Run iperf3 for UE1
    t1 = threading.Thread(
        target=iperf_runner,
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
        daemon=True
    )

    t1.start()
    t1.join()

    # Alternate bandwidth
    bandwidth_ue1 = "120M" if bandwidth_ue1 == "30M" else "30M"

logger.info("Traffic generation completed!")
