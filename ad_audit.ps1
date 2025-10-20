
# Read the json data from the file
$data = Get-Content -Path "ad_export-json" -Raw | ConvertFrom-Json

# Del A

Write-Host "=== Del A: Grundläggande analys ==='n"

# Shows domain and export date
Write-Host "Domännamn:" $data.domain
Write-Host "Exportdatum:" $data.export_date

# filter users who hasnt logged in for more than 30 days
$gränsdatum = (Get-Date).AddDays(-30)
$inaktivaAnvändare = $data.users | Where-Object {
    ([datetime]$_.lastLogon) -lt $gränsdatum

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
