#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        boundary_group_name = @{ type = 'str'; required = $true }
        boundary_group_description = @{ type = 'str'; required = $true }
        site_system_server_names = @{ type = 'list'; required = $true }
        boundary = @{ type = 'str'; required = $true }
    }
    supports_check_mode = $true
}
$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

Import-Module "C:\\Program Files (x86)\\Microsoft Configuration Manager\\AdminConsole\\bin\\ConfigurationManager.psd1"

#https://www.windows-noob.com/forums/topic/16422-connect-configmgr64-function-to-connect-to-cmsite-sccm-feedback-for-improvement/
if ((Get-PSDrive -Name $module.Params.site_code -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null)
{
    $ProviderMachineName = (Get-ItemProperty 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\ConfigMgr10\AdminUI\Connection' -Name Server).Server
    New-PSDrive -Name $module.Params.site_code -PSProvider CMSite -Root $ProviderMachineName
}

Set-Location "$($module.Params.site_code):\"

$bg = Get-CMBoundaryGroup -Name $module.Params.boundary_group_name

if (-not $bg) {
    if (-not $module.CheckMode) {
        New-CMBoundaryGroup -Name $module.Params.boundary_group_name -Description $module.Params.boundary_group_description
        $bg = Get-CMBoundaryGroup -Name $module.Params.boundary_group_name
    }
    $module.Result.changed = $true
}

# Only touch DefaultSiteCode when it isn't already ours: prevents an install
# for site B from silently reassigning site A's boundary group.
if ($bg -and $bg.DefaultSiteCode -ne $module.Params.site_code) {
    if (-not $module.CheckMode) {
        Set-CMBoundaryGroup -Name $module.Params.boundary_group_name -DefaultSiteCode $module.Params.site_code
    }
    $module.Result.changed = $true
}

if (-not $module.CheckMode) {
    foreach ($server in $module.Params.site_system_server_names) {
        $get_server = Get-CMSiteSystemServer -Name $server -ErrorAction SilentlyContinue
        if ($get_server) {
            try {
                Set-CMBoundaryGroup -Name $module.Params.boundary_group_name -AddSiteSystemServer $get_server -ErrorAction Stop
                $module.Result.changed = $true
            } catch {
                # Site system already a member of the group; ignore.
            }
        }
    }

    try {
        Add-CMBoundaryToGroup -BoundaryGroupName $module.Params.boundary_group_name -BoundaryName $module.Params.boundary -ErrorAction Stop
        $module.Result.changed = $true
    } catch {
        # Boundary already linked to the group; ignore.
    }
}

$module.ExitJson()
