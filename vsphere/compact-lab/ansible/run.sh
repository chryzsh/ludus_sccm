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
# Dispatches to ansible-playbook or ansible depending on the first
# argument, so both playbook runs and the ad-hoc one-liners in
# docs/workshop-oncall.md work through the same proxy-safe wrapper.
#
# Usage: ./run.sh <playbook.yml> [ansible-playbook args...]
#     e.g. ./run.sh 00_connectivity.yml --limit '!ps1-dev'
#        ./run.sh -m <module> -a '<args>' <host-or-group>
#     e.g. ./run.sh -m ansible.windows.win_ping dc

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
# A playbook invocation names a .yml/.yaml file first; anything else is
# ad-hoc (-m/-a/--list-hosts/...) and belongs to `ansible`, which does
# not accept ansible-playbook's argument shape.
case "${1:-}" in
    *.yml|*.yaml) exec ansible-playbook "$@" ;;
    *)            exec ansible "$@" ;;
esac
