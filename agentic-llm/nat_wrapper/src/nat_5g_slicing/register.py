# SPDX-FileCopyrightText: Copyright (c) 2024-2025, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

"""Register 5G network management tools as NAT function groups."""

import asyncio
import logging
import os
import subprocess
from collections.abc import AsyncGenerator

import gpudb
import pandas as pd
from dotenv import find_dotenv, load_dotenv
from pydantic import BaseModel, Field

from nat.builder.builder import Builder
from nat.builder.function import FunctionGroup
from nat.cli.register_workflow import register_function_group
from nat.data_models.function import FunctionGroupBaseConfig


# =============================================================================
# Input Models (NAT requires exactly one Pydantic model parameter per function)
# =============================================================================

class ReconfigureNetworkInput(BaseModel):
    """Input schema for network reconfiguration."""
    ue: str = Field(
        description="User Equipment identifier (UE1 or UE3)"
    )
    value_1_old: int = Field(
        description="Old bandwidth allocation value for slice 1"
    )
    value_2_old: int = Field(
        description="Old bandwidth allocation value for slice 2"
    )


class GetPacketlossLogsInput(BaseModel):
    """Input schema for packet loss log retrieval."""
    limit: int = Field(
        default=20,
        description="Maximum number of log entries to retrieve"
    )


# =============================================================================
# Configuration
# =============================================================================

class NetworkManagementToolsConfig(FunctionGroupBaseConfig, name="network_tools"):
    """Configuration for 5G network management tools."""
    
    include: list[str] = Field(
        default_factory=lambda: ["reconfigure_network", "get_packetloss_logs"],
        description="The list of functions to include in the network management function group."
    )
    kinetica_host: str = Field(
        default="localhost:9191",
        description="Kinetica database host"
    )
    kinetica_username: str = Field(
        default="admin",
        description="Kinetica username"
    )
    kinetica_password: str = Field(
        default="admin",
        description="Kinetica password"
    )
    kinetica_schema: str = Field(
        default="nvidia_gtc_dli_2025",
        description="Kinetica schema"
    )
    iperf_table_name: str = Field(
        default="nvidia_gtc_dli_2025.iperf3_logs",
        description="iPerf3 logs table name"
    )
    reconfig_script_path: str = Field(
        default="../llm-slicing-5g-lab/docker/change_rc_slice_docker.sh",
        description="Path to network reconfiguration script"
    )


# =============================================================================
# Function Group Registration
# =============================================================================

@register_function_group(config_type=NetworkManagementToolsConfig)
async def network_tools(
    config: NetworkManagementToolsConfig,
    _builder: Builder
) -> AsyncGenerator[FunctionGroup, None]:
    """Create and register the 5G network management function group."""
    
    load_dotenv(find_dotenv())
    
    # Initialize Kinetica connection
    kdbc_options = gpudb.GPUdb.Options()
    kdbc_options.username = os.getenv("KINETICA_USERNAME", config.kinetica_username)
    kdbc_options.password = os.getenv("KINETICA_PASSWORD", config.kinetica_password)
    kdbc_options.disable_auto_discovery = True
    
    kdbc = gpudb.GPUdb(
        host=os.getenv("KINETICA_HOST", config.kinetica_host),
        options=kdbc_options
    )
    
    group = FunctionGroup(config=config)

    # -------------------------------------------------------------------------
    # Tool Functions (single Pydantic model input)
    # -------------------------------------------------------------------------

    async def _reconfigure_network(input: ReconfigureNetworkInput) -> str:
        """Reconfigure the 5G network bandwidth allocation.
        
        Args:
            input: ReconfigureNetworkInput containing ue, value_1_old, value_2_old
            
        Returns:
            New configuration values as a string
        """
        logging.info(
            f"Executing reconfigure_network with UE={input.ue}, "
            f"value_1_old={input.value_1_old}, value_2_old={input.value_2_old}"
        )
        
        script_path = os.getenv("RECONFIG_SCRIPT_PATH", config.reconfig_script_path)
        args_1 = ["20", "20"]
        
        # Determine new allocation based on UE
        if input.ue.upper() == "UE1":
            args_2 = ["80", "20"]
        else:
            args_2 = ["20", "80"]
        
        try:
            # Execute first reconfiguration
            result = subprocess.run(
                [script_path] + args_1,
                check=True,
                text=True,
                capture_output=True
            )
            logging.info(f"Script output args_1: {result.stdout}")
            
            # Execute second reconfiguration
            result = subprocess.run(
                [script_path] + args_2,
                check=True,
                text=True,
                capture_output=True
            )
            logging.info(f"Script output args_2: {result.stdout}")
            
            await asyncio.sleep(10)
            logging.info("Reconfiguration complete, waiting for changes to take effect")
            
            return str(args_2)
            
        except subprocess.CalledProcessError as e:
            logging.error(f"Reconfiguration failed: {e.stderr}")
            raise ValueError(f"Reconfiguration unsuccessful: {e.stderr}")

    async def _get_packetloss_logs(input: GetPacketlossLogsInput = None) -> str:
        """Get packet loss logs from Kinetica database to determine which UE is failing.
        
        Args:
            input: GetPacketlossLogsInput containing limit for number of entries
            
        Returns:
            Formatted string containing recent packet loss data for all UEs
        """
        if input is None:
            input = GetPacketlossLogsInput()
        
        logging.info("Retrieving packet loss logs from Kinetica database")
        
        await asyncio.sleep(5)
        
        load_dotenv(find_dotenv())
        table_name = os.getenv("IPERF3_RANDOM_TABLE_NAME", config.iperf_table_name)
        
        sql_query = f"""
            SELECT lost_packets, loss_percentage, UE 
            FROM {table_name} 
            ORDER BY timestamp DESC 
            LIMIT {input.limit};
        """
        
        try:
            response = kdbc.execute_sql_and_decode(statement=sql_query)
            
            if response and "records" in response and response["records"]:
                result_df = pd.DataFrame(response["records"])
                return result_df.to_string(index=False)
            else:
                return "WARNING: No packet loss data available at this time. Please try again later."
            
        except Exception as e:
            logging.error(f"Failed to retrieve packet loss logs: {e}")
            raise ValueError(f"Failed to query Kinetica database: {e}")

    # -------------------------------------------------------------------------
    # Register functions
    # -------------------------------------------------------------------------
    
    if "reconfigure_network" in config.include:
        group.add_function(
            name="reconfigure_network",
            fn=_reconfigure_network,
            description="Reconfigure the 5G network bandwidth allocation for a specific UE"
        )
    
    if "get_packetloss_logs" in config.include:
        group.add_function(
            name="get_packetloss_logs",
            fn=_get_packetloss_logs,
            description="Get packet loss logs from Kinetica database to determine which UE is failing"
        )

    yield group