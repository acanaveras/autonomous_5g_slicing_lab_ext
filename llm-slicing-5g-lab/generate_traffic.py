#!/usr/bin/env python3
# FINAL FIXED VERSION - Real-time streaming traffic generator with auto-detection
import os, re, subprocess, threading, time, logging, random
from datetime import datetime
from typing import Pattern

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def get_ue_ip(namespace: str = "ue1", interface: str = "oaitun_ue1") -> str:
    """Auto-detect UE IP address from the namespace (UPDATED FOR NAMESPACES)"""
    try:
        result = subprocess.run(
            ["sudo", "ip", "netns", "exec", namespace, "ip", "addr", "show", interface],
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
                ["sudo", "ip", "netns", "exec", namespace, "ping", "-I", ip, "-c", "1", "-W", "1", "192.168.70.135"],
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

def iperf_runner_single(ue_namespace, ue_name, bind_host, server_host, udp_port, bandwidth, test_length_secs, log_file):
    """Run a single iperf test (not continuous) - UPDATED FOR NAMESPACES"""
    try:
        # Run iperf3 in namespace instead of Docker container
        iperf_cmd = [
            "sudo", "ip", "netns", "exec", ue_namespace,
            "iperf3", "-B", bind_host, "-c", server_host,
            "-p", str(udp_port), "-R", "-u", "-b", bandwidth,
            "-t", str(test_length_secs), "--forceflush"  # Force immediate output
        ]

        logger.info(f"🚀 [{ue_name}] Starting iperf test in namespace {ue_namespace} ({bandwidth}, {test_length_secs}s)")

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

# Helper function to get UE IP with retry (UPDATED FOR NAMESPACES)
def get_ue_ip_with_retry(namespace: str, interface: str, max_retries: int = 5) -> str:
    """Auto-detect UE IP address from namespace with retry logic"""
    for attempt in range(max_retries):
        try:
            result = subprocess.run(
                ["sudo", "ip", "netns", "exec", namespace, "ip", "addr", "show", interface],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if 'inet ' in line and '/24' in line:
                        ip = line.strip().split()[1].split('/')[0]
                        logger.info(f"✅ Auto-detected {namespace} ({interface}) IP: {ip}")
                        return ip
        except Exception as e:
            logger.warning(f"Attempt {attempt + 1}/{max_retries} failed for {namespace}: {e}")
            time.sleep(2)

    logger.error(f"❌ Could not determine IP for {namespace}")
    return None

# Start traffic generation with bandwidth alternation for both UE1 and UE2
logger.info("="*60)
logger.info("🚀 CONTINUOUS TRAFFIC GENERATION (UE1 + UE2 - REAL TRAFFIC)")
logger.info("="*60)

# Auto-detect UE1 IP address from namespace ue1
ue1_ip = get_ue_ip_with_retry("ue1", "oaitun_ue1")

if not ue1_ip:
    logger.error("❌ Failed to detect UE1 IP address from namespace ue1. Exiting...")
    exit(1)

# Auto-detect UE2 IP address from namespace ue2
ue2_ip = get_ue_ip_with_retry("ue2", "oaitun_ue2")

if not ue2_ip:
    logger.error("❌ Failed to detect UE2 IP address from namespace ue2. Exiting...")
    exit(1)

logger.info(f"Using UE1 IP: {ue1_ip}")
logger.info(f"Using UE2 IP: {ue2_ip}")
logger.info("")
logger.info("📝 Both UE1 and UE2 will run REAL iperf3 traffic")
logger.info("   - UE1: Real iperf traffic to port 5201 with alternating bandwidth")
logger.info("   - UE2: Real iperf traffic to port 5202 with inverse bandwidth pattern")
logger.info("   - This demonstrates real slicing behavior in Grafana dashboard")
logger.info("")

# Initial bandwidth settings (opposite patterns for UE1 and UE2)
bandwidth_ue1 = "30M"
bandwidth_ue2 = "120M"  # Inverse of UE1
test_length_secs = 60  # Each iteration runs for 60 seconds
iteration = 0

logger.info("🔄 Starting bandwidth alternation pattern:")
logger.info("   - UE1 and UE2 will alternate between 30M and 120M")
logger.info("   - Pattern shows effect of dynamic bandwidth slicing")
logger.info("")

def simulate_ue2_metrics(ue1_record, target_bandwidth, ue1_bandwidth):
    """Create realistic UE2 metrics based on UE1 pattern but different bandwidth"""
    # Calculate bandwidth ratio
    ue1_bw = 30 if ue1_bandwidth == "30M" else 120
    ue2_bw = 30 if target_bandwidth == "30M" else 120
    ratio = ue2_bw / ue1_bw

    # Simulate packet loss based on bandwidth demand and slice allocation
    # Assume 50/50 slice allocation initially (each slice gets ~60M of 120M total)
    # When requesting 120M with 50% allocation, expect ~0.5-2% loss
    # When requesting 30M with 50% allocation, minimal loss ~0-0.3%
    base_loss_ue1 = 0.0
    base_loss_ue2 = 0.0

    if ue1_bw == 120:  # UE1 high bandwidth
        # Requesting 120M but slice limited to ~60M → congestion
        base_loss_ue1 = random.uniform(0.5, 2.0)
    else:  # UE1 low bandwidth
        # Requesting 30M, well within 60M limit → minimal loss
        base_loss_ue1 = random.uniform(0.0, 0.3)

    if ue2_bw == 120:  # UE2 high bandwidth
        # Requesting 120M but slice limited to ~60M → congestion
        base_loss_ue2 = random.uniform(0.8, 2.5)  # Slightly different than UE1
    else:  # UE2 low bandwidth
        # Requesting 30M, well within 60M limit → minimal loss
        base_loss_ue2 = random.uniform(0.0, 0.4)

    # Calculate total packets based on bandwidth and duration
    total_packets = int(ue1_record["total_packets"] * ratio * random.uniform(0.95, 1.05))
    lost_packets = int(total_packets * (base_loss_ue2 / 100.0))

    # Create UE2 record with scaled metrics and realistic variations
    ue2_record = {
        "ue": "UE2",
        "stream": ue1_record["stream"],
        "interval_start": ue1_record["interval_start"],
        "interval_end": ue1_record["interval_end"],
        "duration": ue1_record["duration"],
        # Scale bandwidth with ratio + small random variation
        "bitrate": ue1_record["bitrate"] * ratio * random.uniform(0.95, 1.05),
        "data_transferred": ue1_record["data_transferred"] * ratio * random.uniform(0.95, 1.05),
        # Jitter varies independently (higher at high bandwidth)
        "jitter": ue1_record["jitter"] * random.uniform(0.8, 1.5) + (2.0 if ue2_bw == 120 else 0.5),
        # Realistic packet loss based on bandwidth demand vs allocation
        "loss_percentage": base_loss_ue2,
        "lost_packets": lost_packets,
        "total_packets": total_packets,
    }

    # Using real iperf3 packet loss for UE1 (not simulated)
    # Real values are already captured from iperf3 output parsing

    return ue2_record

def iperf_runner_with_ue2_sim(ue_namespace, ue_name, bind_host, server_host, udp_port, bandwidth, test_length_secs, log_file, ue2_bandwidth):
    """Run iperf for UE1 and simulate UE2 metrics - UPDATED FOR NAMESPACES"""
    global ue1_last_metrics
    try:
        iperf_cmd = [
            "sudo", "ip", "netns", "exec", ue_namespace,
            "iperf3", "-B", bind_host, "-c", server_host,
            "-p", str(udp_port), "-R", "-u", "-b", bandwidth,
            "-t", str(test_length_secs), "--forceflush"
        ]

        logger.info(f"🚀 [UE1] Starting iperf test in namespace {ue_namespace} ({bandwidth}, {test_length_secs}s)")
        logger.info(f"🎭 [UE2] Simulating with bandwidth {ue2_bandwidth}")

        proc = subprocess.Popen(
            iperf_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1
        )

        records_inserted = 0
        ue2_records_inserted = 0

        for line in proc.stdout:
            line = line.strip()
            match = pattern.match(line)
            if match:
                # Parse UE1 record
                ue1_record = {
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

                # Insert UE1 into Kinetica
                if kdbc is not None:
                    try:
                        sql = f"""INSERT INTO {FIXED_TABLE_NAME} ("ue", "stream", "interval_start", "interval_end", "data_transferred", "bitrate", "jitter", "lost_packets", "total_packets", "loss_percentage", "duration")
                                  VALUES ('{ue1_record["ue"]}', {ue1_record["stream"]}, {ue1_record["interval_start"]}, {ue1_record["interval_end"]}, {ue1_record["data_transferred"]}, {ue1_record["bitrate"]}, {ue1_record["jitter"]}, {ue1_record["lost_packets"]}, {ue1_record["total_packets"]}, {ue1_record["loss_percentage"]}, {ue1_record["duration"]})"""
                        kdbc.execute_sql(sql)
                        records_inserted += 1
                    except Exception as e:
                        if records_inserted == 0:
                            logger.error(f"❌ [UE1] Kinetica insert failed: {e}")

                # Generate UE2 simulated metrics (this also adds loss to UE1)
                ue2_record = simulate_ue2_metrics(ue1_record, ue2_bandwidth, bandwidth)

                # Write UE1 to InfluxDB (now with added packet loss)
                write_to_influxdb(ue_name, ue1_record)

                # Write UE2 to InfluxDB
                write_to_influxdb("UE2", ue2_record)

                # Insert UE2 into Kinetica
                if kdbc is not None:
                    try:
                        sql = f"""INSERT INTO {FIXED_TABLE_NAME} ("ue", "stream", "interval_start", "interval_end", "data_transferred", "bitrate", "jitter", "lost_packets", "total_packets", "loss_percentage", "duration")
                                  VALUES ('{ue2_record["ue"]}', {ue2_record["stream"]}, {ue2_record["interval_start"]}, {ue2_record["interval_end"]}, {ue2_record["data_transferred"]}, {ue2_record["bitrate"]}, {ue2_record["jitter"]}, {ue2_record["lost_packets"]}, {ue2_record["total_packets"]}, {ue2_record["loss_percentage"]}, {ue2_record["duration"]})"""
                        kdbc.execute_sql(sql)
                        ue2_records_inserted += 1
                    except Exception as e:
                        if ue2_records_inserted == 0:
                            logger.error(f"❌ [UE2] Kinetica insert failed: {e}")

                # Write to UE1 log file
                with open(log_file, "a") as f:
                    f.write(f"[{ue_name}] [{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {line}\n")

                # Write to UE2 log file
                ue2_log = os.path.join(os.getcwd(), "logs", "UE2_iperfc.log")
                with open(ue2_log, "a") as f:
                    f.write(f"[UE2] [{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] SIMULATED - Bitrate: {ue2_record['bitrate']:.2f} Mbits/sec, Loss: {ue2_record['loss_percentage']:.2f}%\n")

        proc.wait()
        logger.info(f"✅ [UE1] Test completed - {records_inserted} records inserted")
        logger.info(f"✅ [UE2] Simulation completed - {ue2_records_inserted} records inserted")

    except Exception as e:
        logger.error(f"❌ Error in {ue_name}: {e}")

try:
    while True:
        iteration += 1
        logger.info(f"📡 Iteration {iteration}: UE1={bandwidth_ue1}, UE2={bandwidth_ue2}")

        # Run UE1 and UE2 traffic in parallel using threads (UPDATED FOR NAMESPACES)
        ue1_thread = threading.Thread(
            target=iperf_runner_single,
            args=("ue1", "UE1", ue1_ip, "192.168.70.135", 5201,
                  bandwidth_ue1, test_length_secs,
                  os.path.join(os.getcwd(), "logs", "UE1_iperfc.log"))
        )

        ue2_thread = threading.Thread(
            target=iperf_runner_single,
            args=("ue2", "UE2", ue2_ip, "192.168.70.135", 5202,
                  bandwidth_ue2, test_length_secs,
                  os.path.join(os.getcwd(), "logs", "UE2_iperfc.log"))
        )

        # Start both threads
        ue1_thread.start()
        ue2_thread.start()

        # Wait for both to complete
        ue1_thread.join()
        ue2_thread.join()

        logger.info(f"✅ Iteration {iteration} completed for both UE1 and UE2")

        # Alternate bandwidths for next iteration (inverse pattern)
        if bandwidth_ue1 == "30M":
            bandwidth_ue1 = "120M"
            bandwidth_ue2 = "30M"
        else:
            bandwidth_ue1 = "30M"
            bandwidth_ue2 = "120M"

        # Small pause between iterations
        time.sleep(2)

except KeyboardInterrupt:
    logger.info("🛑 Stopping traffic generation...")
    if influx_write_api:
        influx_client.close()
