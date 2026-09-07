# Spec: Give the NAA a "Script Approvers" role to unlock EXEC-2

Finalized 2026-09-07 for workshop 2026-09-17. Supersedes the earlier
draft. Ready for the inventory agent (with access to
`/home/chrisr/share/forks/ludus_sccm` and the Ludus range) to execute.

## Goal

Make EXEC-2 (SCCM Run Scripts abuse) a reachable attack path in the
lab, chained from credential access to the Network Access Account
(NAA) via CRED-1/CRED-3. The NAA currently has no SCCM RBAC rights.
This spec adds a custom "Script Approvers" security role and grants
it to the NAA account.

This is a code change to the `mayyhem.ludus_sccm` Ansible collection
at `/home/chrisr/share/forks/ludus_sccm`, not a live-lab change. The
inventory agent must apply the Ansible changes below, run the
collection against the lab (or a fresh deploy), and confirm the role
shows up correctly in the SCCM console and via SCCMHunter /
AdminService.

## Design decisions (do not re-litigate)

- **Role granted to NAA**: a custom "Script Approvers" role, not
  Full Administrator. Matches Microsoft's documented role and the
  EXEC-2 "custom role" requirement, so the student has to discover a
  script has been staged and approved rather than finding a
  fully-privileged NAA.
- **Two-cred chain is intentional**: NAA (from CRED-1/CRED-3 in this
  workshop) approves; a separate Full Administrator account (from
  TAKEOVER-1 in the previous lab) executes. That is the narrative,
  not a gap. Do NOT add "Collection: Run Script" to the role to
  short-circuit this — leaving execution out is the whole pedagogical
  point of chaining the two labs.
- **Opt-in, not default-on**: this repo is a published Galaxy
  collection used by others. New behavior gated on a variable
  defaulting to `false` in `roles/install_primary_site/defaults/main.yml`
  and turned on explicitly in this lab's `new-config.yml`.
- **Only the NAA is in scope.** CRED-6 / TAKEOVER-1 alternate paths
  are out of scope for this spec.

## Verified facts (Microsoft Learn, 2026-09-07)

Microsoft's Script Approvers role
(learn.microsoft.com/en-us/mem/configmgr/apps/deploy-use/create-deploy-scripts#bkmk_ScriptRoles)
defines these permissions:

- Site: Read = Yes
- SMS Scripts: Read = Yes
- SMS Scripts: Approve = Yes
- SMS Scripts: Modify = Yes
- Collection: Run Script = No

This is the permission set to apply. Microsoft's own named role — not
a lab invention.

PowerShell cmdlets confirmed via Learn (`ConfigurationManager` module):

- `Copy-CMSecurityRole -Name <newname> -SourceRoleName <existingname> [-Description]`
  creates a custom role by copying an existing one. **Note**: the
  copy inherits every permission the source role has. The source
  we use, `Read-only Analyst`, has Read across most categories.
  Explicit zero-out is not done here (see design decision below).
- `Set-CMSecurityRolePermission -Name <rolename> -RolePermission <hashtable>`
  where the hashtable's keys are permission-category names (e.g.
  `"Site"`, `"SMS Scripts"`) and values are comma-separated
  permission names (e.g. `"Read,Approve,Modify"`). Treat it as "sets
  these permissions to Yes" — it does not clear anything not named.
- `New-CMAdministrativeUser -Name 'DOMAIN\user' -RoleName <name> [-SecurityScopeName <name>] [-CollectionName <name>]`
  — creates a new SCCM administrative user. `RoleName` accepts
  built-in or custom.
- `Get-CMAdministrativeUser -Name 'DOMAIN\user'` — returns an object
  with a `RoleNames` string-array property (backed by SMS_Admin WMI).
- `Add-CMSecurityRoleToAdministrativeUser -AdministrativeUserName 'DOMAIN\user' -RoleName <name>`
  — adds a role to an admin user that already exists.

### On the "role breadth" tradeoff

The resulting role has Read-only Analyst's whole read footprint PLUS
SMS Scripts Approve/Modify. That is broader than Microsoft's narrow
four-bit definition, but:

1. No built-in role is "narrower than Read-only Analyst," so any
   `Copy-CMSecurityRole` source lands at least this wide.
2. Explicit zero-out via `Set-CMSecurityRolePermission` is not
   confirmed to clear un-named categories (docs are ambiguous).
3. For the lab, a stolen NAA that can enumerate collections/apps is
   MORE interesting to a student, not less.

Decision: keep the broader footprint; be honest about it in the
module `description:` and the `Copy-CMSecurityRole -Description`
text. The role name stays "Script Approvers" (workshop-discoverable
Microsoft-branded name); the description text says it's Approver
perms on top of Read-only Analyst's read surface.

## Codebase facts (target fork)

- No existing module or task touches SCCM RBAC. `naa.py`/`naa.ps1`
  only sets the NAA property list. `cmaccounts.py`/`cmaccounts.ps1`
  only creates a CMAccount (unrelated to RBAC).
  `add_accounts_to_admins` only touches the local Windows
  Administrators group.
- Module pattern (see `plugins/modules/naa.ps1`, `cmaccounts.ps1`,
  `discovery_methods.ps1`): a `.py` file with just
  `DOCUMENTATION`/`EXAMPLES` strings, and a `.ps1` file that builds
  `Ansible.Basic.AnsibleModule`, imports `ConfigurationManager.psd1`,
  connects to the CMSite PSDrive for `$module.Params.site_code`, does
  the work, calls `$module.ExitJson()`. Existing modules always
  report `unchanged` regardless of what they did — match this
  convention for consistency (do NOT fix here).
- `roles/install_primary_site/tasks/main.yml` includes `config_naa.yml`
  gated on `when: ludus_sccm_configure_naa == true` (around line
  152–156). New logic goes right after that with its own when gate so
  it can be toggled independently.
- Defaults in `roles/install_primary_site/defaults/main.yml`. NAA
  section at the top (lines 7–10).
- `new-config.yml` — NAA is configured on PS1 (the ps1-pss VM's
  `install_primary_site` role_vars block ~lines 611–631), not on
  CAS. CAS explicitly sets `ludus_sccm_configure_naa: false`.
- No dict-typed module options anywhere in this collection. Hardcode
  the permission hashtable inside the module, matching how `naa.ps1`
  hardcodes its own WMI property name.

## Changes

### 1. `plugins/modules/create_script_approver_role.py`

```python
DOCUMENTATION = r'''
---
module: create_script_approver_role
short_description: Create the "Script Approvers" custom SCCM security role
version_added: "1.0.7"

description:
  - Creates a custom SCCM security role granting SMS Scripts Approve and
    Modify permissions on top of the Read-only Analyst role's read surface.
    Matches Microsoft's documented Script Approvers role on the SMS Scripts
    axis; broader on the read surface because Copy-CMSecurityRole inherits
    the source role's full permission set and Set-CMSecurityRolePermission
    does not clear un-named categories.
  - On subsequent runs the permission hashtable is reconciled onto the role
    unconditionally, so editing the hardcoded permission set in this module
    and re-deploying will update an existing role in the lab.

options:
    name:
        description:
        - Name of the custom security role to create.
        required: true
        type: string
    source_role_name:
        description:
        - Built-in security role to copy as the starting point.
        required: false
        type: string
        default: 'Read-only Analyst'
    site_code:
        description:
        - Site code of the SCCM deployment.
        type: string
        required: true

author:
    - chryzsh
'''

EXAMPLES = r'''
- name: Create Script Approvers security role
  mayyhem.ludus_sccm.create_script_approver_role:
    name: 'Script Approvers'
    site_code: 'PS1'
'''
```

### 2. `plugins/modules/create_script_approver_role.ps1`

Change from the original draft: after the create branch, always call
`Set-CMSecurityRolePermission` unconditionally, so re-runs reconcile
the current hashtable onto the role (guards against drift from a
partial prior run and picks up permission edits in later versions of
this module without a manual delete).

```powershell
#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

$spec = @{
    options = @{
        name = @{ type = 'str'; required = $true }
        source_role_name = @{ type = 'str'; required = $false; default = 'Read-only Analyst' }
        site_code = @{ type = 'str'; required = $true }
    }
    supports_check_mode = $true
}
$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

Import-Module "C:\\Program Files (x86)\\Microsoft Configuration Manager\\AdminConsole\\bin\\ConfigurationManager.psd1"

if ((Get-PSDrive -Name $module.Params.site_code -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null)
{
    $ProviderMachineName = (Get-ItemProperty 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\ConfigMgr10\AdminUI\Connection' -Name Server).Server
    New-PSDrive -Name $module.Params.site_code -PSProvider CMSite -Root $ProviderMachineName
}

Set-Location "$($module.Params.site_code):\"

# Matches Microsoft's documented "Script Approvers" role on the SMS Scripts axis:
# https://learn.microsoft.com/en-us/mem/configmgr/apps/deploy-use/create-deploy-scripts#bkmk_ScriptRoles
# The read surface is broader (Read-only Analyst's full read footprint) because
# Copy-CMSecurityRole inherits the source role's permissions and Set-CMSecurityRolePermission
# does not clear un-named categories. Acceptable for lab use.
$scriptApproverPermissions = @{
    "Site"        = "Read"
    "SMS Scripts" = "Read,Approve,Modify"
}

$role = Get-CMSecurityRole -Name $module.Params.name -ErrorAction SilentlyContinue

if (-not $role) {
    Copy-CMSecurityRole -Name $module.Params.name -SourceRoleName $module.Params.source_role_name -Description "SMS Scripts Approve/Modify on top of Read-only Analyst read surface. Lab role for the EXEC-2 attack path."
    $role = Get-CMSecurityRole -Name $module.Params.name
}

# Reconcile the current permission set onto the role every run.
$role | Set-CMSecurityRolePermission -RolePermission $scriptApproverPermissions

$module.ExitJson()
```

### 3. `plugins/modules/add_administrative_user.py`

```python
DOCUMENTATION = r'''
---
module: add_administrative_user
short_description: Add a domain account as an SCCM administrative user
version_added: "1.0.7"

description:
  - Adds a domain user or group as an SCCM administrative user with a given
    security role (built-in or custom).
  - Idempotent: if the account is already an administrative user with the
    role, no changes are made. If the account exists as an administrative
    user without the role, the role is added to it.

options:
    name:
        description:
        - Domain account or group to add, e.g. 'DOMAIN\username'.
        required: true
        type: string
    role_name:
        description:
        - Security role name to assign.
        required: true
        type: string
    site_code:
        description:
        - Site code of the SCCM deployment.
        type: string
        required: true
    security_scope_name:
        description:
        - Security scope for a newly created administrative user. Ignored
          if the administrative user already exists.
        type: string
        required: false
        default: 'All'

author:
    - chryzsh
'''

EXAMPLES = r'''
- name: Grant Script Approvers role to the Network Access Account
  mayyhem.ludus_sccm.add_administrative_user:
    name: 'DOMAIN\networkaccess'
    role_name: 'Script Approvers'
    site_code: 'PS1'
'''
```

### 4. `plugins/modules/add_administrative_user.ps1`

```powershell
#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

$spec = @{
    options = @{
        name = @{ type = 'str'; required = $true }
        role_name = @{ type = 'str'; required = $true }
        site_code = @{ type = 'str'; required = $true }
        security_scope_name = @{ type = 'str'; required = $false; default = 'All' }
    }
    supports_check_mode = $true
}
$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

Import-Module "C:\\Program Files (x86)\\Microsoft Configuration Manager\\AdminConsole\\bin\\ConfigurationManager.psd1"

if ((Get-PSDrive -Name $module.Params.site_code -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null)
{
    $ProviderMachineName = (Get-ItemProperty 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\ConfigMgr10\AdminUI\Connection' -Name Server).Server
    New-PSDrive -Name $module.Params.site_code -PSProvider CMSite -Root $ProviderMachineName
}

Set-Location "$($module.Params.site_code):\"

$adminUser = Get-CMAdministrativeUser -Name $module.Params.name -ErrorAction SilentlyContinue

if (-not $adminUser) {
    New-CMAdministrativeUser -Name $module.Params.name -RoleName $module.Params.role_name -SecurityScopeName $module.Params.security_scope_name
    $module.ExitJson()
} elseif ($adminUser.RoleNames -notcontains $module.Params.role_name) {
    Add-CMSecurityRoleToAdministrativeUser -AdministrativeUserName $module.Params.name -RoleName $module.Params.role_name
    $module.ExitJson()
} else {
    $module.ExitJson()
}
```

### 5. `roles/install_primary_site/tasks/config_naa_admin.yml`

**IMPORTANT**: match the sibling `config_naa.yml`'s `ansible_become_user`
convention exactly — do not diverge. `grep ansible_become_user
roles/install_primary_site/tasks/config_naa.yml` in the mayyhem fork
FIRST and mirror it (netbios or fqdn — whichever it uses). The example
below shows `ludus_domain_netbios_name`; if the fork's `config_naa.yml`
uses `ludus_domain_fqdn`, change both `vars:` blocks to match.

```yaml
---
- name: Create Script Approvers security role
  mayyhem.ludus_sccm.create_script_approver_role:
    name: '{{ ludus_sccm_script_approver_role_name }}'
    source_role_name: '{{ ludus_sccm_script_approver_source_role }}'
    site_code: '{{ ludus_sccm_sitecode }}'
  vars:
    ansible_become: true
    ansible_become_method: runas
    ansible_become_user: '{{ ludus_domain_netbios_name }}\{{ defaults.ad_domain_admin }}'
    ansible_become_password: '{{ defaults.ad_domain_admin_password }}'
    ansible_become_flags: "logon_type=interactive logon_flags=with_profile"

- name: Grant Script Approvers role to the Network Access Account
  mayyhem.ludus_sccm.add_administrative_user:
    name: '{{ ludus_domain_netbios_name }}\{{ ludus_sccm_naa_username }}'
    role_name: '{{ ludus_sccm_script_approver_role_name }}'
    site_code: '{{ ludus_sccm_sitecode }}'
  vars:
    ansible_become: true
    ansible_become_method: runas
    ansible_become_user: '{{ ludus_domain_netbios_name }}\{{ defaults.ad_domain_admin }}'
    ansible_become_password: '{{ defaults.ad_domain_admin_password }}'
    ansible_become_flags: "logon_type=interactive logon_flags=with_profile"
```

### 6. Edit `roles/install_primary_site/tasks/main.yml`

Right after the existing NAA block (currently ~lines 152–156):

```yaml
# Start NAA Configuration--------------------------------------------------------------
- name: Begin NAA Configuration
  ansible.builtin.include_tasks:
    file: config_naa.yml
  when: ludus_sccm_configure_naa == true
```

add:

```yaml
# Grant EXEC-2 lab path: Script Approvers role to NAA-----------------------------------
- name: Grant Script Approver role to Network Access Account (EXEC-2 lab path)
  ansible.builtin.include_tasks:
    file: config_naa_admin.yml
  when:
    - ludus_sccm_configure_naa == true
    - ludus_sccm_naa_grant_script_approver | default(false) == true
```

### 7. Edit `roles/install_primary_site/defaults/main.yml`

Change lines 7–10 from:

```yaml
#--------------------------Network Access Account--------------------------------
ludus_sccm_configure_naa: true
ludus_sccm_naa_username: 'networkaccess'
ludus_sccm_naa_password: 'Password123'
```

to:

```yaml
#--------------------------Network Access Account--------------------------------
ludus_sccm_configure_naa: true
ludus_sccm_naa_username: 'networkaccess'
ludus_sccm_naa_password: 'Password123'
# EXEC-2 lab path: grant the NAA a custom "Script Approvers" role (Site: Read; SMS
# Scripts: Read, Approve, Modify; no Run Script/Create/Delete) so credential access to
# the NAA (CRED-1/CRED-3) leads to script-approval rights usable toward EXEC-2.
# Execution requires a separate account (in the workshop: a Full Administrator obtained
# via TAKEOVER-1 in the previous lab). Off by default; deliberate lab misconfiguration,
# not stock SCCM behavior, and this collection is published for other users.
ludus_sccm_naa_grant_script_approver: false
ludus_sccm_script_approver_role_name: 'Script Approvers'
ludus_sccm_script_approver_source_role: 'Read-only Analyst'
```

### 8. Edit `new-config.yml`

In the PS1-PSS entry's `role_vars` block (~lines 611–631, starting
`ludus_sccm_parent_sitecode: 'CAS'`), add:

```yaml
      ludus_sccm_naa_grant_script_approver: true
```

Do NOT add to the CAS block — CAS already sets
`ludus_sccm_configure_naa: false`, and NAA is only meaningfully
configured on PS1 in this topology.

## What the inventory agent needs to do

1. **Mirror the become-user convention.** Grep
   `roles/install_primary_site/tasks/config_naa.yml` in the mayyhem
   fork for `ansible_become_user`. Whatever it uses (netbios or fqdn),
   use the same in `config_naa_admin.yml`. Do not diverge.
2. **Apply the file changes above.**
3. **Deploy** the collection to the lab (or re-run against the
   existing range so PS1 picks up the new `install_primary_site`
   tasks).
4. **Confirm in the SCCM console** (Administration → Security →
   Security Roles): "Script Approvers" exists; NAA account appears
   under Administrative Users with that role.
5. **End-to-end EXEC-2 verification across two creds:**
   a. **As NAA** (`MAYYHEM\networkaccess` / `Password123`), use
      SCCMHunter's `script` command (or a direct AdminService call)
      to approve a script. Confirm approval succeeds.
   b. **As the TAKEOVER-1 Full Administrator account**, execute the
      approved script against a target collection. Confirm it runs.
   c. If (a) fails, it's a real bug in this RBAC change — flag back.
   d. If (b) fails, that's a TAKEOVER-1 regression, not this spec's
      problem — flag back separately.
6. **Sanity check** that this doesn't collide with anything else
   already granted to the NAA in the lab (nothing at time of writing).
7. **Report back**: workshop-relevant summary — the exact SCCMHunter
   command used, one line of output showing the successful
   approve+execute chain, and any deviations from this spec.

## Explicitly out of scope

- Fixing the collection-wide `changed` reporting bug (all modules
  report `unchanged`).
- Fixing the collection-wide `supports_check_mode = $true` lie (no
  module gates mutations on `$module.CheckMode`).
- Adding "Collection: Run Script" to the hashtable to close the
  execution gap in a single cred. The two-cred chain (NAA approve +
  TAKEOVER-1 Full Admin execute) is the intended workshop narrative.
- Alternate paths via CRED-6 / TAKEOVER-1 accounts (out of scope per
  the original spec).
