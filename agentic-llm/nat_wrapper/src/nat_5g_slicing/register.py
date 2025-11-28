# SPDX-FileCopyrightText: Copyright (c) 2024-2025, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

"""Register 5G network management tools as NAT function groups."""

from collections.abc import AsyncGenerator
import os
import subprocess
import time
import logging
from typing import Optional

import pandas as pd
import gpudb
from dotenv import load_dotenv, find_dotenv
from pydantic import Field

from nat.builder.builder import Builder
from nat.builder.function import FunctionGroup
from nat.cli.register_workflow import register_function_group
from nat.data_models.function import FunctionGroupBaseConfig


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


@register_function_group(config_type=NetworkManagementToolsConfig)
async def network_tools(
    config: NetworkManagementToolsConfig,
    _builder: Builder
) -> AsyncGenerator[FunctionGroup, None]:
    """Create and register the 5G network management function group.

    Args:
        config: Network management tools configuration.
        _builder: Workflow builder (unused).

    Yields:
        FunctionGroup: The configured network management function group with
            reconfigure_network and get_packetloss_logs operations.
    """
    # Load environment variables
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

    async def _reconfigure_network(
        ue: str,
        value_1_old: int,
        value_2_old: int
    ) -> str:
        """Reconfigure the 5G network bandwidth allocation.
        
        Args:
            ue: User Equipment identifier (UE1 or UE3)
            value_1_old: Old bandwidth allocation value for slice 1
            value_2_old: Old bandwidth allocation value for slice 2
            
        Returns:
            New configuration values as a string
        """
        logging.info(f"Executing reconfigure_network with UE={ue}, value_1_old={value_1_old}, value_2_old={value_2_old}")
        
        script_path = os.getenv("RECONFIG_SCRIPT_PATH", config.reconfig_script_path)
        args_1 = ["20", "20"]
        
        # Determine new allocation based on UE
        if ue.upper() == "UE1":
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
            
            # Wait for reconfiguration to take effect
            await asyncio.sleep(10)
            logging.info("Reconfiguration complete, waiting for changes to take effect")
            
            return str(args_2)
            
        except subprocess.CalledProcessError as e:
            logging.error(f"Reconfiguration failed: {e.stderr}")
            raise ValueError(f"Reconfiguration unsuccessful: {e.stderr}")

    async def _get_packetloss_logs() -> str:
        """Get packet loss logs from Kinetica database to determine which UE is failing.
        
        Returns:
            Formatted string containing recent packet loss data for all UEs
        """
        logging.info("Retrieving packet loss logs from Kinetica database")
        
        # Wait for database to update
        await asyncio.sleep(5)
        
        # Reload environment to get latest table name
        load_dotenv(find_dotenv())
        table_name = os.getenv("IPERF3_RANDOM_TABLE_NAME", config.iperf_table_name)
        
        sql_query = f"""
            SELECT lost_packets, loss_percentage, UE 
            FROM {table_name} 
            ORDER BY timestamp DESC 
            LIMIT 20;
        """
        
        try:
            result_df: pd.DataFrame = kdbc.to_df(sql=sql_query)
            
            if result_df is None or result_df.empty:
                return "WARNING: No packet loss data available at this time. Please try again later."
            
            return result_df.to_string(index=False)
            
        except Exception as e:
            logging.error(f"Failed to retrieve packet loss logs: {e}")
            raise ValueError(f"Failed to query Kinetica database: {e}")

    # Register functions in the group
    if "reconfigure_network" in config.include:
        group.add_function(
            name="reconfigure_network",
            fn=_reconfigure_network,
            description=_reconfigure_network.__doc__
        )
    
    if "get_packetloss_logs" in config.include:
        group.add_function(
            name="get_packetloss_logs",
            fn=_get_packetloss_logs,
            description=_get_packetloss_logs.__doc__
        )

    yield group


# Import asyncio for async operations
import asyncio
