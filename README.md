# Patch Management Windows en PowerShell

Outil simplifié de gestion des correctifs pour un petit parc Windows, réalisé en PowerShell dans le cadre du cours **Sécurité des systèmes** (EFREI, enseignant : Salim Benayoune).

À partir d'une liste de machines (`computers.txt`), la solution :

1. vérifie la disponibilité des postes ;
2. se connecte à distance (PowerShell Remoting / WinRM) pour inventorier chaque poste ;
3. récupère les correctifs installés (numéros KB) ;
4. les compare à une liste de correctifs obligatoires et attribue un statut (CONFORME, NON CONFORME, INACCESSIBLE) ;
5. génère un rapport de sécurité (CSV et HTML) et un journal d'exécution ;
6. envoie une notification par e-mail, uniquement s'il y a une anomalie.

## Structure du dépôt

```
config/
  computers.txt            Liste des postes : nom;adresse IP
  required-patches.txt     Correctifs obligatoires : un KB par ligne
scripts/
  Part1-Availability.ps1   Disponibilité des postes (ping)
  Part2-Inventory.ps1      Inventaire matériel et système
  Part3-PatchInventory.ps1 Inventaire des correctifs installés
  Part4-Compliance.ps1     Contrôle de conformité
  Part6-Report.ps1         Rapport de sécurité (CSV, HTML) et journal
  Part7-Notify.ps1         Notification e-mail en cas d'anomalie
docs/                      Captures d'écran des tests
output/                    Fichiers générés (non versionnés, voir plus bas)
```

La Partie 5 n'existe pas dans le sujet. La Partie 8 (sécurisation) est une analyse et des réglages système, décrits dans le rapport : elle n'a pas de script.

## Prérequis

- Windows PowerShell 5.1 sur le poste d'administration.
- Au moins une machine à contrôler (physique ou virtuelle) joignable sur le réseau.
- **WinRM activé sur chaque poste contrôlé**, dans une console PowerShell administrateur :
  ```powershell
  Enable-PSRemoting -Force
  ```
- Profil réseau **Privé** (ou Domaine) sur les postes contrôlés : le profil Public désactive la règle de pare-feu WinRM.
- Réponse au ping (ICMPv4 entrant autorisé), car les scripts testent la machine avant de s'y connecter.
- Hors domaine, déclarer les postes cibles dans les hôtes approuvés du poste d'administration, avec des adresses précises (jamais `*`) :
  ```powershell
  Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.10.12" -Force
  ```
- Un compte autorisé à ouvrir une session distante sur les postes cibles.

## Configuration

**`config/computers.txt`** : un poste par ligne, `nom;adresse IP`. Exemple :

```
PC01;192.168.10.11
PC02;192.168.10.12
PC03;192.168.10.13
```

Le poste d'administration peut figurer dans la liste : il est alors contrôlé en local, sans WinRM.

**`config/required-patches.txt`** : la politique de conformité, un numéro de KB par ligne. Les lignes vides ou qui ne ressemblent pas à un KB sont ignorées. Exemple :

```
KB5124007
KB5129195
```

## Utilisation

Ouvrir PowerShell dans le dossier du projet. Autoriser les scripts pour la fenêtre en cours seulement :

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

Créer les identifiants du compte distant (le mot de passe est saisi à l'exécution, jamais écrit dans le code) :

```powershell
$pwd  = Read-Host "Mot de passe" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential ("<NOM_MACHINE>\<utilisateur>", $pwd)
```

Les scripts s'enchaînent dans l'ordre des parties :

| Script | Rôle | Paramètres | Fichiers produits (`output/`) |
| --- | --- | --- | --- |
| `Part1-Availability.ps1` | Affiche nom, adresse IP et disponibilité de chaque poste | aucun | aucun |
| `Part2-Inventory.ps1` | Modèle, BIOS, Windows, architecture, RAM, disque, dernier démarrage, mises à jour, service Windows Update | `-Credential` | `Inventory.csv` |
| `Part3-PatchInventory.ps1` | Un enregistrement par correctif (KB, description, date, installé par) ; résumé par machine | `-Credential` | `PatchesInventory.csv` |
| `Part4-Compliance.ps1` | Compare les KB installés aux KB requis ; taux de conformité (postes inaccessibles exclus) | `-Credential` | `ComplianceReport.csv` |
| `Part6-Report.ps1` | Relance les parties 2 et 4, fusionne les résultats, génère la synthèse du parc, la liste des postes à traiter et le rapport HTML | `-Credential`, `-SkipCollect` | `SecurityReport.csv`, `SecurityReport.html`, `PatchManager.log` |
| `Part7-Notify.ps1` | Génère le rapport puis envoie un e-mail seulement si un poste est NON CONFORME ou INACCESSIBLE | `-Credential`, `-SkipCollect`, `-SmtpServer`, `-Port`, `-From`, `-To`, `-SmtpCredential`, `-UseSsl` | ajoute des lignes à `PatchManager.log` |

Exemples :

```powershell
./scripts/Part2-Inventory.ps1 -Credential $cred
./scripts/Part4-Compliance.ps1 -Credential $cred
./scripts/Part6-Report.ps1 -Credential $cred            # chaîne complète + rapport
./scripts/Part6-Report.ps1 -Credential $cred -SkipCollect   # réutilise les CSV existants
./scripts/Part7-Notify.ps1 -Credential $cred             # chaîne complète + notification
```

`Part7-Notify.ps1` suffit pour tout exécuter : il appelle la Partie 6, qui appelle les Parties 2 et 4.

## Notification : serveur de test

Par défaut, le message est envoyé à `admin@entreprise.local` via `localhost:25`. Pour tester sans compte de messagerie, installer **smtp4dev**, un serveur SMTP local qui reçoit les messages sans les transmettre :

```powershell
winget install Rnwood.Smtp4dev
```

Après le lancement, l'interface web est sur `http://localhost:5000`. Pour un serveur réel avec authentification, passer `-SmtpServer`, `-Port`, `-UseSsl` et `-SmtpCredential` (identifiant saisi à l'exécution avec `Get-Credential`).

## Fichiers générés

Le dossier `output/` contient l'état détaillé du parc : il est **exclu de Git** (`.gitignore`, avec `*.log`, `*.csv`, `*.html`, `*.xml` et `credentials*`). Il est créé automatiquement par les scripts. Le journal `PatchManager.log` est écrit en ajout : chaque exécution s'ajoute à la suite.

Format du journal :

```
jj/mm/aaaa hh:mm:ss ; Debut de l'audit
jj/mm/aaaa hh:mm:ss ; PC01 ; Accessible
jj/mm/aaaa hh:mm:ss ; PC01 ; Non conforme ; KB5128942
jj/mm/aaaa hh:mm:ss ; PC03 ; WinRM inaccessible
jj/mm/aaaa hh:mm:ss ; Rapport genere
jj/mm/aaaa hh:mm:ss ; Fin de l'audit
jj/mm/aaaa hh:mm:ss ; Notification envoyee a admin@entreprise.local
```

## Sécurité

- Aucun mot de passe ni information sensible dans le code ou le dépôt : les identifiants sont demandés à l'exécution.
- `TrustedHosts` ne contient que des adresses précises.
- Mesures appliquées sur le lab (détail dans le rapport, partie sécurisation) : règle de pare-feu WinRM limitée à l'adresse du poste d'administration sur la machine administrée, droits du dossier `output` réduits à deux comptes, empreinte SHA-256 du journal pour détecter une modification.
- Mesures recommandées mais non déployées : compte de service sans droit d'administration avec JEA, WinRM en HTTPS, Kerberos en domaine, copie des journaux sur un stockage distant en ajout seul.

## Limites

- La comparaison se fait par numéro de KB : un correctif remplacé par une mise à jour cumulative peut ne plus être listé par `Get-HotFix`, alors que la faille est corrigée.
- `Get-HotFix` ne voit pas tous les correctifs.
- Les machines sont contrôlées l'une après l'autre : un poste injoignable ralentit l'exécution (environ 20 secondes dans le lab).
- Les rapports fusionnent les données par nom de poste : les noms doivent être uniques.
- `Send-MailMessage` est marquée comme obsolète par Microsoft ; elle est utilisée ici pour sa simplicité.

## Environnement de test

Un poste d'administration Windows 11, une machine virtuelle Windows 11 sous Hyper-V (réseau virtuel Default Switch) et une machine fictive volontairement inaccessible, qui sert à tester la gestion des postes injoignables. Les captures d'écran des tests sont dans `docs/`.
