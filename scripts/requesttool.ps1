param(
    
    [ValidateSet("RequestOnly","CreateAD")]
    [string]$Mode = "RequestOnly",

    [ValidateSet("IT","Students","Teachers")]
    [string]$Department,

    [string]$Role,

    [string]$FirstName,

    [string]$LastName,

    [string]$FallbackDomain = "lab.local"
)


$ErrorActionPreference = "Stop"

# Prosjektroot = én mappe opp fra scripts-mappa
$Root = Split-Path -Parent $PSScriptRoot

$ReqDir      = Join-Path $Root "requests"
$LogDir      = Join-Path $Root "logs"
$ResultsDir  = Join-Path $Root "results"
$ReqPath     = Join-Path $ReqDir "requests.csv"
$ResultsPath = Join-Path $ResultsDir "results.csv"
$LogPath     = Join-Path $LogDir ("run_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

# Sørg for mapper
New-Item -ItemType Directory -Path $ReqDir, $LogDir, $ResultsDir -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $LogPath -Value $line
    Write-Host $line
}

function New-Username {
    param([string]$FirstName, [string]$LastName)

    $u = ("{0}.{1}" -f $FirstName.Trim(), $LastName.Trim()).ToLower()
    $u = $u.Replace("æ","ae").Replace("ø","oe").Replace("å","aa")
    $u = $u -replace "\s",""
    $u = $u -replace "[^a-z0-9\.]",""
    return $u
}

function New-RequestId {
    param([string]$ReqPath)

    $today = Get-Date -Format "yyyyMMdd"
    $nextNumber = 1

    if (Test-Path $ReqPath) {
        $rows = Import-Csv $ReqPath
        $todayRows = $rows | Where-Object { $_.RequestId -like "$today-*" }

        if ($todayRows) {
            $max = ($todayRows | ForEach-Object {
                $parts = $_.RequestId -split "-"
                [int]$parts[1]
            } | Measure-Object -Maximum).Maximum

            $nextNumber = $max + 1
        }
    }

    return ("{0}-{1:000}" -f $today, $nextNumber)
}

function Get-DomainDN {
    param([string]$Fqdn)
    ($Fqdn.Split('.') | ForEach-Object { "DC=$_" }) -join ","
}

function Get-CurrentDomainInfo {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $domain = Get-ADDomain
        return [pscustomobject]@{
            DNSRoot           = $domain.DNSRoot
            DistinguishedName = $domain.DistinguishedName
        }
    }
    catch {
        return $null
    }
}

function Get-OUFromDept {
    param(
        [string]$Department,
        [string]$DomainDN
    )

    switch ($Department.ToLower()) {
        "it"       { "OU=IT,$DomainDN" }
        "students" { "OU=Students,$DomainDN" }
        "teachers" { "OU=Teachers,$DomainDN" }
        default    { throw "Ugyldig avdeling. Bruk IT / Students / Teachers." }
    }
}

function Get-GroupsFromRole {
    param(
        [string]$Department,
        [string]$Role
    )

    $groups = @()

    switch ($Department.ToLower()) {
        "students" {
            switch ($Role.ToLower()) {
                "vg1" { $groups += "VG1" }
                "vg2" { $groups += "VG2" }
                default { throw "Ugyldig rolle for Students. Bruk VG1 eller VG2." }
            }
        }

        "teachers" {
            switch ($Role.ToLower()) {
                "vg1" { $groups += "Teachers-VG1" }
                "vg2" { $groups += "Teachers-VG2" }
                default { throw "Ugyldig rolle for Teachers. Bruk VG1 eller VG2." }
            }
        }

        "it" {
            # IT skal ikke ha gruppe foreløpig
        }

        default {
            throw "Ugyldig avdeling."
        }
    }

    return ($groups | Select-Object -Unique) -join ";"
}

function New-RandomPassword {
    param([int]$Length = 14)
    $chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@$%&*?"
    -join (1..$Length | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
}

function Save-Result {
    param(
        [string]$RequestId,
        [string]$Username,
        [string]$Status,
        [string]$Message
    )

    $resultRow = [pscustomobject]@{
        Time      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        RequestId = $RequestId
        Username  = $Username
        Status    = $Status
        Message   = $Message
    }

    if (-not (Test-Path $ResultsPath)) {
        $resultRow | Export-Csv -Path $ResultsPath -NoTypeInformation -Encoding UTF8
    }
    else {
        $resultRow | Export-Csv -Path $ResultsPath -NoTypeInformation -Append -Encoding UTF8
    }
}

function Create-ADUserFromRequest {
    param(
        [pscustomobject]$RequestRow,
        [string]$DomainFqdn
    )

    Import-Module ActiveDirectory -ErrorAction Stop

    $existingUser = Get-ADUser -Filter "SamAccountName -eq '$($RequestRow.Username)'" -ErrorAction SilentlyContinue
    if ($existingUser) {
        throw "AD-bruker '$($RequestRow.Username)' finnes allerede."
    }

    $ouExists = Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$($RequestRow.OU))" -ErrorAction SilentlyContinue
    if (-not $ouExists) {
        throw "Fant ikke OU i AD: $($RequestRow.OU)"
    }

    $groupList = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestRow.Groups)) {
        $groupList = $RequestRow.Groups -split ";" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    foreach ($group in $groupList) {
        $groupExists = Get-ADGroup -Filter "Name -eq '$group'" -ErrorAction SilentlyContinue
        if (-not $groupExists) {
            throw "Fant ikke gruppe i AD: $group"
        }
    }

    $tempPasswordPlain = New-RandomPassword
    $securePassword = ConvertTo-SecureString $tempPasswordPlain -AsPlainText -Force

    New-ADUser `
        -Name "$($RequestRow.FirstName) $($RequestRow.LastName)" `
        -GivenName $RequestRow.FirstName `
        -Surname $RequestRow.LastName `
        -SamAccountName $RequestRow.Username `
        -UserPrincipalName "$($RequestRow.Username)@$DomainFqdn" `
        -Path $RequestRow.OU `
        -AccountPassword $securePassword `
        -Enabled $true `
        -ChangePasswordAtLogon $true

    foreach ($group in $groupList) {
        Add-ADGroupMember -Identity $group -Members $RequestRow.Username
    }

    return $tempPasswordPlain
}

Write-Log "Starter script"
Write-Log "Mode: $Mode"
Write-Log "Prosjektroot: $Root"

# Finn domene automatisk hvis AD-modulen finnes, ellers fallback
$domainInfo = Get-CurrentDomainInfo

if ($domainInfo) {
    $DomainFqdn = $domainInfo.DNSRoot
    $DomainDN   = $domainInfo.DistinguishedName
    Write-Log "Fant domene automatisk: $DomainFqdn / $DomainDN"
}
else {
    $DomainFqdn = $FallbackDomain
    $DomainDN   = Get-DomainDN -Fqdn $DomainFqdn
    Write-Log "AD-modul ikke tilgjengelig. Bruker fallback-domene: $DomainFqdn"
}

 # Input  bruker parametre hvis de er gitt, ellers spør scriptet interaktivt

if ([string]::IsNullOrWhiteSpace($Department)) {
    $Dept = Read-Host "Avdeling (IT/Students/Teachers)"
}
else {
    $Dept = $Department
}

if ([string]::IsNullOrWhiteSpace($Dept)) {
    throw "Avdeling kan ikke være tom."
}

switch ($Dept.ToLower()) {
    "it" {
        $Role = ""
    }
    "students" {
        if ([string]::IsNullOrWhiteSpace($Role)) {
            $Role = Read-Host "Rolle (VG1/VG2)"
        }
    }
    "teachers" {
        if ([string]::IsNullOrWhiteSpace($Role)) {
            $Role = Read-Host "Rolle (VG1/VG2)"
        }
    }
    default {
        throw "Ugyldig avdeling. Bruk IT / Students / Teachers."
    }
}

if ([string]::IsNullOrWhiteSpace($FirstName)) {
    $FirstName = Read-Host "Fornavn"
}

if ([string]::IsNullOrWhiteSpace($LastName)) {
    $LastName = Read-Host "Etternavn"
}

if ([string]::IsNullOrWhiteSpace($FirstName)) { throw "Fornavn kan ikke være tomt." }
if ([string]::IsNullOrWhiteSpace($LastName))  { throw "Etternavn kan ikke være tomt." }

if ($Dept.ToLower() -ne "it" -and [string]::IsNullOrWhiteSpace($Role)) {
    throw "Rolle kan ikke være tom for Students eller Teachers."
}

$requestId = New-RequestId -ReqPath $ReqPath
$username  = New-Username -FirstName $FirstName -LastName $LastName
$ou        = Get-OUFromDept -Department $Dept -DomainDN $DomainDN
$groups    = Get-GroupsFromRole -Department $Dept -Role $Role

# Duplikatsjekk i requests.csv
if (Test-Path $ReqPath) {
    $existing = Import-Csv $ReqPath
    if ($existing.Username -contains $username) {
        throw "Username '$username' finnes allerede i requests.csv"
    }
}

$row = [pscustomobject]@{
    RequestId  = $requestId
    FirstName  = $FirstName
    LastName   = $LastName
    Department = $Dept
    Role       = $Role
    Username   = $username
    OU         = $ou
    Groups     = $groups
}

# Lagre request
if (-not (Test-Path $ReqPath)) {
    $row | Export-Csv -Path $ReqPath -NoTypeInformation -Encoding UTF8
    Write-Log "Opprettet requests.csv"
}
else {
    $row | Export-Csv -Path $ReqPath -NoTypeInformation -Append -Encoding UTF8
    Write-Log "La til rad i requests.csv"
}

Write-Host "`n=== REQUEST LAGRET ==="
$row | Format-List

# AD-oppretting hvis valgt
if ($Mode -eq "CreateAD") {
    try {
        Write-Log "Forsøker å opprette bruker i AD"
        $tempPassword = Create-ADUserFromRequest -RequestRow $row -DomainFqdn $DomainFqdn

        Write-Log "AD-bruker opprettet: $username"
        Save-Result -RequestId $requestId -Username $username -Status "OK" -Message "AD-bruker opprettet"

        Write-Host "`n=== AD OPPRETTET ==="
        Write-Host "Bruker: $username"
        Write-Host "Midlertidig passord: $tempPassword"
    }
    catch {
        Write-Log "AD-feil: $($_.Exception.Message)"
        Save-Result -RequestId $requestId -Username $username -Status "FAIL" -Message $_.Exception.Message
        throw
    }
}
else {
    Save-Result -RequestId $requestId -Username $username -Status "REQUEST_ONLY" -Message "Kun request lagret"
}

Write-Log "Ferdig. CSV: $ReqPath"
Write-Log "Ferdig. Resultater: $ResultsPath"