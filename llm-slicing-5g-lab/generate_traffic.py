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

def iperf_runner_single(ue_container, ue_name, bind_host, server_host, udp_port, bandwidth, test_length_secs, log_file):
    """Run a single iperf test (not continuous)"""
    try:
        # CRITICAL FIX: Use unbuffered Python + immediate flush
        iperf_cmd = [
            "docker", "exec", ue_container,
            "iperf3", "-B", bind_host, "-c", server_host,
            "-p", str(udp_port), "-R", "-u", "-b", bandwidth,
            "-t", str(test_length_secs), "--forceflush"  # Force immediate output
        ]

        logger.info(f"🚀 [{ue_name}] Starting iperf test ({bandwidth}, {test_length_secs}s)")

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

                # Write to InfluxDB for this UE
                write_to_influxdb(ue_name, record)

                # Write to log file
                with open(log_file, "a") as f:
                    f.write(f"[{ue_name}] [{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {line}\n")

        proc.wait()
        logger.info(f"✅ [{ue_name}] Test completed - {records_inserted} records inserted")

    except Exception as e:
        logger.error(f"❌ Error in {ue_name}: {e}")

# Helper function to get UE IP with retry
def get_ue_ip_with_retry(container_name: str, interface: str, max_retries: int = 5) -> str:
    """Auto-detect UE IP address with retry logic"""
    for attempt in range(max_retries):
        try:
            result = subprocess.run(
                ["docker", "exec", container_name, "ip", "addr", "show", interface],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if 'inet ' in line and '/24' in line:
                        ip = line.strip().split()[1].split('/')[0]
                        logger.info(f"✅ Auto-detected {container_name} IP: {ip}")
                        return ip
        except Exception as e:
            logger.warning(f"Attempt {attempt + 1}/{max_retries} failed for {container_name}: {e}")
            time.sleep(2)

    logger.error(f"❌ Could not determine IP for {container_name}")
    return None

# Start traffic generation with bandwidth alternation for UE1 and UE3
logger.info("="*60)
logger.info("🚀 CONTINUOUS TRAFFIC GENERATION (UE1 + UE3 - REAL IPERF)")
logger.info("="*60)

# Auto-detect UE1 IP address
ue1_ip = get_ue_ip_with_retry("oai-ue-slice1", "oaitun_ue1")

if not ue1_ip:
    logger.error("❌ Failed to detect UE1 IP address. Exiting...")
    exit(1)

# Auto-detect UE3 IP address (from oai-ue-slice2 container using oaitun_ue3 interface)
ue3_ip = get_ue_ip_with_retry("oai-ue-slice2", "oaitun_ue3")

if not ue3_ip:
    logger.error("❌ Failed to detect UE3 IP address. Exiting...")
    exit(1)

logger.info(f"Using UE1 IP: {ue1_ip}")
logger.info(f"Using UE3 IP: {ue3_ip}")
logger.info("")
logger.info("📝 Note: Both UE1 and UE3 using REAL iperf3 traffic")
logger.info("   - UE1: Real iperf traffic with alternating bandwidth")
logger.info("   - UE3: Real iperf traffic with inverse bandwidth pattern")
logger.info("   - This demonstrates actual slicing behavior in Grafana dashboard")
logger.info("")

# Initial bandwidth settings (opposite patterns for UE1 and UE3)
bandwidth_ue1 = "30M"
bandwidth_ue3 = "120M"  # Inverse of UE1
test_length_secs = 60  # Each iteration runs for 60 seconds
iteration = 0

logger.info("🔄 Starting bandwidth alternation pattern:")
logger.info("   - UE1 and UE3 will alternate between 30M and 120M")
logger.info("   - Pattern shows effect of dynamic bandwidth slicing")
logger.info("")

def iperf_runner_parallel(ue_configs):
    """Run multiple iperf tests in parallel for different UEs"""
    threads = []

    for config in ue_configs:
        thread = threading.Thread(
            target=iperf_runner_single,
            args=(
                config["container"],
                config["ue_name"],
                config["bind_host"],
                config["server_host"],
                config["udp_port"],
                config["bandwidth"],
                config["test_length_secs"],
                config["log_file"]
            )
        )
        threads.append(thread)
        thread.start()

    # Wait for all threads to complete
    for thread in threads:
        thread.join()

try:
    while True:
        iteration += 1
        logger.info(f"📡 Iteration {iteration}: UE1={bandwidth_ue1}, UE3={bandwidth_ue3} (REAL iperf3)")

        # Configure both UE1 and UE3 for parallel execution
        ue_configs = [
            {
                "container": "oai-ue-slice1",
                "ue_name": "UE1",
                "bind_host": ue1_ip,
                "server_host": "192.168.70.135",
                "udp_port": 5201,
                "bandwidth": bandwidth_ue1,
                "test_length_secs": test_length_secs,
                "log_file": os.path.join(os.getcwd(), "logs", "UE1_iperfc.log")
            },
            {
                "container": "oai-ue-slice2",
                "ue_name": "UE3",
                "bind_host": ue3_ip,
                "server_host": "192.168.70.135",
                "udp_port": 5202,  # Different port for UE3
                "bandwidth": bandwidth_ue3,
                "test_length_secs": test_length_secs,
                "log_file": os.path.join(os.getcwd(), "logs", "UE3_iperfc.log")
            }
        ]

        # Run both UE1 and UE3 iperf tests in parallel
        iperf_runner_parallel(ue_configs)

        # Alternate bandwidths for next iteration (inverse pattern)
        if bandwidth_ue1 == "30M":
            bandwidth_ue1 = "120M"
            bandwidth_ue3 = "30M"
        else:
            bandwidth_ue1 = "30M"
            bandwidth_ue3 = "120M"

        # Small pause between iterations
        time.sleep(2)

except KeyboardInterrupt:
    logger.info("🛑 Stopping traffic generation...")
    if influx_write_api:
        influx_client.close()
