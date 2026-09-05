#!/usr/bin/env python3
"""Generate the Ansible inventory from terraform state.

Mirrors the shape of GOAD's `goad/provider/terraform/vsphere.py::_sync_inventory_hosts_from_tfstate`.

Reads `../terraform/terraform.tfstate`, extracts each `vsphere_virtual_machine.mayyhem_vm[<key>]`
resource, and emits an Ansible YAML inventory to `inventory.yml`.

The output file is gitignored — it contains real IPs. Do not commit it.

Usage:
    cd vsphere/ansible
    python3 sync_inventory.py

Options:
    --state <path>       Alternate terraform state file
    --out <path>         Alternate inventory output path
    --domain <fqdn>      Domain FQDN, defaults to mayyhem.com
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


CAS_TIER = {"dc", "cas-db", "cas-scp", "cas-pss"}
PS1_TIER = {
    "ps1-db",
    "ps1-lib",
    "ps1-psv",
    "ps1-dp",
    "ps1-mp",
    "ps1-sms",
    "ps1-pss",
    "ps1-dev",
    "ps1-sec",
    "ps1-lab",
}
# Non-SCCM systems used to simulate a third-party integration for
# TAKEOVER-9 lab reproduction. See docs/takeover-9-lab-plan.md.
THIRD_PARTY_TIER = {"monitor"}


def _extract_vms(state: dict) -> dict[str, dict]:
    """Return {hostname_key: {full_name, ip}} from terraform state.

    Extracts static-config IP from the guest customization block (the value
    we asked terraform to set), NOT the runtime-observed IP. Runtime IP can
    be blank when VMware Tools didn't respond in time (see ps1-dev), but
    the customization value is what we told the VM to use.
    """
    out: dict[str, dict] = {}
    for resource in state.get("resources", []):
        if resource.get("type") != "vsphere_virtual_machine":
            continue
        if resource.get("name") != "mayyhem_vm":
            continue
        for instance in resource.get("instances", []):
            key = instance.get("index_key")
            attrs = instance.get("attributes", {})
            if not key or not attrs:
                continue
            clone = (attrs.get("clone") or [{}])[0]
            customize = (clone.get("customize") or [{}])[0]
            net = (customize.get("network_interface") or [{}])[0]
            ip = net.get("ipv4_address") or ""
            out[key] = {
                "full_name": attrs.get("name") or key,
                "ip": ip,
            }
    return out


def _emit_inventory(vms: dict[str, dict], domain: str) -> str:
    def _hostblock(name: str) -> str:
        info = vms.get(name)
        if not info or not info.get("ip"):
            return f"        {name}:  # WARNING: no IP in tfstate for {name} — check terraform apply output\n"
        return f"        {name}:\n          ansible_host: {info['ip']}\n"

    def _group(name: str, hosts: list[str]) -> str:
        s = f"    {name}:\n      hosts:\n"
        for h in hosts:
            s += _hostblock(h)
        return s

    cas_hosts = [h for h in CAS_TIER if h in vms]
    ps1_hosts = [h for h in PS1_TIER if h in vms]
    tp_hosts = [h for h in THIRD_PARTY_TIER if h in vms]

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
        + (_group('third_party_tier', tp_hosts) if tp_hosts else '')
        + f"{_group('cas_tier', cas_hosts)}"
        f"{_group('ps1_tier', ps1_hosts)}"
        "    domain_controllers:\n"
        "      hosts:\n"
        f"{_hostblock('dc')}"
        "    sccm_site_servers:\n"
        "      hosts:\n"
        f"{_hostblock('cas-pss')}"
        f"{_hostblock('ps1-pss')}"
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
    parser.add_argument("--domain", default="mayyhem.com", help="Domain FQDN")
    args = parser.parse_args()

    state_path = Path(args.state)
    if not state_path.is_file():
        print(f"terraform state file not found: {state_path}", file=sys.stderr)
        return 1

    with state_path.open() as fh:
        state = json.load(fh)

    vms = _extract_vms(state)
    if not vms:
        print("No mayyhem_vm resources found in state", file=sys.stderr)
        return 2

    content = _emit_inventory(vms, args.domain)

    out_path = Path(args.out)
    out_path.write_text(content)
    print(f"wrote {out_path} ({len(vms)} VMs)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
