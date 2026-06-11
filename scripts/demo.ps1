Write-Host "=== AD ONBOARDING DEMO ==="
Write-Host "1. RequestOnly - Student VG2"
Write-Host "2. RequestOnly - Teacher VG1"
Write-Host "3. RequestOnly - IT-bruker"
Write-Host "4. CreateAD - Student VG2"
Write-Host ""

# Finner requesttool.ps1 i samme mappe som demo.ps1
$ToolPath = Join-Path $PSScriptRoot "requesttool.ps1"

if (-not (Test-Path $ToolPath)) {
    Write-Host "Fant ikke requesttool.ps1 i samme mappe som demo.ps1"
    Write-Host "Sjekk at begge filene ligger i samme mappe."
    exit
}

# Lager et lite nummer slik at navnene ikke blir like hver gang
$Suffix = Get-Date -Format "HHmmss"

$choice = Read-Host "Velg demo"

switch ($choice) {
    "1" {
        & $ToolPath -Mode RequestOnly -Department Students -Role VG2 -FirstName magnus -LastName "jorgensen$Suffix"
    }

    "2" {
        & $ToolPath -Mode RequestOnly -Department Teachers -Role VG1 -FirstName sindre -LastName "belgum$Suffix"
    }

    "3" {
        & $ToolPath -Mode RequestOnly -Department IT -FirstName rune -LastName "karlsen$Suffix"
    }

    "4" {
        & $ToolPath -Mode CreateAD -Department Students -Role VG2 -FirstName Test -LastName "Bruker$Suffix"
    }

    default {
        Write-Host "Ugyldig valg. Bruk 1, 2, 3 eller 4."
    }
}