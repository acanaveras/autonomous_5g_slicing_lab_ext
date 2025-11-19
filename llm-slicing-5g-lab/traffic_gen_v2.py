#!/usr/bin/env python3
# Continuous traffic generation for 5G Lab - Fixed Version
import os, re, subprocess, threading, time, logging
from datetime import datetime
from typing import Pattern

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

# Configure Kinetica
os.environ["KINETICA_HOST"] = "localhost:9191"
os.environ["KINETICA_USERNAME"] = "admin"
os.environ["KINETICA_PASSWORD"] = "Admin123!"

from gpudb import GPUdb
kdbc_options = GPUdb.Options()
kdbc_options.username = "admin"
kdbc_options.password = "Admin123!"
kdbc_options.disable_auto_discovery = True
kdbc = GPUdb(host="localhost:9191", options=kdbc_options)

FIXED_TABLE_NAME = "nvidia_gtc_dli_2025.iperf3_logs"

# Initialize InfluxDB
try:
    from influxdb_client import InfluxDBClient, Point
    from influxdb_client.client.write_api import SYNCHRONOUS
    influx_client = InfluxDBClient(url="http://localhost:9001", token="5g-lab-token", org="5g-lab")
    influx_write_api = influx_client.write_api(write_options=SYNCHRONOUS)
    logger.info("Connected to InfluxDB")
except Exception as e:
    logger.warning(f"InfluxDB not available: {e}")
    influx_write_api = None

# Regex for iperf3 output
pattern: Pattern[str] = re.compile(
    r'^\[ *([0-9]+)\] +([0-9]+\.[0-9]+)-([0-9]+\.[0-9]+) +sec +'
    r'([0-9\.]+) +MBytes +([0-9\.]+) +Mbits/sec +([0-9\.]+) +ms +'
    r'([0-9]+)/([0-9]+) +\(([0-9\.]+)%\)$'
)

def write_to_influxdb(ue_name: str, record: dict):
    if influx_write_api is None:
        return
    try:
        point = Point("iperf3_metrics") \
            .tag("ue", ue_name) \
            .field("bitrate", float(record["bitrate"])) \
            .field("jitter", float(record["jitter"])) \
            .field("loss_percentage", float(record["loss_percentage"]))
        influx_write_api.write(bucket="5g-metrics", org="5g-lab", record=point)
    except Exception as e:
        logger.debug(f"InfluxDB write failed: {e}")

def iperf_runner_continuous(ue_container, ue_name, bind_host, server_host, udp_port, bandwidth, test_length_secs, log_file):
    iteration = 0
    while True:
        iteration += 1
        try:
            iperf_cmd = f"docker exec {ue_container} iperf3 -B {bind_host} -c {server_host} -p {udp_port} -R -u -b {bandwidth} -t {test_length_secs}"
            logger.info(f"[{ue_name}] Iteration {iteration}: {bandwidth} for {test_length_secs}s")

            proc = subprocess.Popen(iperf_cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True, bufsize=1)

            for line in proc.stdout:
                line = line.strip()
                match = pattern.match(line)
                if match:
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

                    # Insert into Kinetica using SQL with quoted column names
                    try:
                        sql = f"""INSERT INTO {FIXED_TABLE_NAME} ("ue", "stream", "interval_start", "interval_end", "data_transferred", "bitrate", "jitter", "lost_packets", "total_packets", "loss_percentage", "duration")
                                  VALUES ('{record["ue"]}', {record["stream"]}, {record["interval_start"]}, {record["interval_end"]}, {record["data_transferred"]}, {record["bitrate"]}, {record["jitter"]}, {record["lost_packets"]}, {record["total_packets"]}, {record["loss_percentage"]}, {record["duration"]})"""
                        kdbc.execute_sql(sql)
                    except Exception as e:
                        logger.error(f"Kinetica insert failed: {e}")

                    # Write to InfluxDB
                    write_to_influxdb(ue_name, record)

                    # Write to log file
                    with open(log_file, "a") as f:
                        f.write(f"[{ue_name}] [{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {line}\n")

            proc.wait()
            logger.info(f"[{ue_name}] Iteration {iteration} completed")
            time.sleep(2)
        except Exception as e:
            logger.error(f"Error in {ue_name}: {e}")
            time.sleep(5)

# Start traffic generation
logger.info("="*60)
logger.info("CONTINUOUS TRAFFIC GENERATION STARTED")
logger.info("="*60)

t1 = threading.Thread(target=iperf_runner_continuous, args=(
    "oai-ue-slice1", "UE1", "12.1.1.2", "192.168.70.135", 5201, "30M", 60,
    "/home/ubuntu/autonomous_5g_slicing_lab_ext/llm-slicing-5g-lab/logs/UE1_iperfc.log"
), daemon=False)

t1.start()
logger.info("Traffic generation for UE1 started")

try:
    t1.join()
except KeyboardInterrupt:
    logger.info("Stopping...")
    if influx_write_api:
        influx_client.close()
