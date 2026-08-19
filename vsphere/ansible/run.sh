#!/usr/bin/env bash
# Thin wrapper around ansible-playbook that ensures pywinrm doesn't
# route WinRM traffic through a corporate outbound proxy when the lab
# lives on RFC1918 space.
#
# Ansible/pywinrm/requests will honor the http_proxy env var by default.
# Its NO_PROXY parser is finicky about IP CIDRs vs. shorthand ("10."),
# so we prepend all three RFC1918 blocks explicitly. Nothing here is
# target-specific — the CIDRs are constants defined in RFC1918.
#
# Usage: ./run.sh <playbook> [ansible-playbook args...]
#     e.g. ./run.sh 00_connectivity.yml --limit '!ps1-dev'

set -euo pipefail

RFC1918="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

if [ -n "${NO_PROXY:-}" ]; then
    NO_PROXY="${RFC1918},${NO_PROXY}"
else
    NO_PROXY="${RFC1918}"
fi

if [ -n "${no_proxy:-}" ]; then
    no_proxy="${RFC1918},${no_proxy}"
else
    no_proxy="${RFC1918}"
fi

export NO_PROXY no_proxy

cd "$(dirname "$0")"
exec ansible-playbook "$@"
