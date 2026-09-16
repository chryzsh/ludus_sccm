#!/usr/bin/env python3
"""Generate the slab Ansible inventory from terraform state.

Reads `../terraform/terraform.tfstate`, extracts each
`vsphere_virtual_machine.slab_vm[<key>]` resource, and emits an Ansible
YAML inventory to `inventory.yml`.

Inventory hostnames are the FULL VM names (slab-dc, slab-pss, slab-db),
which also match the Windows computer names set by guest customization.
This keeps role-var references (e.g. ludus_sccm_site_server_hostname:
'slab-pss') consistent across ansible inventory, Windows names, and
computer-account references like SLAB\\slab-pss$.

The output file is gitignored — it contains real IPs. Do not commit it.

Usage:
    cd vsphere/small-lab/ansible
    python3 sync_inventory.py

Options:
    --state <path>       Alternate terraform state file
    --out <path>         Alternate inventory output path
    --domain <fqdn>      Domain FQDN, defaults to slab.lab
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


# Inventory groups organised by role. Keys are the FULL VM names (which
# are also the Windows computer names).
SLAB_HOSTS = {"slab-dc", "slab-pss", "slab-db"}


def _extract_vms(state: dict) -> dict[str, dict]:
    """Return {full_vm_name: {ip}} from terraform state.

    Uses the guest-customization IP (what we told terraform to set), not
    the runtime-observed IP — the runtime value can be blank when VMware
    Tools didn't respond in time.
    """
    out: dict[str, dict] = {}
    for resource in state.get("resources", []):
        if resource.get("type") != "vsphere_virtual_machine":
            continue
        if resource.get("name") != "slab_vm":
            continue
        for instance in resource.get("instances", []):
            attrs = instance.get("attributes", {})
            name = attrs.get("name")
            if not name:
                continue
            clone = (attrs.get("clone") or [{}])[0]
            customize = (clone.get("customize") or [{}])[0]
            net = (customize.get("network_interface") or [{}])[0]
            ip = net.get("ipv4_address") or ""
            out[name] = {"ip": ip}
    return out


def _emit_inventory(vms: dict[str, dict], domain: str) -> str:
    def _hostblock(name: str, indent: str = "        ") -> str:
        info = vms.get(name)
        if not info or not info.get("ip"):
            return f"{indent}{name}:  # WARNING: no IP in tfstate for {name} — check terraform apply output\n"
        return f"{indent}{name}:\n{indent}  ansible_host: {info['ip']}\n"

    slab_hosts = [h for h in sorted(SLAB_HOSTS) if h in vms]

    slab_block = "    slab_tier:\n      hosts:\n"
    for h in slab_hosts:
        slab_block += _hostblock(h)

    return (
        "# GENERATED FILE — do not commit. Regenerate with sync_inventory.py.\n"
        "all:\n"
        "  vars:\n"
        "    ansible_user: Administrator\n"
        "    ansible_connection: winrm\n"
        "    ansible_winrm_transport: ntlm\n"
        "    ansible_winrm_server_cert_validation: ignore\n"
        "    ansible_port: 5985\n"
        f"    ludus_domain_fqdn: {domain}\n"
        "  children:\n"
        f"{slab_block}"
        "    domain_controllers:\n"
        "      hosts:\n"
        f"{_hostblock('slab-dc')}"
        "    sccm_site_servers:\n"
        "      hosts:\n"
        f"{_hostblock('slab-pss')}"
        "    sccm_sql_servers:\n"
        "      hosts:\n"
        f"{_hostblock('slab-db')}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--state",
        default=str(Path(__file__).parent.parent / "terraform" / "terraform.tfstate"),
        help="Path to terraform.tfstate",
    )
    parser.add_argument(
        "--out",
        default=str(Path(__file__).parent / "inventory.yml"),
        help="Inventory output path",
    )
    parser.add_argument("--domain", default="slab.lab", help="Domain FQDN")
    args = parser.parse_args()

    state_path = Path(args.state)
    if not state_path.is_file():
        print(f"terraform state file not found: {state_path}", file=sys.stderr)
        return 1

    with state_path.open() as fh:
        state = json.load(fh)

    vms = _extract_vms(state)
    if not vms:
        print("No slab_vm resources found in state", file=sys.stderr)
        return 2

    content = _emit_inventory(vms, args.domain)

    out_path = Path(args.out)
    out_path.write_text(content)
    print(f"wrote {out_path} ({len(vms)} VMs)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
