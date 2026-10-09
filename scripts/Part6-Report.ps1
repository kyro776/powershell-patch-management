param(
    [System.Management.Automation.PSCredential]$Credential,
    [switch]$SkipCollect   # si present : reutilise les CSV existants sans relancer les controles
)

$root   = $PSScriptRoot | Split-Path -Parent
$outDir = Join-Path $root 'output'
$logFile = Join-Path $outDir 'PatchManager.log'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

function Write-Log {
    param([string]$Message)
    $ligne = '{0} ; {1}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'), $Message
    Add-Content -Path $logFile -Value $ligne -Encoding UTF8
}
function Enc([object]$v) { [System.Net.WebUtility]::HtmlEncode([string]$v) }

Write-Log "Debut de l'audit"

# 1. Collecte (Parties 2 et 4)
if (-not $SkipCollect) {
    $args2 = @{}
    if ($Credential) { $args2.Credential = $Credential }
    & (Join-Path $PSScriptRoot 'Part2-Inventory.ps1')  @args2 | Out-Null
    & (Join-Path $PSScriptRoot 'Part4-Compliance.ps1') @args2 | Out-Null
}

$inventory  = Import-Csv (Join-Path $outDir 'Inventory.csv')        -Delimiter ';'
$compliance = Import-Csv (Join-Path $outDir 'ComplianceReport.csv') -Delimiter ';'

# 2. Fusion par poste
$rapport = foreach ($c in $compliance) {
    $inv = $inventory | Where-Object { $_.Poste -eq $c.Poste } | Select-Object -First 1
    $acces = if ($c.Statut -eq 'INACCESSIBLE') { 'Inaccessible' } else { 'Accessible' }

    # Journal
    if ($c.Statut -eq 'INACCESSIBLE') {
        Write-Log "$($c.Poste) ; WinRM inaccessible"
    }
    else {
        Write-Log "$($c.Poste) ; Accessible"
        if ($c.Statut -eq 'CONFORME') { Write-Log "$($c.Poste) ; Conforme" }
        else { Write-Log "$($c.Poste) ; Non conforme ; $($c.KBManquants)" }
    }

    [PSCustomObject]@{
        Poste            = $c.Poste
        AdresseIP        = $c.AdresseIP
        Acces            = $acces
        Windows          = if ($inv -and $inv.Windows) { "$($inv.Windows) ($($inv.Version))" } else { '-' }
        DernierDemarrage = if ($inv -and $inv.DernierDemarrage) { $inv.DernierDemarrage } else { '-' }
        WindowsUpdate    = if ($inv -and $inv.WindowsUpdate) { $inv.WindowsUpdate } else { '-' }
        KBRequises       = $c.KBRequises
        NbKBManquants    = $c.NbKBManquants
        KBManquants      = if ($c.KBManquants) { $c.KBManquants } else { '-' }
        Statut           = $c.Statut
        DateControle     = $c.DateControle
    }
}

# 3. Synthese globale
$total       = @($rapport).Count
$accessibles = @($rapport | Where-Object { $_.Statut -ne 'INACCESSIBLE' }).Count
$inacc       = @($rapport | Where-Object { $_.Statut -eq 'INACCESSIBLE' }).Count
$conformes   = @($rapport | Where-Object { $_.Statut -eq 'CONFORME' }).Count
$nonConf     = @($rapport | Where-Object { $_.Statut -eq 'NON CONFORME' }).Count
$totalKB     = 0
foreach ($r in $rapport) { if ($r.NbKBManquants -match '^\d+$') { $totalKB += [int]$r.NbKBManquants } }
$taux = if ($accessibles -gt 0) { [math]::Round(($conformes / $accessibles) * 100, 1) } else { 0 }
$dateRapport = Get-Date -Format 'dd/MM/yyyy HH:mm:ss'

$aTraiter = @($rapport | Where-Object { $_.Statut -ne 'CONFORME' })

# 4. Export CSV du rapport
$rapport | Export-Csv (Join-Path $outDir 'SecurityReport.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8

# 5. Version HTML
function Ligne($r) {
    $classe = switch ($r.Statut) { 'CONFORME' {'ok'} 'NON CONFORME' {'ko'} default {'na'} }
    "<tr><td>$(Enc $r.Poste)</td><td>$(Enc $r.AdresseIP)</td><td>$(Enc $r.Acces)</td><td>$(Enc $r.Windows)</td>" +
    "<td>$(Enc $r.DernierDemarrage)</td><td>$(Enc $r.WindowsUpdate)</td><td>$(Enc $r.KBRequises)</td>" +
    "<td>$(Enc $r.NbKBManquants)</td><td>$(Enc $r.KBManquants)</td><td class='$classe'>$(Enc $r.Statut)</td>" +
    "<td>$(Enc $r.DateControle)</td></tr>"
}
$lignesTout = ($rapport  | ForEach-Object { Ligne $_ }) -join "`n"
$lignesInter = if ($aTraiter.Count -gt 0) { ($aTraiter | ForEach-Object { Ligne $_ }) -join "`n" }
               else { "<tr><td colspan='11'>Aucun poste ne necessite d'intervention.</td></tr>" }

$entete = "<tr><th>Poste</th><th>Adresse IP</th><th>Acces</th><th>Windows</th><th>Dernier demarrage</th><th>Windows Update</th><th>KB requis</th><th>KB manquants</th><th>Liste des KB manquants</th><th>Etat</th><th>Date du controle</th></tr>"

$html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>Rapport de securite - Patch Management</title>
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #222; }
  h1 { margin-bottom: 4px; }
  .date { color: #666; margin-bottom: 20px; }
  table { border-collapse: collapse; margin-bottom: 28px; }
  th, td { border: 1px solid #ccc; padding: 6px 10px; text-align: left; }
  th { background: #f0f0f0; }
  .synth td:first-child { font-weight: 600; background: #fafafa; }
  .ok { background: #d4edda; font-weight: 600; }
  .ko { background: #f8d7da; font-weight: 600; }
  .na { background: #e2e3e5; font-weight: 600; }
</style>
</head>
<body>
<h1>Rapport de securite - Patch Management</h1>
<div class="date">Genere le $dateRapport</div>

<h2>Synthese du parc</h2>
<table class="synth">
<tr><td>Nombre total de postes</td><td>$total</td></tr>
<tr><td>Nombre de postes accessibles</td><td>$accessibles</td></tr>
<tr><td>Nombre de postes inaccessibles</td><td>$inacc</td></tr>
<tr><td>Nombre de postes conformes</td><td>$conformes</td></tr>
<tr><td>Nombre de postes non conformes</td><td>$nonConf</td></tr>
<tr><td>Nombre total de correctifs manquants</td><td>$totalKB</td></tr>
<tr><td>Taux de conformite</td><td>$taux % (postes inaccessibles exclus)</td></tr>
</table>

<h2>Postes necessitant une intervention</h2>
<table>
$entete
$lignesInter
</table>

<h2>Detail par poste</h2>
<table>
$entete
$lignesTout
</table>
</body>
</html>
"@
Set-Content -Path (Join-Path $outDir 'SecurityReport.html') -Value $html -Encoding UTF8
Write-Log "Rapport genere"

# 6. Affichage console
Write-Host "`n=== Synthese du parc ===" -ForegroundColor Cyan
[PSCustomObject]@{
    'Postes (total)'        = $total
    'Accessibles'           = $accessibles
    'Inaccessibles'         = $inacc
    'Conformes'             = $conformes
    'Non conformes'         = $nonConf
    'KB manquants (total)'  = $totalKB
    'Taux de conformite'    = "$taux %"
} | Format-List

Write-Host "=== Postes necessitant une intervention ===" -ForegroundColor Yellow
if ($aTraiter.Count -gt 0) {
    $aTraiter | Select-Object Poste, Statut, KBManquants | Format-Table -AutoSize
} else { Write-Host "Aucun.`n" }

Write-Host "Rapport HTML : .\output\SecurityReport.html"
Write-Host "Rapport CSV  : .\output\SecurityReport.csv"
Write-Host "Journal      : .\output\PatchManager.log"

Write-Log "Fin de l'audit"