param(
    [System.Management.Automation.PSCredential]$Credential
)

$root          = Split-Path $PSScriptRoot -Parent
$computersFile = Join-Path $root 'config\computers.txt'
$requiredFile  = Join-Path $root 'config\required-patches.txt'
$outDir        = Join-Path $root 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

# Correctifs obligatoires (on ignore les lignes vides ou invalides)
$required = @(Get-Content $requiredFile |
    ForEach-Object { $_.Trim().ToUpper() } |
    Where-Object { $_ -match '^KB\d+$' })

$localIPs     = (Get-NetIPAddress -AddressFamily IPv4).IPAddress
$dateControle = Get-Date -Format 'dd/MM/yyyy HH:mm:ss'

$results = foreach ($line in Get-Content $computersFile) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $name, $ip = $line.Split(';') | ForEach-Object { $_.Trim() }

    $statut      = ''
    $manquants   = ''
    $nbManquants = '-'
    $erreur      = ''

    if (-not (Test-Connection $ip -Count 1 -Quiet)) {
        $statut = 'INACCESSIBLE'
        $erreur = 'Ping sans reponse'
    }
    else {
        try {
            if ($localIPs -contains $ip) {
                $installed = Get-HotFix | Select-Object -ExpandProperty HotFixID
            }
            else {
                $params = @{
                    ComputerName = $ip
                    ErrorAction  = 'Stop'
                    ScriptBlock  = { Get-HotFix | Select-Object -ExpandProperty HotFixID }
                }
                if ($Credential) { $params.Credential = $Credential }
                $installed = Invoke-Command @params
            }
            $missing     = @($required | Where-Object { $_ -notin $installed })
            $nbManquants = $missing.Count
            if ($missing.Count -eq 0) {
                $statut = 'CONFORME'
            }
            else {
                $statut    = 'NON CONFORME'
                $manquants = $missing -join ', '
            }
        }
        catch {
            $statut = 'INACCESSIBLE'
            $erreur = $_.Exception.Message
        }
    }

    [PSCustomObject]@{
        Poste         = $name
        AdresseIP     = $ip
        KBRequises    = $required.Count
        NbKBManquants = $nbManquants
        KBManquants   = $manquants
        Statut        = $statut
        DateControle  = $dateControle
        Erreur        = $erreur
    }
}

$results | Export-Csv "$outDir\ComplianceReport.csv" -Delimiter ';' -NoTypeInformation -Encoding UTF8
$results | Format-Table -AutoSize

# Taux global de conformite (sans les postes inaccessibles)
$accessibles = @($results | Where-Object { $_.Statut -ne 'INACCESSIBLE' })
$conformes   = @($results | Where-Object { $_.Statut -eq 'CONFORME' })
$inacc       = @($results | Where-Object { $_.Statut -eq 'INACCESSIBLE' })

if ($accessibles.Count -gt 0) {
    $taux = [math]::Round(($conformes.Count / $accessibles.Count) * 100, 1)
    Write-Host "Taux de conformite : $taux % ($($conformes.Count) conforme(s) sur $($accessibles.Count) machine(s) accessible(s))"
}
else {
    Write-Host "Taux de conformite : non calculable (aucune machine accessible)"
}
Write-Host "Machines inaccessibles : $($inacc.Count)"
Write-Host "Rapport exporte : .\output\ComplianceReport.csv"