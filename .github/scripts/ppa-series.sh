#!/bin/bash
# Ubuntu releases to upload to, as "version name" lines: the stable and supported ones from 24.04 on.
# 22.04 ships fzf 0.29, older than the 0.38 cch needs. Asking Launchpad keeps the list current
# without editing this file every six months
set -euo pipefail

curl -fsSL https://api.launchpad.net/1.0/ubuntu/series | jq -r '
  .entries[]
  | select(.active and (.status == "Current Stable Release" or .status == "Supported"))
  | select((.version | split(".") | map(tonumber)) >= [24, 4])
  | "\(.version) \(.name)"'
