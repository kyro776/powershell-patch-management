# Part1-Availability.ps1
# Lit computers.txt et affiche nom, IP et disponibilité de chaque poste

param(
    [string]$ComputersFile = ".\config\computers.txt"
)

if (-not (Test-Path $ComputersFile)) {
    Write-Error "Fichier introuvable : $ComputersFile"
    return
}

# On ignore les lignes vides et les commentaires (#)
$lines = Get-Content $ComputersFile | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' }

$results = foreach ($line in $lines) {
    $name, $ip = $line -split ';'
    $name = $name.Trim()
    $ip   = $ip.Trim()

    # -Quiet renvoie $true/$false, -Count 1 = un seul ping
    $ping = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        Poste         = $name
        AdresseIP     = $ip
        Disponibilite = if ($ping) { "Accessible" } else { "Inaccessible" }
    }
}

$results | Format-Table -AutoSize
