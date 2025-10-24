#!/bin/bash

# --- Configuration (Set your values once here) ---

# Replace with the actual IP/hostname if Jenkins isn't on the same machine (not local)
JENKINS_URL="http://localhost:8080"
# CRITICAL: This secret will change if you delete and recreate the node in Jenkins!
SECRET="9b210d1cc9cd85e86f2bf1ee77f6983de58263cad2416e3f0cb4c9fc3d8f932a"
AGENT_NAME="docker-deploy-host"
WORK_DIR="/home/pc/workspace"

# --- Script Execution ---

echo "Starting Jenkins Agent..."

# 1. Download agent.jar (suppress output with -s)
echo "Downloading agent.jar..."
curl -sO "${JENKINS_URL}/jnlpJars/agent.jar"

# 2. Launch the agent
echo "Connecting agent to Jenkins controller..."
java -jar agent.jar \
     -url "${JENKINS_URL}/" \
     -secret "${SECRET}" \
     -name "${AGENT_NAME}" \
     -webSocket \
     -workDir "${WORK_DIR}"
