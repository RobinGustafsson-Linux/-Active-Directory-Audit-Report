
# Read the json data from the file
$data = Get-Content -Path "ad_export-json" -Raw | ConvertFrom-Json

# Del A

Write-Host "=== Del A: Grundläggande analys ==='n"

# Shows domain and export date
Write-Host "Domännamn:" $data.domain
Write-Host "Exportdatum:" $data.export_date

# filter users who hasnt logged in for more than 30 days
$gränsDatum = (Get-Date).AddDays(-30)
$inaktivaAnvändare = $data.users | Where-Object {
    ([datetime]$_.lastLogon) -lt $gränsDatum

}

Write-Host "`nAnvändare som inte loggat in på 30+ dagar:`n"
$inaktivaAnvändare | Select-Object displayName, departmen, site, lastLogon | Format-Table

# Count users per department
$antalPerAvdelning = @{}
foreach ($user in $data.users) {
    $avd = $user.department
    if ($antalPerAvdelning.ContainsKey($avd)) {
        $antalPerAvdelning[$avd] += 1
    }
    else {
        $antalPerAvdelning[$avd] = 1

    }
}

Write-Host "`nAntal användare per avdelning:`n"
foreach ($key in $antalPerAvdelning.Keys) {
    Write-Host "$Key : $(antalPerAvdelning[$key])"
}

# ===== DEL B =====

Write-Host "`n=== Del B: Pipeline och export ===`n"

# Groups computers by site
$datorerPerSite = $data.computers | Group-Object -Property site
Write-Host "Datorer per site:`n"
foreach ($grupp in $datorerPerSite) {
    Write-Host "$($grupp.Name): $($grupp.Count)"
}

# Password calculation in days
foreach ($user in $data.users) {
    $pwdDate = [datetime]$user.passwordLastSet
    $daysOld = ((Get-Date) - $pwdDate).Days
    $user | Add-Member -NotePropertyName "passwordAgeDays" -NotePropertyValue $daysOld -Force
}

# Creating CSV file with inactive users
$inaktivaAnvändare | Select-Object samAccountName, displayName, department, site, lastLogon, passwordAgeDays |
Export-Csv -Path "inactive_users.csv" -NoTypeInformation -Encoding UTF8
Write-Host "`nCSV-fil skapad: inactive_users.csv"

# List the 10 users that have not logged in for the longest time
$datorerSorterade = $data.computers | Sort-Object -Property lastLogon | Select-Object -First 10
Write-Host "`n10 datorer som inte checkat in på längst tid:`n"
$datorerSorterade | Select-Object name, site, lastLogon | Format-Table

# Report writing

$rapport = @"
==============================================
ACTIVE DIRECTORY AUDIT RAPPORT
==============================================
Domän: $($data.domain)
Exportdatum: $($data.export_date)

Antal inaktiva användare: $($inaktivaAnvändare.Count)

Användare per avdelning:
$(
    $antalPerAvdelning.GetEnumerator() | ForEach-Object {
        " - $($_.Key): $($_.Value)"
    } | Out-String
)
==============================================
"@

$rapport | Out-File -FilePath "ad_audit_report.txt" -Encoding UTF8
Write-Host "`nRapport sparad som ad_audit_report.txt"