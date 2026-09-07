# Spec: CRED-6 file-loot plant on ps1-dp

Finalized 2026-09-07 for workshop 2026-09-17. Plants a non-default
SMB share on the primary distribution point with a hardcoded-cred
PowerShell utility, so CRED-6 (loot creds from SCCM Distribution
Points and other site server shares) becomes a productive attack
path in this lab.

## Goal

Make CRED-6 hit for real. Stock SCCM plus this lab's baseline leaves
nothing loot-able on the DP or site server — CMLoot / sccm-http-looter
returns package content only (WIM images, boot media), no scripts, no
config files, no hardcoded credentials. This plant follows the "IT
engineer left creds in an automation script" pattern the CRED-6 doc
calls out as a real-world example, so the technique executes
end-to-end against something a student can actually pivot from.

## Design decisions (do not re-litigate)

- **Host: ps1-dp** (primary distribution point). Rationale: CRED-6
  is framed around DP loot first ("Loot domain credentials … from
  SCCM Distribution Points and other site server shares"), so a
  student running the technique targets the DP by mental model.
  Planting on ps1-pss (site server) or ps1-lib (content library)
  would still hit under the "Other Site Server Shares" bullet, but
  the DP is the on-technique location.
- **Share name: `Scripts`.** Common non-default share seen on real
  SCCM site systems. Stands out against the RECON-2 baseline share
  list without screaming "workshop lure."
- **Domain-authenticated read access** (`MAYYHEM\Domain Users` read,
  `BUILTIN\Administrators` full). Matches the CRED-6 doc's
  authenticated-SMB example (`cmloot.py .../domainuser`). Not
  anonymous — a student needs at least one domain cred first.
- **Payoff account: `MAYYHEM\svc_sccm_maint`, local admin on
  `ps1-dev` only.** Option B from the design discussion. Reasons:
  most real-ops-plausible (least-privilege service account for a
  specific automation), doesn't duplicate TAKEOVER-1's endgame, and
  chains cleanly into the next workshop attack (once on ps1-dev,
  extract NAA cache → back into the SCCM chain via CRED-1/CRED-3).
- **Password: `Password123!`.** Committable — new lab-created string,
  not tied to any operator credential. Note the trailing `!` to
  differentiate from the default `Password123` sprinkled through the
  collection.
- **Implementation: single `misc_*` playbook, no collection
  changes.** Matches other lab-specific one-offs
  (`misc_enforce_smb_signing_ps1_sec.yml`,
  `misc_workshop_prep_ps1_lab.yml`). Not a stock collection feature
  because the plant is deliberately lab-narrative-specific.

## Verified facts

- `roles/create_demo_users/tasks/main.yml` demonstrates the
  established pattern for creating an AD user (`microsoft.ad.user`
  with `delegate_to: "{{ ludus_dc_vm_name }}"` + runas to the domain
  admin) and adding to local groups (`ansible.windows.win_group_membership`).
- `roles/create_contentlib_share/tasks/main.yml` demonstrates
  `ansible.windows.win_share` with per-principal `full` ACL. The
  same module supports `read` for a list-visible domain-user share.
- `vsphere/ansible/inventory.yml` maps the DC hostname `dc`, the
  Win11 client `ps1-dev`, and the distribution point `ps1-dp` to
  their lab IPs. Use `ansible-inventory -i vsphere/ansible/inventory.yml --host <name>`
  to look them up.
- `group_vars/all/local.yml` provides `defaults.ad_domain_admin` /
  `defaults.ad_domain_admin_password`. `group_vars/all/main.yml`
  provides `ludus_domain_netbios_name = MAYYHEM` and
  `ludus_dc_vm_name = dc`.

## Changes

### 1. New playbook: `vsphere/ansible/misc_plant_cred6_share.yml`

Three plays in sequence:

1. **On `dc`**: create `svc_sccm_maint` domain user via
   `microsoft.ad.user`, password `Password123!`,
   `password_never_expires: true`, description flagging it as an
   IT-Ops automation account.
2. **On `ps1-dev`**: add `MAYYHEM\svc_sccm_maint` to local
   `Administrators` group via `win_group_membership` (runas
   domainadmin).
3. **On `ps1-dp`**: create `C:\Scripts`, drop
   `Reset-SCCMClientCache.ps1` via `win_copy` with inline `content:`,
   expose as SMB share `Scripts` via `win_share`
   (`list: true`, `read: MAYYHEM\Domain Users`,
   `full: BUILTIN\Administrators`). Verify with a `win_powershell`
   read of the share list.

### 2. `Reset-SCCMClientCache.ps1` (planted content, inline in the playbook)

```powershell
# Scheduled task: Reset-SCCMClientCache
# Runs weekly on drift-prone dev machines. Owner: IT-Ops.
#
# TODO: move creds out of the script before rolling this to prod.
#       (Ticket IT-4419)

$ServiceAccount = "MAYYHEM\svc_sccm_maint"
$Password       = "Password123!"

$Target = if ($args[0]) { $args[0] } else { "ps1-dev" }

$SecPass = ConvertTo-SecureString -String $Password -AsPlainText -Force
$Cred    = New-Object System.Management.Automation.PSCredential($ServiceAccount, $SecPass)

Invoke-Command -ComputerName $Target -Credential $Cred -ScriptBlock {
    Restart-Service -Name CcmExec -Force
    Remove-Item -Path 'C:\Windows\ccmcache\*' -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service -Name CcmExec
}
```

The `# TODO: move creds out of the script before rolling this to
prod.` line is the tell. Students grepping loot for `password`,
`ConvertTo-SecureString`, or `PSCredential` hit it. Real-ops
narrative: "someone was going to fix this later. They didn't."

## Deployment

```
./run.sh misc_plant_cred6_share.yml
```

Targets `dc`, `ps1-dev`, `ps1-dp`. Idempotent: `microsoft.ad.user`,
`win_group_membership`, `win_file`, `win_share` all no-op on re-run.
`win_copy` re-copies the file if its content differs from disk.

## Verification (student-side, EXPECTED workshop demo)

```
# On any student Ubuntu box, with any domain cred.
# Substitute <PS1-DP-IP> and <PS1-DEV-IP> from the range's inventory.
smbclient.py 'mayyhem.com/domainuser:Password123@<PS1-DP-IP>'
> shares
# ... Scripts should appear in the list ...
> use Scripts
> ls
# ... Reset-SCCMClientCache.ps1 ...
> get Reset-SCCMClientCache.ps1
> exit

# Alternative: CMLoot with default extension filter picks it up too
python3 cmloot.py 'mayyhem.com/domainuser:Password123@<PS1-DP-IP>' -cmlootinventory /tmp/cred6.txt
python3 cmloot.py 'mayyhem.com/domainuser:Password123@<PS1-DP-IP>' -cmlootdownload /tmp/cred6.txt
grep -R 'Password' CMLootOut/ | head

# Verify the cred works (lateral movement to ps1-dev):
evil-winrm -i <PS1-DEV-IP> -u svc_sccm_maint -p 'Password123!'
```

## Chain positioning in the workshop

The CRED-6 loot yields `svc_sccm_maint / Password123!`, which is
local admin on `ps1-dev` only. From ps1-dev the student can then
run CRED-1/CRED-3-style NAA cache extraction (already reachable
from the previously-established client foothold, but now reachable
from a *purely-loot-driven* chain — no ELEVATE step required to
get onto ps1-dev). This gives the workshop a second, orthogonal
route into the SCCM chain that doesn't depend on any of the client
initial-access primitives.

## Gotchas

- **Share `list: true`** is required — students find the share via
  `shares` in smbclient.py. Hidden `$`-suffixed shares wouldn't
  match the CRED-6 doc's enumeration example.
- **Password can't be an operator credential** (nothing from
  `group_vars/all/local.yml`) — the plant is committed source code.
  `Password123!` is a new lab-only string.
- **`Invoke-Command` in the .ps1 needs WinRM reachable to ps1-dev**
  with `svc_sccm_maint` as local admin. Both true after this play
  runs (`windows_base` enables WinRM cluster-wide; play 2 grants
  the local-admin membership). If the student runs the script
  verbatim after looting, it actually restarts CcmExec on ps1-dev
  — a nice "the cred is real, the script works" beat.
- **`Password123!` differs from `Password123`** intentionally. If
  a student pastes the wrong string they'll get an auth failure
  and know the plant is precise.

## What the inventory agent needs to do

1. Apply the file changes above.
2. `./run.sh misc_plant_cred6_share.yml`.
3. Confirm from a student box (verification steps above).
4. Sanity-check that `svc_sccm_maint` shows up in AD with the
   expected description, and that ps1-dev's local Administrators
   group lists it.

## Explicitly out of scope

- Fixing the "32/34 techniques" coverage claim in the workshop
  material to reflect what's actually covered — that's a
  separate documentation exercise.
- Enabling `AllowClientAnonymous` on ps1-dp for a no-creds CRED-6
  demo (HTTP-only anonymous DP loot via sccm-http-looter) — could
  be a separate plant, but this spec covers only the
  authenticated-SMB path.
- Additional plants on ps1-pss / ps1-lib / ps1-mp. Ps1-dp is the
  single plant location for this spec.
