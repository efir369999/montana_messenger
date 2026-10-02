#!/bin/bash
# Watchdog, every 2 minutes from cron: Xray must be active and listening on its port, otherwise restart.
LOG=/var/log/xray-guardian.log
if ! systemctl is-active --quiet xray || ! ss -tln 2>/dev/null | grep -q ":__PORT__ "; then
  printf '%s xray down or not listening on __PORT__, restart\n' "$(date -u +%Y-%m-%dT%H:%M)" >> "$LOG"
  systemctl restart xray
fi
