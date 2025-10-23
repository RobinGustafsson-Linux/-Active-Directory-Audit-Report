# Active Directory Audit - TechCorp AB
# Del A + Del B: Läs JSON, analysera användare och datorer, skapa rapport + CSV

# Läs in JSON
$data = Get-Content -Path "ad_export.json" -Raw | ConvertFrom-Json

# Timestampel for generating
$generated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

# DEL A - Grundläggande
Write-Host "Del A: Grundläggande analys..."
Write-Host "Domän:" $data.domain
Write-Host "Exportdatum:" $data.export_date

# Calculate threshold date
$thirtyDaysAgo = (Get-Date).AddDays(-30)
$sevenDaysAgo = (Get-Date).AddDays(-7)
$nintyDaysAgo = (Get-Date).AddDays(-90)

# Filterate inactive users (>30 days since lastLogon)
$inaktivaAnvandare = $data.users | Where-Object {
    # Hantera om lastLogon finns
    if ([string]::IsNullOrWhiteSpace($_.lastLogon)) { return $false }
    ([datetime]$_.lastLogon) -lt $thirtyDaysAgo
}

# Count per department 
$antalPerAvd = @{}
foreach ($u in $data.users) {
    $avd = $u.department
    if ($antalPerAvd.ContainsKey($avd)) { $antalPerAvd[$avd]++ } else { $antalPerAvd[$avd] = 1 }
}

# Calculate password age (in days) and mark older than 90 days
foreach ($u in $data.users) {
    if ($u.passwordLastSet) {
        $pwdDate = [datetime]$u.passwordLastSet
        $age = ((Get-Date) - $pwdDate).Days
    }
    else {
        $age = 9999
    }
    # Add property for later export/report
    $u | Add-Member -NotePropertyName passwordAgeDays -NotePropertyValue $age -Force
}

# DEL B - Pipeline & Export

Write-Host "`nDel B: Pipeline och export..."

# Group-Object: computer per site
$datorerPerSite = $data.computers | Group-Object -Property site

# Created inactive_users.csv
$csvInactive = $inaktivaAnvandare | ForEach-Object {
    $daysInactive = ((Get-Date) - [datetime]$_.lastLogon).Days
    [PSCustomObject]@{
        SamAccountName = $_.samAccountName
        DisplayName    = $_.displayName
        Department     = $_.department
        Site           = $_.site
        LastLogon      = $_.lastLogon
        DaysInactive   = $daysInactive
        AccountExpires = $_.accountExpires
    }
}
$csvInactive | Export-Csv -Path "inactive_users.csv" -NoTypeInformation -Encoding UTF8
Write-Host "CSV skapad: inactive_users.csv"

# List the 10 computers that hasnt checked in for longest time (oldest first)
$oldestComputers = $data.computers |
Where-Object { $_.lastLogon -and (-not [string]::IsNullOrWhiteSpace($_.lastLogon)) } |
Sort-Object { [datetime]$_.lastLogon } |
Select-Object -First 10

# Created computer_status.csv (summary per site)
$computerSummary = foreach ($grp in $datorerPerSite) {
    $siteName = $grp.Name
    $computers = $grp.Group
    $total = $computers.Count
    $active = ($computers | Where-Object { [datetime]$_.lastLogon -ge $sevenDaysAgo }).Count
    $inactive = ($computers | Where-Object { [datetime]$_.lastLogon -lt $thirtyDaysAgo }).Count
    $win11 = ($computers | Where-Object { $_.operatingSystem -like "*Windows 11*" }).Count
    $win10 = ($computers | Where-Object { $_.operatingSystem -like "*Windows 10*" }).Count
    $winServer = ($computers | Where-Object { $_.operatingSystem -like "*Windows Server*" }).Count

    [PSCustomObject]@{
        Site               = $siteName
        TotalComputers     = $total
        ActiveComputers    = $active
        InactiveComputers  = $inactive
        Windows10Count     = $win10
        Windows11Count     = $win11
        WindowsServerCount = $winServer
    }
}
$computerSummary | Export-Csv -Path "computer_status.csv" -NoTypeInformation -Encoding UTF8
Write-Host "CSV skapad: computer_status.csv"

# More calculations for executive summary
$accountsExpiring30 = ($data.users | Where-Object {
        if ($_.accountExpires) {
            ([datetime]$_.accountExpires) -lt (Get-Date).AddDays(30)
        }
        else { $false }
    }).Count

$usersNotLogged30 = $inaktivaAnvandare.Count
$computersNotSeen30 = ($data.computers | Where-Object {
        ([datetime]$_.lastLogon) -lt $thirtyDaysAgo
    }).Count

$pwdOlder90 = ($data.users | Where-Object { $_.passwordAgeDays -ge 90 }).Count

$totalComputers = $data.computers.Count
$win11Total = ($data.computers | Where-Object { $_.operatingSystem -like "*Windows 11*" }).Count
$win11Pct = if ($totalComputers -gt 0) { [math]::Round(($win11Total / $totalComputers) * 100, 0) } else { 0 }

# Create text report in this format
$inactiveUserLines = $inaktivaAnvandare | Sort-Object { [datetime]$_.lastLogon } |
Select-Object -First 5 | ForEach-Object {
    $days = ((Get-Date) - [datetime]$_.lastLogon).Days
    "{0,-10} {1,-18} {2,-10} {3,-15} {4,6}" -f $_.samAccountName, $_.displayName, $_.department, $_.lastLogon, $days
} | Out-String

$usersPerDeptText = $antalPerAvd.GetEnumerator() | Sort-Object Name | ForEach-Object {
    " {0,-18} {1,3} users" -f $_.Key, $_.Value
} | Out-String

$computersByOs = $data.computers | Group-Object -Property operatingSystem | ForEach-Object {
    # present name, count and procent
    $name = $_.Name
    $count = $_.Count
    $pct = if ($totalComputers -gt 0) { [math]::Round(($count / $totalComputers) * 100, 0) } else { 0 }
    "{0,-25} {1,3} ({2}%)" -f $name, $count, $pct
} | Out-String

$report = @"
================================================================================
                        ACTIVE DIRECTORY AUDIT REPORT
================================================================================
Generated: $generated
Domain: $($data.domain)
Export Date: $($data.export_date)

EXECUTIVE SUMMARY
-----------------
⚠ CRITICAL: $accountsExpiring30 user accounts expiring within 30 days
⚠ WARNING: $usersNotLogged30 users haven't logged in for 30+ days
⚠ WARNING: $computersNotSeen30 computers not seen in 30+ days
⚠ SECURITY: $pwdOlder90 users with passwords older than 90 days
✓ POSITIVE: $win11Pct% of computers running Windows 11

USER ACCOUNT STATUS
-------------------
Total Users: $($data.users.Count)
Active Users: $(($data.users | Where-Object { $_.enabled -eq $true }).Count) ($([math]::Round((($data.users | Where-Object { $_.enabled -eq $true }).Count / $data.users.Count) * 100,0))% )
Disabled Accounts: $(($data.users | Where-Object { $_.enabled -eq $false }).Count)

INACTIVE USERS (No login >30 days)
-----------------------------------
Username    Name                Department      Last Login        Days Inactive
$inactiveUserLines

USERS PER DEPARTMENT
--------------------
$usersPerDeptText

COMPUTER STATUS
---------------
Total Computers: $totalComputers
Active (seen <7 days): $(($data.computers | Where-Object { [datetime]$_.lastLogon -ge $sevenDaysAgo }).Count)
Inactive (>30 days): $computersNotSeen30

COMPUTERS BY OPERATING SYSTEM
------------------------------
$computersByOs
"@

# Save file 
$report | Out-File -FilePath "ad_audit_report.txt" -Encoding UTF8
Write-Host "`nText-rapport skapad: ad_audit_report.txt"

# Write summary of created files in the terminal
Write-Host "`nKlar. Filer skapade:"
Write-Host " - ad_audit_report.txt"
Write-Host " - inactive_users.csv"
Write-Host " - computer_status.csv"
