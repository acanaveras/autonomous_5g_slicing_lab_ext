#!/bin/bash

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

ue_id=-1

create_namespace() {
  ue_id=$1
  local name="ue$ue_id"
  echo "creating namespace for UE ID ${ue_id} name ${name}"

  # Create namespace
  ip netns add $name

  # Create veth pair
  ip link add v-eth$ue_id type veth peer name v-ue$ue_id
  ip link set v-ue$ue_id netns $name

  # Calculate IP addresses (10.201.1.x for UE1, 10.202.1.x for UE2)
  BASE_IP=$((200+ue_id))
  ip addr add 10.$BASE_IP.1.100/24 dev v-eth$ue_id
  ip link set v-eth$ue_id up

  # Find Docker bridge interface for demo-oai-public-net
  DOCKER_BRIDGE=$(docker network inspect demo-oai-public-net --format '{{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null || echo "demo-oai")
  if [ -z "$DOCKER_BRIDGE" ]; then
    DOCKER_BRIDGE="demo-oai"
  fi

  # Set up NAT and forwarding to Docker network
  iptables -t nat -A POSTROUTING -s 10.$BASE_IP.1.0/255.255.255.0 -o $DOCKER_BRIDGE -j MASQUERADE
  iptables -A FORWARD -i $DOCKER_BRIDGE -o v-eth$ue_id -j ACCEPT
  iptables -A FORWARD -o $DOCKER_BRIDGE -i v-eth$ue_id -j ACCEPT

  # Also enable forwarding to all interfaces for general connectivity
  iptables -A FORWARD -i v-eth$ue_id -j ACCEPT
  iptables -A FORWARD -o v-eth$ue_id -j ACCEPT

  # Configure namespace
  ip netns exec $name ip link set dev lo up
  ip netns exec $name ip addr add 10.$BASE_IP.1.$ue_id/24 dev v-ue$ue_id
  ip netns exec $name ip link set v-ue$ue_id up

  # Add routes in namespace
  # Default route to host for general connectivity
  ip netns exec $name ip route add default via 10.$BASE_IP.1.100

  # Explicit route to Docker network subnet through host
  ip netns exec $name ip route add 192.168.70.128/26 via 10.$BASE_IP.1.100

  # Add route on host to reach namespace
  ip route add 10.$BASE_IP.1.0/24 dev v-eth$ue_id 2>/dev/null || true

  echo "Namespace $name created with IP 10.$BASE_IP.1.$ue_id"
  echo "Routes configured for Docker network (192.168.70.128/26)"
  echo "Docker bridge: $DOCKER_BRIDGE"
}

delete_namespace() {
  local ue_id=$1
  local name="ue$ue_id"
  echo "deleting namespace for UE ID ${ue_id} name ${name}"

  # Calculate IP addresses
  BASE_IP=$((200+ue_id))

  # Find Docker bridge interface
  DOCKER_BRIDGE=$(docker network inspect demo-oai-public-net --format '{{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null || echo "demo-oai")
  if [ -z "$DOCKER_BRIDGE" ]; then
    DOCKER_BRIDGE="demo-oai"
  fi

  # Remove iptables rules
  iptables -t nat -D POSTROUTING -s 10.$BASE_IP.1.0/255.255.255.0 -o $DOCKER_BRIDGE -j MASQUERADE 2>/dev/null || true
  iptables -D FORWARD -i $DOCKER_BRIDGE -o v-eth$ue_id -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -o $DOCKER_BRIDGE -i v-eth$ue_id -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -i v-eth$ue_id -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -o v-eth$ue_id -j ACCEPT 2>/dev/null || true

  # Remove route
  ip route del 10.$BASE_IP.1.0/24 dev v-eth$ue_id 2>/dev/null || true

  # Delete veth pair and namespace
  ip link delete v-eth$ue_id 2>/dev/null || true
  ip netns delete $name 2>/dev/null || true

  echo "Namespace $name deleted"
}

list_namespaces() {
  ip netns list
}

open_namespace() {
  if [[ $ue_id -lt 1 ]]; then echo "error: no last UE processed"; exit 1; fi
  local name="ue$ue_id"
  echo "opening shell in namespace ${name}"
  echo "type 'ip netns exec $name bash' in additional terminals"
  ip netns exec $name bash
}

usage () {
  echo "$1 -c <num>: create namespace \"ue<num>\""
  echo "$1 -d <num>: delete namespace \"ue<num>\""
  echo "$1 -e      : execute shell in last processed namespace"
  echo "$1 -l      : list namespaces"
  echo "$1 -o <num>: open shell in namespace \"ue<num>\""
}

prog_name=$(basename $0)

if [[ $(id -u) -ne 0 ]] ; then echo "Please run as root"; exit 1; fi
if [[ $# -eq 0 ]]; then echo "error: no parameters given"; usage $prog_name; exit 1; fi

while getopts c:d:ehlo: cmd
do
  case "${cmd}" in
    c) create_namespace ${OPTARG};;
    d) delete_namespace ${OPTARG};;
    e) open_namespace; exit;;
    h) usage ${prog_name}; exit;;
    l) list_namespaces;;
    o) ue_id=${OPTARG}; open_namespace;;
    /?) echo "Invalid option"; usage ${prog_name}; exit;;
  esac
done  
