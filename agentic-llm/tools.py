# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This file defines the tools that are used by the agents.

import pandas as pd
import time
import os
from langchain_core.tools import tool
import subprocess
import yaml
import logging
from dotenv import load_dotenv, find_dotenv
import gpudb


config_file = yaml.safe_load(open('config.yaml', 'r'))
# Configure the logger without timestamp and level tags
logging.basicConfig(
    filename= config_file['AGENT_LOG_FILE'],  # Log file name
    level=logging.INFO,   # Log level
    format="%(message)s",  # Only log the message
    force=True  # Override any existing logging config
)

# Get the root logger and disable buffering
logger = logging.getLogger()
for handler in logger.handlers:
    handler.setLevel(logging.INFO)
    handler.flush()
    # Force immediate flush after each log by disabling buffering
    if hasattr(handler, 'stream'):
        handler.stream.reconfigure(line_buffering=True)

# Configure for Kinetica instance (use container IP when running in Docker)
os.environ["KINETICA_HOST"] = os.getenv("KINETICA_HOST", "192.168.70.172:9191")
os.environ["KINETICA_USERNAME"] = os.getenv("KINETICA_USERNAME", "admin")
os.environ["KINETICA_PASSWORD"] = os.getenv("KINETICA_PASSWORD", "admin")
os.environ["KINETICA_SCHEMA"] = os.getenv("KINETICA_SCHEMA", "nvidia_gtc_dli_2025")

kdbc_options = gpudb.GPUdb.Options()
kdbc_options.username = os.environ.get("KINETICA_USERNAME")
kdbc_options.password = os.environ.get("KINETICA_PASSWORD")
kdbc_options.disable_auto_discovery = True
kdbc: gpudb.GPUdb = gpudb.GPUdb(
    host=os.environ.get("KINETICA_HOST"),
    options=kdbc_options
)


@tool
def reconfigure_network(UE: str, value_1_old: int, value_2_old: int):
    """
    Use this tool to reconfigure the network. The tool reconfigures network, and returns new configuration values.
    """
    time.sleep(2) #to improve logging
    logging.info(f"This is reconfigure_network Tool \n")
    logging.info(f"\n Executing reconfigure_network with UE={UE}, value_1_old={value_1_old}, value_2_old={value_2_old} \n")
    script_path = config_file['reconfig_script_path']
    config_value_1 = "20"
    config_value_2 = "80"
    args_1 = args_2 = None
    args_1 = ["20", "20"]
    
    if UE == "UE1":
       args_2 = ["80","20"]
    else: 
       args_2 = ["20","80"]
 
    try:
        logging.info(f"\n🔄 Running reconfiguration step 1 with args: {args_1}\n")
        result = subprocess.run([script_path] + args_1, check=True, text=True, capture_output=True, timeout=30)
        logging.info("\n✅ Script output args_1:\n")
        logging.info(result.stdout)
        if result.stderr:
            logging.info("Script stderr args_1:")
            logging.info(result.stderr)

        if args_2!=None:
          logging.info(f"\n🔄 Running reconfiguration step 2 with args: {args_2}\n")
          result = subprocess.run([script_path] + args_2, check=True, text=True, capture_output=True, timeout=30)
          logging.info("\n✅ Script output args_2:\n")
          logging.info(result.stdout)
          if result.stderr:
              logging.info("Script stderr args_2:")
              logging.info(result.stderr)

        time.sleep(10)
        logging.info("\n⏳ Wait for reconfiguration to kick in \n")
        if args_2 != None:
            return str(args_2)

        return str(args_1)
    except subprocess.TimeoutExpired as e:
        logging.info(f"\n❌ Error: Script timed out after 30 seconds\n")
        logging.info(f"Command: {e.cmd}\n")
        if e.stdout:
            logging.info(f"Stdout before timeout:\n{e.stdout}\n")
        if e.stderr:
            logging.info(f"Stderr before timeout:\n{e.stderr}\n")
        return "Reconfiguration unsuccessful - timeout"
    except subprocess.CalledProcessError as e:
        logging.info(f"\n❌ Error occurred during reconfiguration:\n")
        logging.info(f"Return code: {e.returncode}\n")
        if e.stdout:
            logging.info(f"Stdout:\n{e.stdout}\n")
        if e.stderr:
            logging.info(f"Stderr:\n{e.stderr}\n")
        return "Reconfiguration unsuccessful"


@tool
def get_packetloss_logs() -> str:
    """
    Get the logs to determine which UE is failing.
    FIXED: Now uses time-based filtering (last 30 seconds) to avoid stale data.
    """
    time.sleep(2) #to improve logging
    logging.info(f"This is get_packetloss_logs Tool \n")
    logging.info("\nRetrieving packet loss logs from database (FIXED: time-based filtering)\n")
    time.sleep(5) # wait for db to get updated
    iperf_random_table_name: str = os.getenv('IPERF3_RANDOM_TABLE_NAME')
    # Just to be sure we have the latest randomly generated table name
    load_dotenv(find_dotenv())

    # FIXED: Use time-based filtering instead of LIMIT to avoid stale data
    # This matches the MonitoringAgent's 30-second window
    sql_query = f"""
    SELECT lost_packets, loss_percentage, UE, timestamp
    FROM {os.getenv('IPERF3_RANDOM_TABLE_NAME')}
    WHERE timestamp > NOW() - INTERVAL '30' SECOND
    ORDER BY timestamp DESC;
    """

    logging.info(f"Query: {sql_query}")
    result_df: pd.DataFrame = kdbc.to_df(
        sql=sql_query
    )

    if result_df is None or result_df.empty:
        return "WARNING: A Problem has occurred. No results were found at this time. Please try again later."

    logging.info(f"Retrieved {len(result_df)} records from last 30 seconds\n")

    # Return summary instead of full dataframe to reduce log clutter
    summary = result_df.groupby('UE').agg({
        'loss_percentage': ['mean', 'max', 'min'],
        'lost_packets': 'sum'
    }).round(2)

    summary_str = f"Packet Loss Summary (Last 30 seconds):\n{summary.to_string()}\n\n"
    summary_str += f"Total records analyzed: {len(result_df)}"

    return summary_str
