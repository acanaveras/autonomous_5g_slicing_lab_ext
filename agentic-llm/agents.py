# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# FIXED VERSION: Monitors packet loss metrics instead of log errors
# DATA STALENESS FIX: ConfigurationAgent now uses time-based filtering and MonitoringAgent's detected UE

import os
import random
import time
import yaml
from typing import TypedDict, Optional
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_nvidia_ai_endpoints import ChatNVIDIA
from langgraph.graph import StateGraph, MessagesState
from langgraph.prebuilt import create_react_agent
from tools import reconfigure_network, get_packetloss_logs
import logging
from dotenv import load_dotenv, find_dotenv
import pandas as pd
import gpudb

# Load environment variables from .env file
load_dotenv(find_dotenv())

print("___________________________________________starting agents (FIXED VERSION - MessagesState)")

# Setup Phoenix tracing if enabled
PHOENIX_ENABLED = os.getenv('PHOENIX_ENABLED', 'true').lower() == 'true'
if PHOENIX_ENABLED:
    try:
        # Import Phoenix OTEL registration from nat_5g_slicing
        import sys
        nat_wrapper_path = os.path.join(os.path.dirname(__file__), 'nat_wrapper', 'src')
        if nat_wrapper_path not in sys.path:
            sys.path.insert(0, nat_wrapper_path)

        from phoenix.otel import register as phoenix_register
        from openinference.instrumentation.langchain import LangChainInstrumentor

        # Register Phoenix tracer provider (global)
        # Let Phoenix auto-configure the endpoint to avoid 405 errors
        tracer_provider = phoenix_register(
            project_name="5g-network-monitoring-agent"
        )

        # Suppress verbose logging from OpenTelemetry before instrumentation
        import logging as stdlib_logging
        stdlib_logging.getLogger('openinference').setLevel(stdlib_logging.WARNING)
        stdlib_logging.getLogger('opentelemetry').setLevel(stdlib_logging.WARNING)

        # Instrument LangChain
        instrumentor = LangChainInstrumentor()
        if not instrumentor.is_instrumented_by_opentelemetry:
            instrumentor.instrument(tracer_provider=tracer_provider)

        print(f"✅ Phoenix tracing enabled (auto-configured endpoint)")
        print(f"   Project: 5g-network-monitoring-agent")
        print(f"   Phoenix UI: http://0.0.0.0:6006")
        print(f"   Note: Now using proper MessagesState - tracing should work correctly\n")
    except Exception as e:
        print(f"⚠️  Phoenix tracing failed to initialize: {e}")
        print(f"   Continuing without Phoenix...\n")
else:
    print("ℹ️  Phoenix tracing disabled (set PHOENIX_ENABLED=true to enable)\n")

# Configure the logger without timestamp and level tags
config_file =  yaml.safe_load(open('config.yaml', 'r'))

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

#llm api to use Nvidia NIM Inference Endpoints.
llm = ChatNVIDIA(
        model= os.getenv('NVIDIA_AI_MODEL_NAME'),
        api_key= os.getenv('NVIDIA_API_KEY'),
        temperature=0.2,
        top_p=0.7,
        max_tokens=4096,
)

# Kinetica connection setup
os.environ["KINETICA_HOST"] = os.getenv("KINETICA_HOST", "192.168.70.172:9191")
os.environ["KINETICA_USERNAME"] = os.getenv("KINETICA_USERNAME", "admin")
os.environ["KINETICA_PASSWORD"] = os.getenv("KINETICA_PASSWORD", "admin")

kdbc_options = gpudb.GPUdb.Options()
kdbc_options.username = os.environ.get("KINETICA_USERNAME")
kdbc_options.password = os.environ.get("KINETICA_PASSWORD")
kdbc_options.disable_auto_discovery = True
kdbc: gpudb.GPUdb = gpudb.GPUdb(
    host=os.environ.get("KINETICA_HOST"),
    options=kdbc_options
)

# State class for communication between agents
# FIXED: Now extends MessagesState to properly handle message objects
class State(MessagesState):
    """Extended MessagesState with additional fields for 5G network monitoring"""
    start: Optional[int] = None  # pointer to start reading from gnodeB.log
    agent_id: Optional[str] = None  # useful for routing between agents
    files: Optional[dict] = None  # pass error logs from Monitoring Agent to Configuration Agent
    consent: Optional[str] = None
    config_value: Optional[list] = None  # keep a track of slice values
    count: Optional[int] = None

def MonitoringAgent(state: State):
    """
    FIXED VERSION: Monitors packet loss metrics from Kinetica database
    instead of log files for buffer errors
    """
    response = "This is a Monitoring agent, monitoring PACKET LOSS METRICS for network issues."

    # Only log the agent start message once
    if state.get('count', 0) == 0:
        logging.info("\n" + "="*80)
        logging.info(response)
        logging.info("="*80 + "\n")

    # Configuration
    PACKET_LOSS_THRESHOLD = 1.5  # Trigger reconfiguration if loss > 1.5%
    CHECK_INTERVAL = 10  # Check every 10 seconds

    # Only log configuration on first run
    if state.get('count', 0) == 0:
        logging.info(f"📊 Monitoring Configuration:")
        logging.info(f"   - Packet Loss Threshold: {PACKET_LOSS_THRESHOLD}%")
        logging.info(f"   - Check Interval: {CHECK_INTERVAL} seconds")
        logging.info(f"   - Data Source: Kinetica Database\n")

    #Keep monitoring packet loss metrics
    while True:
        try:
            # Get table name from environment
            iperf_table_name = os.getenv('IPERF3_RANDOM_TABLE_NAME')

            if not iperf_table_name:
                logging.info("⚠️  IPERF3_RANDOM_TABLE_NAME not set, waiting...")
                time.sleep(CHECK_INTERVAL)
                continue

            # Query recent packet loss data
            sql_query = f"""
            SELECT ue, AVG(loss_percentage) as avg_loss, MAX(loss_percentage) as max_loss, COUNT(*) as samples
            FROM {iperf_table_name}
            WHERE timestamp > NOW() - INTERVAL '30' SECOND
            GROUP BY ue
            """

            # Query without logging - reduces verbosity
            result_df = kdbc.to_df(sql=sql_query)

            if result_df is None or result_df.empty:
                logging.info(f"⏳ No recent data yet, waiting {CHECK_INTERVAL} seconds...\n")
                time.sleep(CHECK_INTERVAL)
                continue

            # Check if any UE exceeds threshold
            high_loss_ues = result_df[result_df['max_loss'] > PACKET_LOSS_THRESHOLD]

            if not high_loss_ues.empty:
                # Only log when there's an issue
                logging.info(f"\n📊 Current Network Metrics (Last 30 seconds):")
                for _, row in result_df.iterrows():
                    logging.info(f"   - {row['ue']}: Avg Loss={row['avg_loss']:.2f}%, Max Loss={row['max_loss']:.2f}%, Samples={row['samples']}")

                logging.info(f"\n🚨 HIGH PACKET LOSS DETECTED!")
                for _, row in high_loss_ues.iterrows():
                    logging.info(f"   - {row['ue']}: {row['max_loss']:.2f}% loss (threshold: {PACKET_LOSS_THRESHOLD}%)")

                # IMPROVED: Warn if multiple UEs have high loss
                if len(high_loss_ues) > 1:
                    logging.info(f"\n⚠️  WARNING: Multiple UEs ({len(high_loss_ues)}) have high packet loss!")
                    logging.info(f"   Processing UE with highest loss first: {high_loss_ues.iloc[0]['ue']}\n")

                logging.info(f"\n➡️  Triggering Configuration Agent for reconfiguration...\n")

                # FIXED: Sort by max_loss to process worst UE first
                high_loss_ues = high_loss_ues.sort_values('max_loss', ascending=False)

                # Prepare data for Configuration Agent
                trigger_data = {
                    "ue": high_loss_ues.iloc[0]['ue'],
                    "avg_loss": high_loss_ues.iloc[0]['avg_loss'],
                    "max_loss": high_loss_ues.iloc[0]['max_loss'],
                    "samples": high_loss_ues.iloc[0]['samples']
                }

                # FIXED: Return messages as a list of message objects (SystemMessage)
                return {
                    "messages": [SystemMessage(content=response)],
                    "start": state.get('start', 0),
                    "files": {"metrics": trigger_data},
                    "config_value": state.get('config_value', ["50", "50"]),
                    "count": state.get('count', 0),
                    "consent": state.get('consent', 'yes')
                }
            else:
                # No logging when everything is normal - reduces log clutter
                time.sleep(CHECK_INTERVAL)

        except Exception as e:
            logging.info(f"❌ Error in MonitoringAgent: {e}")
            logging.info(f"   Retrying in {CHECK_INTERVAL} seconds...\n")
            time.sleep(CHECK_INTERVAL)

system_promt = 'You are a Configuration agent in a LangGraph. Your task is to help an user reconfigure a current 5G network. You must reply to the questions asked concisely, and exactly in the format directed to you.'
config_agent = create_react_agent(llm, tools=[reconfigure_network, get_packetloss_logs], prompt = system_promt)

def ConfigurationAgent(state: State):
    # Use a separate variable name to avoid collision with agent invoke responses
    agent_description = "This is a Configuration Agent, whose goal is to reconfigure the network to solve packet loss issues."
    logging.info("\n" + "="*80)
    logging.info(agent_description)
    logging.info("="*80 + "\n")
    logging.info("Packet loss metrics detected: \n %s \n\n", state['files']['metrics'])

    # FIXED: Use the UE already detected by MonitoringAgent instead of re-analyzing
    detected_ue = state['files']['metrics']['ue']
    detected_max_loss = state['files']['metrics']['max_loss']

    logging.info(f"🔍 Step 1: Using UE detected by MonitoringAgent...")
    logging.info(f"   Detected UE: {detected_ue}")
    logging.info(f"   Max packet loss: {detected_max_loss:.2f}%\n")

    # Still call get_packetloss_logs for verification and logging purposes
    prompt_0 = f'''
    The Monitoring Agent has detected high packet loss for {detected_ue} ({detected_max_loss:.2f}%).

    Call the get_packetloss_logs tool to verify and get recent packet loss data.
    Action: get_packetloss_logs()

    After reviewing the logs, confirm that {detected_ue} is the UE that needs reconfiguration.
    Reply with ONLY the UE name: either "UE1" or "UE2". DO NOT provide explanation.
    '''

    human_message = HumanMessage(content=prompt_0)
    response = config_agent.invoke({"messages":[human_message]})
    cleaned_content0 = response['messages'][-1].content
    logging.info(f"🎯 AI Confirmation: {cleaned_content0} requires reconfiguration\n")

    # Validation: Ensure AI confirms the same UE detected by MonitoringAgent
    if cleaned_content0.strip() != detected_ue:
        logging.info(f"⚠️  WARNING: AI selected {cleaned_content0} but MonitoringAgent detected {detected_ue}")
        logging.info(f"   Using MonitoringAgent's detection: {detected_ue} (more reliable)\n")
        cleaned_content0 = detected_ue

    prompt_1 = f'''

    Your task is to reconfigure the network using the `reconfigure_network` tool. The tool accepts the following parameters:
    1. `UE` = UE (UE1 or UE2) which requires reconfiguration
    2. `value_1_old` = Old value 1 of configs
    3. `value_2_old` = Old value 2 of configs

    Here is the input:
    - `UE` = {cleaned_content0}
    - `value_1_old` = {state['config_value'][0]}
    - `value_2_old` = {state['config_value'][1]}

    Use the tool to reconfigure the network. Return **only** the tool response list as the output.'''

    logging.info("🔧 Step 2: Reconfiguring network slice parameters...")
    human_message2 = HumanMessage(content=prompt_1)
    response2 = config_agent.invoke({"messages":[human_message2]})
    config_value_updated = response2['messages'][-2].content
    config_value_updated = config_value_updated.strip("[]").replace("'", "").split(", ")
    logging.info(f"✅ Reconfiguration complete! New slice values: {config_value_updated}\n")
    count = state['count']
    count += 1
    logging.info(f"📊 Total reconfigurations performed: {count}\n")

    #start monitoring from the end
    start = state.get('start', 0)

    #take in human input
    consent = 'yes'
    if count >= config_file['interrupt_after']:
        consent = input("Do you want to continue Monitoring? (yes/no)")

    # FIXED: Return messages as a list of message objects (SystemMessage)
    # Use agent_description (not response, which is now a dict from config_agent.invoke)
    return {
        "messages": [SystemMessage(content=agent_description)],
        "agent_id": "Configuration Agent",
        "start": start,
        'config_value': config_value_updated,
        'count': count,
        'consent': consent
    }
