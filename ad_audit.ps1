
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
