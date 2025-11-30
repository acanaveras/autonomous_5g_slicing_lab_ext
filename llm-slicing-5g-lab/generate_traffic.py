#!/usr/bin/env python3
# FINAL FIXED VERSION - Real-time streaming traffic generator with auto-detection
import os, re, subprocess, threading, time, logging, random
from datetime import datetime
from typing import Pattern

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def get_ue_ip(container_name: str = "oai-ue-slice1") -> str:
    """Auto-detect UE IP address from the container"""
    try:
        result = subprocess.run(
            ["docker", "exec", container_name, "ip", "addr", "show", "oaitun_ue1"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            # Parse IP address from output like: "inet 12.1.1.3/24 brd ..."
            for line in result.stdout.split('\n'):
                if 'inet ' in line and '/24' in line:
                    ip = line.strip().split()[1].split('/')[0]
                    logger.info(f"✅ Auto-detected UE IP: {ip}")
                    return ip
    except Exception as e:
        logger.error(f"Failed to auto-detect UE IP: {e}")

    # Fallback to common IPs
    logger.warning("Could not auto-detect UE IP, trying common addresses...")
    for ip in ["12.1.1.2", "12.1.1.3", "12.1.1.4"]:
        try:
            # Test ping to see if interface responds
            result = subprocess.run(
                ["docker", "exec", container_name, "ping", "-I", ip, "-c", "1", "-W", "1", "192.168.70.135"],
                capture_output=True,
                timeout=3
            )
            if result.returncode == 0:
                logger.info(f"✅ Found working UE IP: {ip}")
                return ip
        except:
            continue

    logger.error("❌ Could not determine UE IP address!")
    return "12.1.1.2"  # Last resort fallback

def get_ue2_ip(container_name: str = "oai-ue-slice2", interface: str = "oaitun_ue3") -> str:
    """Auto-detect UE2 IP address from the container (uses oaitun_ue3 due to --node-number 4)"""
    try:
        result = subprocess.run(
            ["docker", "exec", container_name, "ip", "addr", "show", interface],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            # Parse IP address from output like: "inet 12.1.1.x/24 brd ..."
            for line in result.stdout.split('\n'):
                if 'inet ' in line and '/24' in line:
                    ip = line.strip().split()[1].split('/')[0]
                    logger.info(f"✅ Auto-detected UE2 IP: {ip}")
                    return ip
    except Exception as e:
        logger.error(f"Failed to auto-detect UE2 IP: {e}")

    # Fallback to common IPs for UE2
    logger.warning("Could not auto-detect UE2 IP, trying common addresses...")
    for ip in ["12.1.1.130", "12.1.1.131", "12.1.1.132"]:
        try:
            # Test ping to see if interface responds
            result = subprocess.run(
                ["docker", "exec", container_name, "ping", "-I", ip, "-c", "1", "-W", "1", "192.168.70.135"],
                capture_output=True,
                timeout=3
            )
            if result.returncode == 0:
                logger.info(f"✅ Found working UE2 IP: {ip}")
                return ip
        except:
            continue

    logger.error("❌ Could not determine UE2 IP address!")
    return "12.1.1.130"  # Last resort fallback

# Configure Kinetica (optional - will continue without it)
try:
    from gpudb import GPUdb, GPUdbTable
    from gpudb import GPUdbColumnProperty as cp
    from gpudb import GPUdbRecordColumn as rc

    kdbc_options = GPUdb.Options()
    kdbc_options.username = "admin"
    kdbc_options.password = "admin"  # Using actual Kinetica password
    kdbc_options.disable_auto_discovery = True
    kdbc = GPUdb(host="localhost:9191", options=kdbc_options)
    FIXED_TABLE_NAME = "nvidia_gtc_dli_2025.iperf3_logs"
    logger.info("✅ Connected to Kinetica")

    # Create schema if it doesn't exist
    target_schema = "nvidia_gtc_dli_2025"
    try:
        existing_schemas = kdbc.show_schema(schema_name=target_schema)
        if not existing_schemas['schema_names']:
            kdbc.create_schema(schema_name=target_schema)
            logger.info(f"✅ Created schema: {target_schema}")
        else:
            logger.info(f"✅ Schema exists: {target_schema}")
    except Exception as e:
        # Try to create anyway
        try:
            kdbc.create_schema(schema_name=target_schema)
            logger.info(f"✅ Created schema: {target_schema}")
        except:
            logger.info(f"✅ Schema already exists: {target_schema}")

    # Create table if it doesn't exist
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
        # Table exists, just get reference to it
        kdbc_table = GPUdbTable(name=FIXED_TABLE_NAME, db=kdbc)
        logger.info(f"✅ Using existing Kinetica table: {FIXED_TABLE_NAME}")

except Exception as e:
    logger.warning(f"⚠️  Kinetica not available: {e}")
    kdbc = None
    kdbc_table = None
    FIXED_TABLE_NAME = None

# Initialize InfluxDB
try:
    from influxdb_client import InfluxDBClient, Point
    from influxdb_client.client.write_api import SYNCHRONOUS
    influx_client = InfluxDBClient(url="http://localhost:9001", token="5g-lab-token", org="5g-lab")
    influx_write_api = influx_client.write_api(write_options=SYNCHRONOUS)
    logger.info("✅ Connected to InfluxDB")
except Exception as e:
    logger.warning(f"⚠️  InfluxDB not available: {e}")
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
        point = Point("network_metrics") \
            .tag("ue", ue_name) \
            .field("bitrate", float(record["bitrate"])) \
            .field("jitter", float(record["jitter"])) \
            .field("loss_percentage", float(record["loss_percentage"])) \
            .field("lost_packets", int(record["lost_packets"])) \
            .field("total_packets", int(record["total_packets"]))
        influx_write_api.write(bucket="5g-metrics", org="5g-lab", record=point)
    except Exception as e:
        pass  # Silent fail for InfluxDB

def iperf_runner_continuous(ue_container, ue_name, bind_host, server_host, udp_port, bandwidth_list, test_length_secs, log_file):
    """
    Run continuous iperf3 tests with alternating bandwidth.

    Args:
        bandwidth_list: List of two bandwidths to alternate between (e.g., ["30M", "120M"])
    """
    iteration = 0
    bandwidth_index = 0  # Start with first bandwidth in list

    while True:
        iteration += 1
        current_bandwidth = bandwidth_list[bandwidth_index]

        try:
            # CRITICAL FIX: Use unbuffered Python + immediate flush
            iperf_cmd = [
                "docker", "exec", ue_container,
                "iperf3", "-B", bind_host, "-c", server_host,
                "-p", str(udp_port), "-R", "-u", "-b", current_bandwidth,
                "-t", str(test_length_secs), "--forceflush"  # Force immediate output
            ]

            logger.info(f"🚀 [{ue_name}] Starting iteration {iteration} ({current_bandwidth}, {test_length_secs}s)")

            proc = subprocess.Popen(
                iperf_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                bufsize=1  # Line buffered
            )

            records_inserted = 0
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

                    # Insert into Kinetica IMMEDIATELY (if available)
                    if kdbc is not None:
                        try:
                            sql = f"""INSERT INTO {FIXED_TABLE_NAME} ("ue", "stream", "interval_start", "interval_end", "data_transferred", "bitrate", "jitter", "lost_packets", "total_packets", "loss_percentage", "duration")
                                      VALUES ('{record["ue"]}', {record["stream"]}, {record["interval_start"]}, {record["interval_end"]}, {record["data_transferred"]}, {record["bitrate"]}, {record["jitter"]}, {record["lost_packets"]}, {record["total_packets"]}, {record["loss_percentage"]}, {record["duration"]})"""
                            kdbc.execute_sql(sql)
                            records_inserted += 1

                            # Log progress every 10 records
                            if records_inserted % 10 == 0:
                                logger.info(f"   📊 [{ue_name}] {records_inserted} records inserted to Kinetica...")

                        except Exception as e:
                            if records_inserted == 0:  # Only log first error
                                logger.error(f"❌ [{ue_name}] Kinetica insert failed: {e}")

                    # Write to InfluxDB
                    write_to_influxdb(ue_name, record)

                    # Write to log file
                    with open(log_file, "a") as f:
                        f.write(f"[{ue_name}] [{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {line}\n")

            proc.wait()
            logger.info(f"✅ [{ue_name}] Iteration {iteration} completed - {records_inserted} records inserted")

            # Alternate bandwidth for next iteration
            bandwidth_index = (bandwidth_index + 1) % len(bandwidth_list)
            time.sleep(2)

        except Exception as e:
            logger.error(f"❌ Error in {ue_name}: {e}")
            time.sleep(5)

# Start traffic generation
logger.info("="*60)
logger.info("🚀 CONTINUOUS REAL-TIME TRAFFIC GENERATION - DUAL UE WITH ALTERNATING BANDWIDTH")
logger.info("="*60)

# Auto-detect UE1 IP address
ue1_ip = get_ue_ip("oai-ue-slice1")
logger.info(f"Using UE1 IP: {ue1_ip}")

# Auto-detect UE2 IP address
ue2_ip = get_ue2_ip("oai-ue-slice2")
logger.info(f"Using UE2 IP: {ue2_ip}")

# Define alternating bandwidths (matching original DLI_Lab_Setup.ipynb behavior)
# UE1 starts at 30M, alternates to 120M
# UE2 starts at 120M, alternates to 30M
# This creates congestion scenarios that alternate between slices
logger.info("")
logger.info("Traffic Pattern:")
logger.info("  UE1: 30M → 120M → 30M → 120M ... (alternating)")
logger.info("  UE2: 120M → 30M → 120M → 30M ... (alternating, opposite of UE1)")
logger.info("  This creates alternating congestion to demonstrate dynamic bandwidth allocation")
logger.info("")

# Create traffic generation threads for both UEs with alternating bandwidths
t1 = threading.Thread(target=iperf_runner_continuous, args=(
    "oai-ue-slice1", "UE1", ue1_ip, "192.168.70.135", 5201,
    ["30M", "120M"],  # Start at 30M, then alternate to 120M
    100,  # 100 seconds per iteration (matching original)
    os.path.join(os.getcwd(), "logs", "UE1_iperfc.log")
), daemon=False)

t2 = threading.Thread(target=iperf_runner_continuous, args=(
    "oai-ue-slice2", "UE2", ue2_ip, "192.168.70.135", 5202,
    ["120M", "30M"],  # Start at 120M, then alternate to 30M (opposite of UE1)
    100,  # 100 seconds per iteration (matching original)
    os.path.join(os.getcwd(), "logs", "UE2_iperfc.log")
), daemon=False)

# Start both traffic generators
t1.start()
t2.start()
logger.info("✅ Traffic generation for UE1 and UE2 started - real-time streaming enabled")
logger.info("   Both UEs will alternate between 30M and 120M to create congestion scenarios")

try:
    t1.join()
    t2.join()
except KeyboardInterrupt:
    logger.info("🛑 Stopping...")
    if influx_write_api:
        influx_client.close()
