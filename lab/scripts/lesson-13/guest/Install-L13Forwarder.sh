#!/bin/bash
# Runs on vm-logfwd-shared-001 as root through Run Command (Deploy-L13Lab.ps1 -Deploy).
# Applies Microsoft's documented AMA forwarder script, which configures rsyslog to listen on
# port 514 (UDP and TCP) and hand messages to the Azure Monitor Agent. Run it after the agent and
# the DCRs exist, which main.bicep guarantees. Idempotent: the script rewrites the same files.
set -e
cd /tmp
wget -q -O Forwarder_AMA_installer.py https://raw.githubusercontent.com/Azure/Azure-Sentinel/master/DataConnectors/Syslog/Forwarder_AMA_installer.py
echo "installer sha256 $(sha256sum Forwarder_AMA_installer.py | cut -d' ' -f1)"
python3 Forwarder_AMA_installer.py
sleep 5
echo "--- listening sockets (514 is rsyslog, 28330 is the agent)"
ss -lnp | grep -E ":514 |:28330 " || echo "no listener found"
echo "--- azuremonitoragent: $(systemctl is-active azuremonitoragent || true)"
echo "--- rsyslog: $(systemctl is-active rsyslog || true)"
