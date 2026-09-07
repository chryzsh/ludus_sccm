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
# Per-student Ubuntu attack workstations for the workshop. Not
# domain-joined; students SSH in and use them as an attack platform
# against the SCCM hierarchy. Provisioned by
# misc_provision_ubuntu_students.yml. Default connection user is
# `ansible` (the account baked into the ubuntu-2604-template with the
# ~/opt/keys/id_ecdsa authorized_keys), not `ubuntu`.
STUDENTS_TIER = {f"ubuntu-student{i:02d}" for i in range(1, 13)}


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
    student_hosts = sorted(h for h in STUDENTS_TIER if h in vms)

    # Group-vars for the student tier: SSH via the ecdsa key baked into
    # the Ubuntu template. Ansible connects as `ubuntu` (the cloud-image
    # default user) for the initial bootstrap; the provisioning playbook
    # creates the per-VM studentNN account and enables password auth,
    # but ansible itself keeps using the key + `ubuntu` user for
    # subsequent runs (deterministic, key auth beats password auth for
    # automation).
    students_block = ""
    if student_hosts:
        students_block = (
            # `ansible_password` is set at group_vars/all scope for
            # the Windows WinRM tier. It leaks into the SSH connection
            # for these ubuntu hosts unless overridden AT A HIGHER
            # PRECEDENCE than group_vars/all — inline inventory vars
            # aren't enough. Any playbook targeting students_tier must
            # override `ansible_password: ""` at play level (see
            # misc_provision_ubuntu_students.yml). Key-only auth here.
            "    students_tier:\n"
            "      vars:\n"
            "        ansible_connection: ssh\n"
            "        ansible_user: ansible\n"
            "        ansible_port: 22\n"
            "        ansible_ssh_private_key_file: ~/opt/keys/id_ecdsa\n"
            "        ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=publickey'\n"
            "        ansible_python_interpreter: /usr/bin/python3\n"
            "        ansible_become: true\n"
            "        ansible_become_method: sudo\n"
            "      hosts:\n"
        )
        for h in student_hosts:
            info = vms.get(h)
            if not info or not info.get("ip"):
                students_block += f"        {h}:  # WARNING: no IP in tfstate for {h}\n"
            else:
                students_block += f"        {h}:\n          ansible_host: {info['ip']}\n"

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
        + students_block
        + "    domain_controllers:\n"
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
