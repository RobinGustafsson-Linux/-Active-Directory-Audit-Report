
# Read the json data from the file
$data = Get-Content -Path "ad_export-json" -Raw | ConvertFrom-Json

# Del A

Write-Host "=== Del A: Grundläggande analys ==='n"

