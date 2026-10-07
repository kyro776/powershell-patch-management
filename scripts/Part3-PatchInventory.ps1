# Part3-PatchInventory.ps1
# Inventaire des correctifs : un KB par ligne et par machine, exporte en CSV, trie par poste puis par date decroissante.
# Les machines inaccessibles sont ignorees proprement, sans interrompre le script.

param(
    [string]$ComputersFile = ".\config\computers.txt",
    [string]$OutputCsv     = ".\output\PatchesInventory.csv",
    [string]$UserName      = "DESKTOP-33OJEVG\Diallo",
    [System.Management.Automation.PSCredential]$Credential
)

if (-not (Test-Path $ComputersFile)) {
    Write-Error "Fichier introuvable : $ComputersFile"
    return
}

# Identifiants : fournis en parametre, sinon demandes a l'execution (jamais dans le code)
if (-not $Credential) {
    $password   = Read-Host "Mot de passe de $UserName" -AsSecureString
    $Credential = New-Object System.Management.Automation.PSCredential ($UserName, $password)
}

$localIPs = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress

# Bloc execute sur chaque machine : liste des correctifs
$collect = {
    Get-HotFix | Select-Object HotFixID, Description, InstalledOn, InstalledBy
}

$lines   = Get-Content $ComputersFile | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' }
$patches = @()
$ignored = @()

foreach ($line in $lines) {
    $name, $ip = ($line -split ';') | ForEach-Object { $_.Trim() }

    try {
        if ($localIPs -contains $ip) {
            $hotfixes = & $collect
        }
        else {
            if (-not (Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
                throw "Ping sans reponse"
            }
            $hotfixes = Invoke-Command -ComputerName $ip -Credential $Credential -ScriptBlock $collect -ErrorAction Stop
        }

        foreach ($h in $hotfixes) {
            $patches += [PSCustomObject]@{
                Poste            = $name
                AdresseIP        = $ip
                KB               = $h.HotFixID
                Description      = $h.Description
                DateInstallation = $h.InstalledOn
                InstallePar      = $h.InstalledBy
            }
        }
    }
    catch {
        # Machine ignoree : on note la raison et on continue
        $ignored += [PSCustomObject]@{ Poste = $name; AdresseIP = $ip; Raison = $_.Exception.Message }
    }
}

# Tri : par poste, puis par date d'installation decroissante
$sorted = $patches | Sort-Object Poste, @{ Expression = 'DateInstallation'; Descending = $true }, @{ Expression = 'KB'; Descending = $true }

# Export CSV (dossier output/ ignore par Git)
$dir = Split-Path $OutputCsv -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$sorted | Export-Csv -Path $OutputCsv -NoTypeInformation -Delimiter ";" -Encoding UTF8

# Resume par machine
Write-Host ""
Write-Host "=== Resume par machine ===" -ForegroundColor Cyan
$sorted | Group-Object Poste | ForEach-Object {
    $first = $_.Group[0]
    [PSCustomObject]@{
        Poste          = $_.Name
        NbCorrectifs   = $_.Count
        DernierCorrectif = $first.DateInstallation
        DernierKB      = $first.KB
    }
} | Format-Table -AutoSize

if ($ignored.Count -gt 0) {
    Write-Host "=== Machines ignorees ===" -ForegroundColor Yellow
    $ignored | Format-Table -AutoSize
}

Write-Host "Inventaire des correctifs exporte : $OutputCsv"