# Part2-Inventory.ps1
# Inventaire du parc : lit computers.txt, collecte les infos systeme et Patch Management
# de chaque machine accessible via PowerShell Remoting, affiche un tableau et exporte en CSV.
# Le script ne s'arrete jamais sur une machine en erreur : l'erreur est notee dans l'inventaire.

param(
    [string]$ComputersFile = ".\config\computers.txt",
    [string]$OutputCsv     = ".\output\Inventory.csv",
    [string]$UserName      = "DESKTOP-33OJEVG\Diallo"
)

if (-not (Test-Path $ComputersFile)) {
    Write-Error "Fichier introuvable : $ComputersFile"
    return
}

# Identifiants demandes a l'execution : aucun mot de passe dans le code
$password   = Read-Host "Mot de passe de $UserName" -AsSecureString
$credential = New-Object System.Management.Automation.PSCredential ($UserName, $password)

# Adresses IP de la machine locale (une machine ne peut pas s'administrer elle-meme par WinRM en workgroup)
$localIPs = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress

# Bloc execute sur chaque machine : renvoie un seul objet avec toutes les infos
$collect = {
    $cs   = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $os   = Get-CimInstance Win32_OperatingSystem
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    $kb   = @(Get-HotFix -ErrorAction SilentlyContinue | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending)
    $wu   = Get-Service wuauserv

    [PSCustomObject]@{
        Modele           = $cs.Model
        BIOS             = $bios.SMBIOSBIOSVersion
        Windows          = $os.Caption
        Version          = $os.Version
        Architecture     = $os.OSArchitecture
        DernierDemarrage = $os.LastBootUpTime
        RAM_Go           = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        DisqueLibre_Go   = [math]::Round($disk.FreeSpace / 1GB, 1)
        NbMAJ            = $kb.Count
        DerniereMAJ      = if ($kb.Count -gt 0) { $kb[0].InstalledOn } else { $null }
        WindowsUpdate    = [string]$wu.Status
    }
}

$lines = Get-Content $ComputersFile | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' }

$inventory = foreach ($line in $lines) {
    $name, $ip = ($line -split ';') | ForEach-Object { $_.Trim() }

    # Ligne de base : machine supposee inaccessible
    $row = [ordered]@{
        Poste = $name; AdresseIP = $ip; Etat = "Inaccessible"
        Modele = $null; BIOS = $null; Windows = $null; Version = $null; Architecture = $null
        DernierDemarrage = $null; RAM_Go = $null; DisqueLibre_Go = $null
        NbMAJ = $null; DerniereMAJ = $null; WindowsUpdate = $null; Erreur = $null
    }

    try {
        if ($localIPs -contains $ip) {
            # Machine locale : execution directe
            $data = & $collect
        }
        else {
            # Verification d'accessibilite avant la commande distante (evite ~20 s d'attente par machine morte)
            if (-not (Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
                throw "Ping sans reponse"
            }
            $data = Invoke-Command -ComputerName $ip -Credential $credential -ScriptBlock $collect -ErrorAction Stop
        }

        $row.Etat = "Accessible"
        foreach ($p in $data.PSObject.Properties) {
            if ($row.Contains($p.Name)) { $row[$p.Name] = $p.Value }
        }
    }
    catch {
        # On garde la machine dans l'inventaire avec l'erreur, et on continue
        $row.Erreur = $_.Exception.Message
    }

    [PSCustomObject]$row
}

# Tableau recapitulatif
$inventory | Format-Table Poste, AdresseIP, Windows, Architecture, DernierDemarrage, WindowsUpdate, Etat -AutoSize

# Export CSV (dossier output/ ignore par Git)
$dir = Split-Path $OutputCsv -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$inventory | Export-Csv -Path $OutputCsv -NoTypeInformation -Delimiter ";" -Encoding UTF8
Write-Host "Inventaire exporte : $OutputCsv"