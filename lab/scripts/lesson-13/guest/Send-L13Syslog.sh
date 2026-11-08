#!/bin/bash
# Runs on vm-logfwd-shared-001 through Run Command. Sends one labeled Syslog message and one labeled
# CEF message to the forwarder's own listener on 127.0.0.1:514, the way an appliance on the network
# would. user.warning matches the Syslog DCR; local4 matches only the CEF DCR.
# Both messages are synthetic and say so.
set -e
logger -p user.warning -n 127.0.0.1 -P 514 --rfc3164 -t servicehub-maint "SC500-L13 synthetic syslog marker=__MARKER__ case=SR-1042 host=vm-maint-01 action=maintenance-window-open"
logger -p local4.warn -n 127.0.0.1 -P 514 --rfc3164 -t CEF "0|Contoso|ServiceHubGateway|1.0|SC500-L13|Parts export gateway test|5|src=203.0.113.24 suser=svc-parts-export cs1Label=Marker cs1=__MARKER__ msg=SC500-L13 synthetic CEF"
echo "sent syslog and CEF with marker __MARKER__ at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
