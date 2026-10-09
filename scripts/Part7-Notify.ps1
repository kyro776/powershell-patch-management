param(
    [string]$SmtpServer = 'localhost',
    [int]$Port = 25,
    [string]$From = 'patchmanager@entreprise.local',
    [string]$To   = 'admin@entreprise.local',
    [System.Management.Automation.PSCredential]$SmtpCredential,  # optionnel, demande a l'execution
    [switch]$UseSsl,
    [System.Management.Automation.PSCredential]$Credential,      # pour la collecte WinRM
    [switch]$SkipCollect
)

$root     = Split-Path $PSScriptRoot -Parent
$outDir   = Join-Path $root 'output'
$logFile  = Join-Path $outDir 'PatchManager.log'
$csvFile  = Join-Path $outDir 'SecurityReport.csv'
$htmlFile = Join-Path $outDir 'SecurityReport.html'

# Caracteres accentues construits a part (evite les problemes d'encodage du fichier .ps1)
$e = [char]0x00E9   # e accent aigu
$o = [char]0x00F4   # o accent circonflexe

function Write-Log {
    param([string]$Message)
    Add-Content -Path $logFile -Value ('{0} ; {1}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'), $Message) -Encoding UTF8
}

# 1. Generation du rapport (Partie 6)
$args6 = @{}
if ($Credential)  { $args6.Credential  = $Credential }
if ($SkipCollect) { $args6.SkipCollect = $true }
& (Join-Path $PSScriptRoot 'Part6-Report.ps1') @args6

# 2. Detection des anomalies
$rapport   = @(Import-Csv $csvFile -Delimiter ';')
$anomalies = @($rapport | Where-Object { $_.Statut -ne 'CONFORME' })

if ($anomalies.Count -eq 0) {
    Write-Log "Aucune anomalie ; notification non envoyee"
    Write-Host "`nAucune anomalie detectee : aucune notification envoyee." -ForegroundColor Green
    return
}

# 3. Construction du message
$nonConf = @($anomalies | Where-Object { $_.Statut -eq 'NON CONFORME' })
$inacc   = @($anomalies | Where-Object { $_.Statut -eq 'INACCESSIBLE' })

$dateControle = ($rapport | Select-Object -First 1).DateControle
$dateJour = if ($dateControle) { $dateControle.Split(' ')[0] } else { Get-Date -Format 'dd/MM/yyyy' }

$lignes = New-Object System.Collections.Generic.List[string]
$lignes.Add("Date du contr${o}le : $dateJour")
$lignes.Add("")
$lignes.Add("Postes contr${o}l${e}s      : $($rapport.Count)")
$lignes.Add("Postes non conformes  : $($nonConf.Count)")
$lignes.Add("Postes inaccessibles  : $($inacc.Count)")

foreach ($p in $anomalies) {
    $lignes.Add("")
    $lignes.Add("$($p.Poste) : $($p.Statut)")
    if ($p.Statut -eq 'NON CONFORME') {
        foreach ($kb in ($p.KBManquants -split ',\s*')) {
            if ($kb -and $kb -ne '-') { $lignes.Add("        $kb manquante") }
        }
    }
}
$corps = $lignes -join "`r`n"
$sujet = "[PATCH MANAGEMENT] Anomalies d${e}tect${e}es"

# 4. Envoi (le mot de passe SMTP, s'il existe, n'est jamais dans le script)
$mail = @{
    SmtpServer    = $SmtpServer
    Port          = $Port
    From          = $From
    To            = $To
    Subject       = $sujet
    Body          = $corps
    Attachments   = $htmlFile
    Encoding      = [System.Text.Encoding]::UTF8
    ErrorAction   = 'Stop'
    WarningAction = 'SilentlyContinue'
}
if ($UseSsl)         { $mail.UseSsl     = $true }
if ($SmtpCredential) { $mail.Credential = $SmtpCredential }

try {
    Send-MailMessage @mail
    Write-Log "Notification envoyee a $To"
    Write-Host "`nNotification envoyee a $To" -ForegroundColor Cyan
}
catch {
    Write-Log "ERREUR ; Notification non envoyee"
    Write-Host "`nERREUR : notification non envoyee ($($_.Exception.Message))" -ForegroundColor Red
}

Write-Host "`n--- Message construit ---"
Write-Host $sujet
Write-Host $corps