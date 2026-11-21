<#
    Itineraire - installation et mise a jour en un double-clic (WoW Forever)

    Installe ou met a jour, dans  World of Warcraft\_forever_\Interface\AddOns :
      - Itineraire            (derniere version sur github.com/Calgar50/itineraire-wow-forever,
                               ou le dossier "Itineraire" fourni a cote de ce script s'il est plus recent)
      - Questie + QuestieDB   (derniere version publiee sur github.com/Questie/Questie)
      - Shortest Path Forever (derniere version sur github.com/cjber/shortest-path-forever ; il inclut sa copie de
                               ForeverCore : un ForeverCore installe a part et plus ancien, que plus aucun addon
                               n'exige, est range dans les sauvegardes)
      - DungeonJournal        (ExehnTV, derniere version publiee sur curseforge.com/wow/addons/dungeonjournal) :
                               Itineraire lit ses donjons, butins et quetes de donjon pendant le jeu. Installe
                               s'il manque (sauf -SansDungeonJournal) ; la mise a jour automatique le tient a
                               jour s'il est installe (le supprimer suffit pour qu'elle le laisse tranquille).

    Mise a jour automatique (proposee a la fin, ou -ActiverMajAuto) : une tache planifiee de Windows,
    a ton nom et sans droits d'administrateur, relance ce script en mode -Auto a l'ouverture de session
    (2 minutes apres) puis toutes les 4 heures, sans aucune fenetre (conhost --headless ; sur un Windows
    trop ancien pour cela : seulement quand l'ordinateur est inutilise depuis 10 minutes), et ne fait
    rien si WoW est ouvert. Elle utilise une copie de ce script rangee dans
    %LOCALAPPDATA%\Itineraire (journal : maj.log). -DesactiverMajAuto la retire.

    Securite :
      - telechargements en HTTPS depuis GitHub, et depuis CurseForge pour DungeonJournal (adresses et
        redirections verifiees : www.curseforge.com, edge.forgecdn.net, mediafilez.forgecdn.net) ;
      - empreinte SHA-256 du fichier comparee a celle publiee par GitHub (refus si elle manque ou differe) ;
        CurseForge n'en publie pas : pour DungeonJournal, fichier publie par le compte de son auteur, taille
        exacte, contenu (un seul dossier, fichiers d'addon seulement) et fichier .toc controles ;
      - archive controlee entree par entree : rien ne peut s'ecrire hors du dossier prevu ;
      - seuls les dossiers attendus sont installes (QuestieTrace, livre avec Questie, est laisse de cote :
        il se dispute la fleche avec Itineraire) ;
      - l'ancienne version de chaque addon est deplacee dans Interface\AddOns_sauvegardes\<date> ;
      - une version installee plus recente que celle proposee n'est jamais remplacee ;
      - ce script ne se met JAMAIS a jour tout seul : seuls les addons (du code de jeu, sans acces a
        ton ordinateur) sont telecharges. Un nouvel installateur se recupere a la main (Itineraire
        previent dans le jeu quand il en sort un).

    Usage : double-clic sur Installer-Itineraire.cmd
       ou : powershell -NoProfile -ExecutionPolicy Bypass -File Installer-Itineraire.ps1 [options]
    Options :
      -WowPath <dossier>    dossier _forever_ (ou World of Warcraft) si la detection automatique echoue
      -Verifier             affiche seulement les versions installees et disponibles, sans rien changer
      -SansTelechargement   installe seulement l'Itineraire fourni a cote (rien depuis Internet)
      -SansDungeonJournal   n'installe pas DungeonJournal (et ne le met pas a jour)
      -Oui                  ne pose aucune question (WoW ouvert : on continue quand meme)
      -ActiverMajAuto       active la mise a jour automatique (tache planifiee)
      -DesactiverMajAuto    la desactive (retire la tache et la copie du script)
      -Auto                 mode de la tache planifiee : silencieux, journal dans maj.log, rien si WoW
                            est ouvert, au plus une verification toutes les 3 heures
#>
[CmdletBinding()]
param(
    [string]$WowPath,
    [switch]$Verifier,
    [switch]$SansTelechargement,
    [switch]$SansDungeonJournal,
    [switch]$Oui,
    [switch]$ActiverMajAuto,
    [switch]$DesactiverMajAuto,
    [switch]$Auto
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # sinon les telechargements sont tres lents sous PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$InstallerVersion = 5
$UserAgent = 'Itineraire-Installateur'
$ItiRepo = 'Calgar50/itineraire-wow-forever'
$Sources = @(
    @{ Repo = 'Questie/Questie'; Pattern = '^Questie-v[0-9][0-9A-Za-z.+-]*\.zip$'; Addons = @('Questie', 'QuestieDB'); Optional = @(); Ignore = @('QuestieTrace') },
    # Depuis Shortest Path 1.43.9, ForeverCore n'est plus livre a part : il est inclus dans l'addon (Libs\ForeverCore).
    @{ Repo = 'cjber/shortest-path-forever'; Pattern = '^ShortestPathForever-v[0-9][0-9A-Za-z.+-]*-forever\.zip$'; Addons = @('ShortestPathForever'); Optional = @('ForeverCore'); Ignore = @() }
)
$ItiSource = @{ Repo = $ItiRepo; Pattern = '^Itineraire-v[0-9]+(\.[0-9]+)*\.zip$'; Addons = @('Itineraire'); Ignore = @() }
$OtherGuides = @('RXPGuides', 'AdventureGuideForever', 'Guidelime', 'ZygorGuidesViewer', 'ZygorGuidesViewerClassic', 'Polestar', 'QuestieTrace', 'Leveldon')
# DungeonJournal (ExehnTV) : projet CurseForge, compte de l'auteur, nom des fichiers publies.
$DjSource = @{ ProjectId = 1707971; Folder = 'ForeverDungeonJournal'; Author = 'exehntv'; Pattern = '^DungeonJournal(?<v>[0-9]+(\.[0-9]+){1,3})\.zip$' }
$CurseHosts = @('www.curseforge.com', 'edge.forgecdn.net', 'mediafilez.forgecdn.net')
$DjExtensions = @('', '.lua', '.toc', '.xml', '.tga', '.blp', '.txt', '.md', '.png', '.jpg', '.ttf', '.otf', '.ogg', '.mp3')
$DjMaxBytes = 600MB

$TaskName = 'Itineraire - mise a jour automatique'
$AutoDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Itineraire'
$AutoScript = Join-Path $AutoDir 'Installer-Itineraire.ps1'
$LogFile = Join-Path $AutoDir 'maj.log'
$StampFile = Join-Path $AutoDir 'derniere-verification.txt'
$AutoMinHours = 3

$script:Logging = $false
function Write-Log([string]$Text) {
    if (-not $script:Logging) { return }
    try {
        if ((Test-Path -LiteralPath $LogFile) -and (Get-Item -LiteralPath $LogFile).Length -gt 256KB) {
            Move-Item -LiteralPath $LogFile -Destination ($LogFile + '.ancien') -Force
        }
        Add-Content -LiteralPath $LogFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $Text) -Encoding ASCII
    } catch { }
}
function Say([string]$Text, [string]$Color = 'Gray') {
    if (-not $Auto) { Write-Host $Text -ForegroundColor $Color }
    Write-Log $Text
}
function Title([string]$Text) { Say ''; Say "== $Text" 'Cyan' }

# --- Dossier de WoW Forever ---------------------------------------------------------------
function Test-Forever([string]$Path) {
    if (-not $Path) { return $null }
    try { $full = [IO.Path]::GetFullPath($Path) } catch { return $null }
    if ((Split-Path $full -Leaf) -eq '_forever_' -and (Test-Path -LiteralPath $full -PathType Container)) { return $full }
    $sub = Join-Path $full '_forever_'
    if (Test-Path -LiteralPath $sub -PathType Container) { return $sub }
    return $null
}

function Find-Forever([string]$Hint) {
    if ($Hint) {
        $found = Test-Forever $Hint
        if (-not $found) { throw "Le dossier '$Hint' ne contient pas de dossier _forever_." }
        return $found
    }
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft', 'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft')) {
        try {
            $p = (Get-ItemProperty -LiteralPath $key -Name InstallPath -ErrorAction Stop).InstallPath
            if ($p) { $roots.Add((Split-Path ($p.TrimEnd('\')) -Parent)); $roots.Add($p) }
        } catch { }
    }
    $pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $pf = [Environment]::GetFolderPath('ProgramFiles')
    foreach ($base in @($pf86, $pf)) { if ($base) { $roots.Add((Join-Path $base 'World of Warcraft')) } }
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($rel in @('World of Warcraft', 'Games\World of Warcraft', 'Jeux\World of Warcraft', 'Program Files (x86)\World of Warcraft', 'Blizzard\World of Warcraft')) {
            $roots.Add((Join-Path $drive.Root $rel))
        }
    }
    foreach ($root in $roots) {
        $found = Test-Forever $root
        if ($found) { return $found }
    }
    # Pas trouve : on demande (fenetre de choix de dossier).
    if ($Oui -or $Auto) { throw "Dossier de WoW Forever introuvable : relance avec -WowPath <dossier _forever_>." }
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Choisis le dossier _forever_ de World of Warcraft (ou le dossier World of Warcraft)'
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw 'Installation annulee.' }
    $found = Test-Forever $dialog.SelectedPath
    if (-not $found) { throw "Le dossier choisi ne contient pas de dossier _forever_." }
    return $found
}

# --- Versions --------------------------------------------------------------------------------
function Get-AddonVersion([string]$Dir, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return $null }
    foreach ($toc in @("${Name}_Forever.toc", "$Name.toc")) {
        $path = Join-Path $Dir $toc
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            foreach ($line in (Get-Content -LiteralPath $path -TotalCount 60 -Encoding UTF8)) {
                if ($line -match '^##\s*Version:\s*v?([0-9][0-9A-Za-z.+-]*)') { return $Matches[1] }
            }
        }
    }
    return '?'
}

function ConvertTo-Version([string]$Text) {
    if (-not $Text) { return $null }
    $clean = ($Text -replace '^v', '') -replace '[^0-9.].*$', ''
    $parts = @($clean.Split('.') | Where-Object { $_ -ne '' })
    while ($parts.Count -lt 2) { $parts += '0' }
    if ($parts.Count -gt 4) { $parts = $parts[0..3] }
    try { return [version]($parts -join '.') } catch { return $null }
}

# 1 = la nouvelle est plus recente (ou rien d'installe), 0 = identique, -1 = l'installee est plus recente
function Compare-AddonVersion([string]$Installed, [string]$Offered) {
    if (-not $Installed) { return 1 }
    if (-not $Offered) { return -1 }
    $a = ConvertTo-Version $Installed; $b = ConvertTo-Version $Offered
    if (-not $a -or -not $b) { if ($Installed -eq $Offered) { return 0 } else { return 1 } }
    return [math]::Sign($b.CompareTo($a))
}

# --- GitHub ----------------------------------------------------------------------------------
function Get-LatestAsset($Source) {
    $api = "https://api.github.com/repos/$($Source.Repo)/releases/latest"
    $release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = $UserAgent; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 60
    $asset = @($release.assets | Where-Object { $_.name -match $Source.Pattern }) | Select-Object -First 1
    if (-not $asset) { throw "Aucun fichier attendu dans la derniere version de $($Source.Repo)." }
    $url = [string]$asset.browser_download_url
    if ($url -notmatch '^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/releases/download/') {
        throw "Adresse de telechargement inattendue pour $($Source.Repo) : $url"
    }
    $digestProp = $asset.PSObject.Properties['digest']
    $digest = if ($digestProp) { [string]$digestProp.Value } else { '' }
    if ($digest -match '^sha256:([0-9a-fA-F]{64})$') {
        $sha = $Matches[1].ToLowerInvariant()
    } else {
        throw "GitHub ne publie pas d'empreinte SHA-256 pour $($asset.name) : installation refusee par prudence."
    }
    return [pscustomobject]@{
        Tag = [string]$release.tag_name; Name = [string]$asset.name; Url = $url
        Size = [long]$asset.size; Sha256 = $sha
    }
}

function Save-Asset($Asset, [string]$Folder) {
    $file = Join-Path $Folder $Asset.Name
    Say "   telechargement de $($Asset.Name) ($([math]::Round($Asset.Size / 1MB, 1)) Mo)..."
    Invoke-WebRequest -Uri $Asset.Url -OutFile $file -UseBasicParsing -Headers @{ 'User-Agent' = $UserAgent } -TimeoutSec 900
    $size = (Get-Item -LiteralPath $file).Length
    if ($size -ne $Asset.Size) { throw "Taille inattendue pour $($Asset.Name) : $size octets au lieu de $($Asset.Size)." }
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $Asset.Sha256) { throw "Empreinte SHA-256 differente pour $($Asset.Name) : fichier refuse." }
    Say "   empreinte SHA-256 verifiee." Green
    return $file
}

# --- CurseForge (DungeonJournal) -----------------------------------------------------------
function Get-Prop($Obj, [string]$Name) {
    if ($null -eq $Obj) { return $null }
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

# Derniere version publiee (pas alpha/beta) par le compte de l'auteur, d'apres la liste des fichiers du projet.
function Get-LatestDungeonJournal {
    $api = "https://www.curseforge.com/api/v1/mods/$($DjSource.ProjectId)/files?pageIndex=0&pageSize=20&sort=dateCreated&sortDescending=true&removeAlphas=true"
    $list = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = $UserAgent; 'Accept' = 'application/json' } -TimeoutSec 60
    $best = $null
    foreach ($f in @(Get-Prop $list 'data')) {
        if ([string](Get-Prop $f 'projectId') -ne [string]$DjSource.ProjectId) { continue }
        if ([string](Get-Prop $f 'releaseType') -ne '1') { continue }
        if ([string](Get-Prop (Get-Prop $f 'user') 'username') -ne $DjSource.Author) { continue }
        $name = [string](Get-Prop $f 'fileName')
        $m = [regex]::Match($name, $DjSource.Pattern)
        if (-not $m.Success) { continue }
        $id = [long](Get-Prop $f 'id')
        $size = [long](Get-Prop $f 'fileLength')
        if ($id -le 0 -or $size -le 0 -or $size -gt 300MB) { continue }
        $v = $m.Groups['v'].Value
        if (-not $best -or (Compare-AddonVersion $best.Version $v) -gt 0) {
            $best = [pscustomobject]@{ Id = $id; Name = $name; Version = $v; Size = $size }
        }
    }
    if (-not $best) { throw 'aucune version publiee trouvee sur CurseForge.' }
    return $best
}

# Suit les redirections a la main : chaque adresse doit etre en HTTPS sur un hote de CurseForge.
function Resolve-CurseUrl([string]$Url) {
    for ($i = 0; $i -lt 6; $i++) {
        $uri = New-Object System.Uri $Url
        if ($uri.Scheme -ne 'https' -or $CurseHosts -notcontains $uri.Host) { throw "adresse de telechargement inattendue ($($uri.Host))." }
        $req = [Net.HttpWebRequest]::Create($uri)
        $req.AllowAutoRedirect = $false
        $req.Method = 'HEAD'
        $req.UserAgent = $UserAgent
        $req.Timeout = 60000
        $resp = $null
        try { $resp = $req.GetResponse() } catch [Net.WebException] { $resp = $_.Exception.Response; if (-not $resp) { throw } }
        try {
            $code = [int]$resp.StatusCode
            $location = $resp.Headers['Location']
        } finally {
            $resp.Close()
        }
        if ($code -eq 200) { return $uri.AbsoluteUri }
        if ($code -ge 300 -and $code -lt 400 -and $location) {
            $Url = (New-Object System.Uri ($uri, $location)).AbsoluteUri
            continue
        }
        throw "reponse HTTP $code de $($uri.Host)."
    }
    throw 'trop de redirections.'
}

function Save-CurseFile($File, [string]$Folder) {
    $url = Resolve-CurseUrl ("https://www.curseforge.com/api/v1/mods/{0}/files/{1}/download" -f $DjSource.ProjectId, $File.Id)
    $path = Join-Path $Folder $File.Name
    Say "   telechargement de $($File.Name) ($([math]::Round($File.Size / 1MB, 1)) Mo)..."
    Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing -Headers @{ 'User-Agent' = $UserAgent } -TimeoutSec 900 -MaximumRedirection 0
    $size = (Get-Item -LiteralPath $path).Length
    if ($size -ne $File.Size) { throw "Taille inattendue pour $($File.Name) : $size octets au lieu de $($File.Size)." }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    Say "   taille verifiee (CurseForge ne publie pas d'empreinte ; SHA-256 du fichier recu : $hash)." Green
    return $path
}

# Controle d'une archive avant extraction : un seul dossier attendu, fichiers d'addon seulement, taille bornee.
function Test-ZipContent([string]$Zip, [string[]]$Folders, [string[]]$Extensions, [long]$MaxBytes) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $total = [long]0
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName -replace '\\', '/'
            $top = $name.Split('/')[0]
            if ($Folders -notcontains $top) { throw "contenu inattendu dans l'archive : $name" }
            if (-not $name.EndsWith('/')) {
                $ext = [IO.Path]::GetExtension($name).ToLowerInvariant()
                if ($Extensions -notcontains $ext) { throw "type de fichier inattendu dans l'archive : $name" }
            }
            $total += $entry.Length
            if ($total -gt $MaxBytes) { throw 'archive trop grosse une fois decompressee.' }
        }
    } finally {
        $archive.Dispose()
    }
}

# Extrait seulement les dossiers attendus, sans jamais ecrire hors de $Stage.
function Expand-Checked([string]$Zip, [string]$Stage, [string[]]$Wanted) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stageFull = [IO.Path]::GetFullPath($Stage).TrimEnd('\') + '\'
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    $skipped = @{}
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName -replace '\\', '/'
            if ($name -match '(^|/)\.\.(/|$)' -or $name -match '^[A-Za-z]:' -or $name.StartsWith('/')) {
                throw "Chemin suspect dans l'archive : $name"
            }
            $top = $name.Split('/')[0]
            if ($Wanted -notcontains $top) { if ($top) { $skipped[$top] = $true }; continue }
            $target = [IO.Path]::GetFullPath((Join-Path $Stage $name))
            if (-not $target.StartsWith($stageFull, [StringComparison]::OrdinalIgnoreCase)) { throw "Chemin suspect dans l'archive : $name" }
            if ($name.EndsWith('/')) {
                [void][IO.Directory]::CreateDirectory($target)
            } else {
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
            }
        }
    } finally {
        $archive.Dispose()
    }
    return @($skipped.Keys)
}

# --- Installation d'un addon prepare dans $Stage ---------------------------------------------
# Range un addon installe dans la sauvegarde du jour (rend son nouveau chemin, ou $null s'il n'etait pas la).
function Move-ToBackup([string]$Name, [string]$AddOns, [string]$BackupRoot) {
    $dest = Join-Path $AddOns $Name
    if (-not (Test-Path -LiteralPath $dest)) { return $null }
    if (-not (Test-Path -LiteralPath $BackupRoot)) {
        [void](New-Item -ItemType Directory -Path $BackupRoot -Force)
        Set-Content -LiteralPath (Join-Path $BackupRoot '.itineraire-sauvegarde') -Value 'Sauvegarde faite par Installer-Itineraire.ps1' -Encoding ASCII
    }
    $saved = Join-Path $BackupRoot $Name
    Move-Item -LiteralPath $dest -Destination $saved
    return $saved
}

function Install-Addon([string]$Name, [string]$From, [string]$AddOns, [string]$BackupRoot) {
    $dest = Join-Path $AddOns $Name
    $saved = Move-ToBackup $Name $AddOns $BackupRoot
    try {
        Move-Item -LiteralPath $From -Destination $dest
    } catch {
        # Echec : l'ancienne version reprend sa place, l'addon ne reste jamais absent.
        if ($saved -and -not (Test-Path -LiteralPath $dest)) { Move-Item -LiteralPath $saved -Destination $dest }
        throw
    }
}

# --- ForeverCore separe ou inclus ------------------------------------------------------------
# La copie de ForeverCore la plus recente incluse dans un addon (dossier Libs\ForeverCore, numero lu dans Begin.lua).
function Get-EmbeddedForeverCore([string]$AddOns) {
    $best = $null
    foreach ($dir in @(Get-ChildItem -LiteralPath $AddOns -Directory -ErrorAction SilentlyContinue)) {
        if ($dir.Name -eq 'ForeverCore') { continue }
        $begin = Join-Path $dir.FullName 'Libs\ForeverCore\Begin.lua'
        if (-not (Test-Path -LiteralPath $begin -PathType Leaf)) { continue }
        $text = (Get-Content -LiteralPath $begin -TotalCount 5 -Encoding UTF8 -ErrorAction SilentlyContinue) -join "`n"
        $m = [regex]::Match($text, 'ForeverCoreLoader\.Begin\([^,]*,\s*([0-9]{7,9})\s*,')
        if (-not $m.Success) { continue }
        $build = [long]$m.Groups[1].Value
        $v = '{0}.{1}.{2}' -f [long][math]::Floor($build / 1000000), ([long][math]::Floor($build / 1000) % 1000), ($build % 1000)
        if (-not $best -or (Compare-AddonVersion $best.Version $v) -gt 0) {
            $best = [pscustomobject]@{ Version = $v; Addon = $dir.Name }
        }
    }
    return $best
}

# Un addon (autre que $Name) qui exige $Name installe a part (## Dependencies / ## RequiredDeps de son .toc), ou $null.
function Get-StandaloneUser([string]$Root, [string]$Name) {
    foreach ($dir in @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue)) {
        if ($dir.Name -eq $Name) { continue }
        foreach ($toc in @(Get-ChildItem -LiteralPath $dir.FullName -Filter '*.toc' -File -ErrorAction SilentlyContinue)) {
            foreach ($line in @(Get-Content -LiteralPath $toc.FullName -TotalCount 40 -Encoding UTF8 -ErrorAction SilentlyContinue)) {
                if ($line -match '^##\s*(Dependencies|RequiredDeps|Dep[0-9]*)\s*:\s*(.+)$') {
                    foreach ($dep in $Matches[2].Split(',')) {
                        if ($dep.Trim() -eq $Name) { return $dir.Name }
                    }
                }
            }
        }
    }
    return $null
}

# Un ForeverCore installe a part et plus ancien que la copie incluse dans un addon : son chargeur previent a chaque
# connexion ("ForeverCore x est plus ancien que le ForeverCore y inclus dans vos addons") et la vieille copie sert
# la session. S'il n'est exige par aucun addon, il est range dans la sauvegarde (comme une ancienne version).
function Remove-StaleForeverCore([string]$AddOns, [string]$BackupRoot) {
    $installed = Get-AddonVersion (Join-Path $AddOns 'ForeverCore') 'ForeverCore'
    if (-not $installed) { return $false }
    $embedded = Get-EmbeddedForeverCore $AddOns
    if (-not $embedded -or (Compare-AddonVersion $installed $embedded.Version) -le 0) { return $false }
    $user = Get-StandaloneUser $AddOns 'ForeverCore'
    if ($user) {
        Say "   ForeverCore $installed (a part) est plus ancien que la copie $($embedded.Version) de $($embedded.Addon), mais $user l'exige : garde." DarkYellow
        return $false
    }
    [void](Move-ToBackup 'ForeverCore' $AddOns $BackupRoot)
    Say "   ForeverCore $installed (installe a part) retire : $($embedded.Addon) inclut le $($embedded.Version), plus recent (range dans AddOns_sauvegardes)." Green
    return $true
}

# Garde les 2 dernieres sauvegardes faites par ce script (et seulement les siennes).
function Clear-OldBackups([string]$Root) {
    if (-not (Test-Path -LiteralPath $Root)) { return }
    $sets = @(Get-ChildItem -LiteralPath $Root -Directory | Where-Object {
            $_.Name -match '^\d{8}-\d{6}$' -and (Test-Path -LiteralPath (Join-Path $_.FullName '.itineraire-sauvegarde'))
        } | Sort-Object Name -Descending)
    for ($i = 2; $i -lt $sets.Count; $i++) {
        Say "   ancienne sauvegarde supprimee : $($sets[$i].FullName)" DarkGray
        Remove-Item -LiteralPath $sets[$i].FullName -Recurse -Force
    }
}

# --- Mise a jour automatique (tache planifiee a ton nom) -------------------------------------
function Get-AutoTask {
    try { return Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch { return $null }
}

function Enable-AutoUpdate([string]$Forever) {
    if (-not (Test-Path -LiteralPath $AutoDir)) { [void](New-Item -ItemType Directory -Path $AutoDir -Force) }
    $self = $MyInvocation.ScriptName
    if (-not $self) { $self = $PSCommandPath }
    if ([IO.Path]::GetFullPath($self) -ne [IO.Path]::GetFullPath($AutoScript)) {
        Copy-Item -LiteralPath $self -Destination $AutoScript -Force
    }
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $AutoScript + '" -Auto -WowPath "' + $Forever + '"'
    $conhost = Join-Path $env:WINDIR 'System32\conhost.exe'
    $headless = (Test-Path -LiteralPath $conhost -PathType Leaf) -and ([Environment]::OSVersion.Version.Build -ge 19041)
    if ($headless) {
        # conhost --headless : aucune fenetre, pas meme un eclair (Windows 10 2004 et plus recent). La mise a jour
        # peut donc tourner quand tu utilises l'ordinateur ; WoW ouvert, elle ne fait rien (voir -Auto).
        $action = New-ScheduledTaskAction -Execute $conhost -Argument ('--headless powershell.exe ' + $arguments)
    } else {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
    }
    $atLogon = New-ScheduledTaskTrigger -AtLogOn -User $user
    $atLogon.Delay = 'PT2M'
    $daily = New-ScheduledTaskTrigger -Daily -At '03:00'
    $daily.Repetition = (New-ScheduledTaskTrigger -Once -At '03:00' -RepetitionInterval (New-TimeSpan -Hours 4) -RepetitionDuration (New-TimeSpan -Days 1)).Repetition
    if ($headless) {
        # Installateur 4 : seulement si l'ordinateur etait inutilise 10 min. Trop strict : la mise a jour ne passait
        # presque jamais quand on se sert de l'ordinateur. Sans fenetre, plus besoin d'attendre.
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
    } else {
        # Sans conhost --headless, une fenetre passerait un instant : seulement quand l'ordinateur est inutilise.
        $settings = New-ScheduledTaskSettingsSet -RunOnlyIfIdle -IdleDuration (New-TimeSpan -Minutes 10) -IdleWaitTimeout (New-TimeSpan -Hours 4) `
            -DontStopOnIdleEnd -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
    }
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($atLogon, $daily) -Settings $settings -Principal $principal `
        -Description 'Met a jour Itineraire, Questie, Shortest Path Forever et DungeonJournal pour WoW Forever (Installer-Itineraire.ps1 -Auto). Desactiver : relancer l''installateur avec -DesactiverMajAuto.' -Force | Out-Null
    Say "   mise a jour automatique ACTIVE (tache planifiee '$TaskName', copie du script : $AutoScript)." Green
}

function Disable-AutoUpdate {
    if (Get-AutoTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Say "   tache planifiee '$TaskName' retiree." Green
    } else {
        Say '   pas de mise a jour automatique active.'
    }
    foreach ($f in @($AutoScript, $StampFile)) {
        if (Test-Path -LiteralPath $f -PathType Leaf) { Remove-Item -LiteralPath $f -Force }
    }
}

# Ce que le jeu lit (Itineraire\Installateur.lua) : version de l'installateur, mise a jour auto, date.
# Seulement des valeurs produites ici (nombres, booleen, date) : rien qui vienne d'Internet.
function Write-InstallerInfo([string]$AddOns) {
    $dir = Join-Path $AddOns 'Itineraire'
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'Itineraire.toc'))) { return }
    $auto = if (Get-AutoTask) { 'true' } else { 'false' }
    $text = "-- Ecrit par Installer-Itineraire.ps1 (ne pas modifier)`r`n" +
        "ItineraireInstallateur = { version = $InstallerVersion, auto = $auto, verifie = `"" + (Get-Date -Format 'yyyy-MM-dd HH:mm') + "`" }`r`n"
    [IO.File]::WriteAllText((Join-Path $dir 'Installateur.lua'), $text, (New-Object Text.UTF8Encoding $false))
}

# --- Programme -------------------------------------------------------------------------------
$exit = 0
$tempDir = $null
$stage = $null
try {
    if ($Auto) {
        $script:Logging = $true
        if (-not (Test-Path -LiteralPath $AutoDir)) { [void](New-Item -ItemType Directory -Path $AutoDir -Force) }
        $running = @(Get-Process -Name 'Wow', 'WowClassic', 'WowT', 'WowB' -ErrorAction SilentlyContinue)
        if ($running.Count -gt 0) { Write-Log 'WoW est ouvert : mise a jour reportee.'; exit 0 }
        if (Test-Path -LiteralPath $StampFile) {
            $last = (Get-Item -LiteralPath $StampFile).LastWriteTime
            if (((Get-Date) - $last).TotalHours -lt $AutoMinHours) { exit 0 }
        }
        Write-Log "--- verification automatique (installateur v$InstallerVersion)"
    }
    Say 'Itineraire : installation / mise a jour pour WoW Forever' White
    $forever = Find-Forever $WowPath
    $addOns = Join-Path $forever 'Interface\AddOns'
    Say "Dossier des addons : $addOns"

    if ($DesactiverMajAuto) {
        Title 'Mise a jour automatique'
        Disable-AutoUpdate
        Write-InstallerInfo $addOns
        return
    }

    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    $bundled = Join-Path $here 'Itineraire'
    $bundledVersion = $null
    if (Test-Path -LiteralPath (Join-Path $bundled 'Itineraire.toc')) { $bundledVersion = Get-AddonVersion $bundled 'Itineraire' }

    $plan = New-Object System.Collections.Generic.List[object]
    $assets = @{}
    $itiAsset = $null
    if (-not $SansTelechargement) {
        Title 'Dernieres versions publiees'
        foreach ($src in @($Sources + $ItiSource)) {
            try {
                $asset = Get-LatestAsset $src
            } catch {
                # Une source injoignable n'empeche pas de mettre a jour les autres.
                Say ("   {0} : indisponible ({1})" -f $src.Repo, $_.Exception.Message) Yellow
                continue
            }
            Say ("   {0} : {1}" -f $src.Repo, $asset.Name)
            if ($src.Repo -eq $ItiRepo) { $itiAsset = $asset; continue }
            $assets[$src.Repo] = $asset
            $offered = ($asset.Name -replace '^[A-Za-z]+-v', '') -replace '(-forever)?\.zip$', ''
            foreach ($name in $src.Addons) {
                $plan.Add([pscustomobject]@{ Name = $name; Offered = $offered; Source = $src })
            }
        }
    }
    # DungeonJournal : installe s'il manque (a la main), mis a jour s'il est la (mode -Auto : seulement s'il est la).
    $djInstalled = Get-AddonVersion (Join-Path $addOns $DjSource.Folder) $DjSource.Folder
    $djLatest = $null
    if (-not $SansTelechargement -and -not $SansDungeonJournal -and (-not $Auto -or $djInstalled)) {
        try {
            $djLatest = Get-LatestDungeonJournal
            Say ("   curseforge.com/wow/addons/dungeonjournal : {0}" -f $djLatest.Name)
        } catch {
            Say ("   curseforge.com/wow/addons/dungeonjournal : indisponible ({0})" -f $_.Exception.Message) Yellow
        }
    }
    # Itineraire : la plus recente entre GitHub et le dossier fourni a cote du script.
    $itiGitVersion = if ($itiAsset) { ($itiAsset.Name -replace '^Itineraire-v', '') -replace '\.zip$', '' } else { $null }
    $itiFrom = $null
    if ($itiGitVersion -and (Compare-AddonVersion $bundledVersion $itiGitVersion) -gt 0) { $itiFrom = 'github' }
    elseif ($bundledVersion) { $itiFrom = 'fourni' }
    $itiOffered = if ($itiFrom -eq 'github') { $itiGitVersion } else { $bundledVersion }
    if ($itiFrom) {
        $plan.Add([pscustomobject]@{ Name = 'Itineraire'; Offered = $itiOffered; Source = $null; From = $itiFrom })
    } else {
        Say "(Itineraire : ni version sur GitHub ni dossier a cote du script, il n'est pas mis a jour)" Yellow
    }

    Title 'Etat'
    foreach ($item in $plan) {
        $installed = Get-AddonVersion (Join-Path $addOns $item.Name) $item.Name
        $item | Add-Member -NotePropertyName Installed -NotePropertyValue $installed
        # (QuestieDB et ForeverCore ont leur propre numero, lu dans l'archive au moment d'installer)
        $label = if ($installed) { $installed } else { 'absent' }
        if ($item.Source) {
            Say ("   {0,-22} installe : {1}" -f $item.Name, $label)
        } else {
            Say ("   {0,-22} installe : {1,-14} propose : {2} ({3})" -f $item.Name, $label, $item.Offered, $item.From)
        }
    }
    $fcAlone = Get-AddonVersion (Join-Path $addOns 'ForeverCore') 'ForeverCore'
    $fcEmbedded = Get-EmbeddedForeverCore $addOns
    $fcAloneLabel = if ($fcAlone) { $fcAlone } else { 'non' }
    $fcEmbeddedLabel = if ($fcEmbedded) { "$($fcEmbedded.Version) (dans $($fcEmbedded.Addon))" } else { '-' }
    Say ("   {0,-22} a part : {1,-16} inclus : {2}" -f 'ForeverCore', $fcAloneLabel, $fcEmbeddedLabel)
    $djLabel = if ($djInstalled) { $djInstalled } else { 'absent' }
    $djOffer = if ($djLatest) { $djLatest.Version } elseif ($SansDungeonJournal) { 'non demande' } else { '?' }
    Say ("   {0,-22} installe : {1,-14} propose : {2} (CurseForge, ExehnTV)" -f 'DungeonJournal', $djLabel, $djOffer)
    foreach ($g in $OtherGuides) {
        if (Test-Path -LiteralPath (Join-Path $addOns $g)) {
            Say "   (autre guide present : $g - Itineraire le desactive au lancement)" DarkYellow
        }
    }
    $task = Get-AutoTask
    Say ("   mise a jour automatique : " + $(if ($task) { 'active' } else { 'non' }))
    if ($Verifier) { Say ''; Say 'Verification seulement : rien n''a ete modifie.' Green; return }

    $running = @(Get-Process -Name 'Wow', 'WowClassic', 'WowT', 'WowB' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0 -and -not $Oui) {
        Say ''
        Say 'World of Warcraft est ouvert. Quitte-le completement (pas seulement /reload) avant de continuer :' Yellow
        Say 'de nouveaux fichiers ne sont pris en compte qu''au prochain lancement du jeu.' Yellow
        $answer = Read-Host 'Continuer quand meme ? (o/N)'
        if ($answer -notmatch '^[oOyY]') { throw 'Installation annulee.' }
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupRoot = Join-Path (Join-Path $forever 'Interface\AddOns_sauvegardes') $stamp
    $stage = Join-Path $forever ("Interface\_itineraire_installation_" + $stamp)
    [void](New-Item -ItemType Directory -Path $stage)
    if (-not (Test-Path -LiteralPath $addOns)) { [void](New-Item -ItemType Directory -Path $addOns -Force) }
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ("itineraire-" + $stamp)
    [void](New-Item -ItemType Directory -Path $tempDir)
    $changed = New-Object System.Collections.Generic.List[string]
    $failed = New-Object System.Collections.Generic.List[string]

    # Questie, Shortest Path (telecharges, verifies, extraits a part puis installes)
    foreach ($src in $Sources) {
        if ($SansTelechargement) { break }
        $items = @($plan | Where-Object { $_.Source -eq $src })
        if ($items.Count -eq 0) { continue }
        Title $src.Repo
        $asset = $assets[$src.Repo]
        # Deja a jour d'apres le nom du fichier (ex. Questie-v12.9.0+v1.1.1 = Questie 12.9.0 + QuestieDB 1.1.1) :
        # on evite de retelecharger 100 Mo pour rien.
        $offered = $items[0].Offered
        $needed = $false
        foreach ($item in $items) { if (-not $item.Installed) { $needed = $true } }
        if ((Compare-AddonVersion $items[0].Installed (($offered -split '\+')[0])) -gt 0) { $needed = $true }
        if ($offered -match '\+v?([0-9][0-9.]*)$' -and $items.Count -gt 1) {
            if ((Compare-AddonVersion $items[1].Installed $Matches[1]) -gt 0) { $needed = $true }
        }
        if (-not $needed) {
            Say ("   {0} : deja a jour, rien a telecharger." -f ($src.Addons -join ' + '))
            continue
        }
        try {
            $zip = Save-Asset $asset $tempDir
            $srcStage = Join-Path $stage ($src.Addons[0])
            [void](New-Item -ItemType Directory -Path $srcStage)
            $skipped = Expand-Checked $zip $srcStage (@($src.Addons) + @($src.Optional))
            foreach ($s in $skipped) {
                if ($src.Ignore -contains $s) { Say "   $s laisse de cote (il se dispute la fleche avec Itineraire)." DarkGray }
                else { Say "   dossier inattendu ignore : $s" DarkYellow }
            }
            foreach ($item in $items) {
                $staged = Join-Path $srcStage $item.Name
                if (-not (Test-Path -LiteralPath $staged -PathType Container) -or -not (Get-ChildItem -LiteralPath $staged -Filter '*.toc' -File)) {
                    throw "Archive incomplete : pas de $($item.Name) avec son fichier .toc."
                }
                $offered = Get-AddonVersion $staged $item.Name
                $cmp = Compare-AddonVersion $item.Installed $offered
                if ($cmp -gt 0) {
                    Install-Addon $item.Name $staged $addOns $backupRoot
                    $was = if ($item.Installed) { $item.Installed } else { 'absent' }
                    Say ("   {0} : {1} -> {2}" -f $item.Name, $was, $offered) Green
                    $changed.Add($item.Name)
                } elseif ($cmp -eq 0) {
                    Say ("   {0} {1} : deja a jour." -f $item.Name, $offered)
                } else {
                    Say ("   {0} : la version installee ({1}) est plus recente que {2}, gardee." -f $item.Name, $item.Installed, $offered) DarkYellow
                }
            }
            # Facultatifs (ForeverCore a part) : mis a jour s'ils sont deja installes, installes seulement si un addon
            # de l'archive les exige ; absents de l'archive : rien a faire.
            foreach ($name in @($src.Optional)) {
                $staged = Join-Path $srcStage $name
                if (-not (Test-Path -LiteralPath $staged -PathType Container)) { continue }
                $installed = Get-AddonVersion (Join-Path $addOns $name) $name
                if (-not $installed -and -not (Get-StandaloneUser $srcStage $name)) { continue }
                $offered = Get-AddonVersion $staged $name
                if ((Compare-AddonVersion $installed $offered) -gt 0) {
                    Install-Addon $name $staged $addOns $backupRoot
                    $was = if ($installed) { $installed } else { 'absent' }
                    Say ("   {0} : {1} -> {2}" -f $name, $was, $offered) Green
                    $changed.Add($name)
                }
            }
        } catch {
            Say ("   ERREUR pour {0} : {1} (les versions en place sont gardees)" -f $src.Repo, $_.Exception.Message) Red
            $failed.Add($src.Repo)
        }
    }

    # ForeverCore installe a part mais plus ancien que la copie incluse dans Shortest Path : retire.
    if (-not $SansTelechargement) {
        Title 'ForeverCore'
        try {
            if (Remove-StaleForeverCore $addOns $backupRoot) { $changed.Add('ForeverCore (retire)') }
            else {
                $embedded = Get-EmbeddedForeverCore $addOns
                if ($embedded) { Say "   ForeverCore $($embedded.Version) : inclus dans $($embedded.Addon), rien a faire." }
                else { Say '   rien a faire.' }
            }
        } catch {
            Say ("   ERREUR pour ForeverCore : {0}" -f $_.Exception.Message) Red
            $failed.Add('ForeverCore')
        }
    }

    # DungeonJournal (ExehnTV, CurseForge) : lu par Itineraire pendant le jeu
    if ($djLatest) {
        Title 'DungeonJournal (CurseForge, ExehnTV)'
        $cmp = Compare-AddonVersion $djInstalled $djLatest.Version
        if ($cmp -gt 0) {
            try {
                $zip = Save-CurseFile $djLatest $tempDir
                Test-ZipContent $zip @($DjSource.Folder) $DjExtensions $DjMaxBytes
                $djStage = Join-Path $stage '_dj'
                [void](New-Item -ItemType Directory -Path $djStage)
                [void](Expand-Checked $zip $djStage @($DjSource.Folder))
                $from = Join-Path $djStage $DjSource.Folder
                $toc = Join-Path $from ($DjSource.Folder + '.toc')
                if (-not (Test-Path -LiteralPath $toc -PathType Leaf)) { throw "Archive incomplete : pas de $($DjSource.Folder).toc." }
                $head = (Get-Content -LiteralPath $toc -TotalCount 30 -Encoding UTF8) -join "`n"
                if ($head -notmatch '(?m)^##\s*Title:\s*DungeonJournal\s*$' -or $head -notmatch '(?m)^##\s*Author:\s*Exehn\b') {
                    throw "le fichier .toc n'est pas celui de DungeonJournal (ExehnTV)."
                }
                $real = Get-AddonVersion $from $DjSource.Folder
                if ($real -ne $djLatest.Version) { throw "l'archive contient la version $real au lieu de $($djLatest.Version)." }
                Install-Addon $DjSource.Folder $from $addOns $backupRoot
                $was = if ($djInstalled) { $djInstalled } else { 'absent' }
                Say ("   DungeonJournal : {0} -> {1}" -f $was, $real) Green
                $changed.Add('DungeonJournal')
            } catch {
                Say ("   ERREUR pour DungeonJournal : {0} (la version en place est gardee)" -f $_.Exception.Message) Red
                $failed.Add('DungeonJournal')
            }
        } elseif ($cmp -eq 0) {
            Say "   DungeonJournal $($djLatest.Version) : deja a jour."
        } else {
            Say "   DungeonJournal : la version installee ($djInstalled) est plus recente que $($djLatest.Version), gardee." DarkYellow
        }
    }

    # Itineraire
    $iti = @($plan | Where-Object { $_.Name -eq 'Itineraire' }) | Select-Object -First 1
    if ($iti) {
        Title 'Itineraire'
        $cmp = Compare-AddonVersion $iti.Installed $iti.Offered
        if ($cmp -gt 0) {
            try {
                $itiStage = Join-Path $stage 'Itineraire'
                if ($iti.From -eq 'github') {
                    $zip = Save-Asset $itiAsset $tempDir
                    $gitStage = Join-Path $stage '_iti'
                    [void](New-Item -ItemType Directory -Path $gitStage)
                    [void](Expand-Checked $zip $gitStage @('Itineraire'))
                    $from = Join-Path $gitStage 'Itineraire'
                    if (-not (Test-Path -LiteralPath (Join-Path $from 'Itineraire.toc'))) { throw 'Archive incomplete : pas de Itineraire.toc.' }
                    $real = Get-AddonVersion $from 'Itineraire'
                    if ((Compare-AddonVersion $iti.Installed $real) -le 0) { throw "l'archive contient la version $real, pas plus recente." }
                    Move-Item -LiteralPath $from -Destination $itiStage
                } else {
                    Copy-Item -LiteralPath $bundled -Destination $itiStage -Recurse
                }
                Install-Addon 'Itineraire' $itiStage $addOns $backupRoot
                $was = if ($iti.Installed) { $iti.Installed } else { 'absent' }
                Say ("   Itineraire : {0} -> {1}" -f $was, $iti.Offered) Green
                $changed.Add('Itineraire')
            } catch {
                Say ("   ERREUR pour Itineraire : {0} (la version en place est gardee)" -f $_.Exception.Message) Red
                $failed.Add('Itineraire')
            }
        } elseif ($cmp -eq 0) {
            Say "   Itineraire $($iti.Offered) : deja a jour."
        } else {
            Say "   Itineraire : la version installee ($($iti.Installed)) est plus recente que $($iti.Offered), gardee." DarkYellow
        }
    }

    # Mise a jour automatique : activee sur demande, proposee au premier passage a la main.
    if ($ActiverMajAuto) {
        Title 'Mise a jour automatique'
        Enable-AutoUpdate $forever
    } elseif (-not $Auto) {
        $task = Get-AutoTask
        if ($task) {
            # Installateur plus recent lance a la main : la tache utilisera desormais cette version-ci.
            $self = $MyInvocation.MyCommand.Path
            if ((Test-Path -LiteralPath $AutoScript) -and ((Get-FileHash -LiteralPath $self).Hash -ne (Get-FileHash -LiteralPath $AutoScript).Hash)) {
                Copy-Item -LiteralPath $self -Destination $AutoScript -Force
                Say "   mise a jour automatique : elle utilise maintenant cet installateur (v$InstallerVersion)." Green
            }
        } elseif (-not $Oui) {
            Say ''
            Say 'Mise a jour automatique : Itineraire, Questie, Shortest Path et DungeonJournal restent a jour tout seuls' White
            Say '(verification a l''ouverture de session puis toutes les 4 h, sans fenetre, jamais quand WoW est' White
            Say 'ouvert ; desactivable en relancant avec -DesactiverMajAuto).' White
            $answer = Read-Host 'Activer la mise a jour automatique ? (O/n)'
            if ($answer -notmatch '^[nN]') { Enable-AutoUpdate $forever }
        }
    }
    Write-InstallerInfo $addOns

    Title 'Termine'
    if ($changed.Count -gt 0) {
        Say ("   Installe / mis a jour : " + ($changed -join ', ')) Green
        if (Test-Path -LiteralPath $backupRoot) { Say "   Anciennes versions sauvegardees dans : $backupRoot" }
    } else {
        Say '   Tout etait deja a jour.' Green
    }
    if ($failed.Count -gt 0) {
        Say ("   Pas mis a jour (reessaye plus tard) : " + ($failed -join ', ')) Yellow
        $exit = 1
    }
    Clear-OldBackups (Join-Path $forever 'Interface\AddOns_sauvegardes')
    if ($Auto) {
        if ($failed.Count -eq 0) { Set-Content -LiteralPath $StampFile -Value (Get-Date -Format 's') -Encoding ASCII }
    } else {
        Say '   Lance WoW Forever : au premier lancement, Itineraire pose 5 questions pour tout regler.'
    }
} catch {
    Say ''
    Say ("ERREUR : " + $_.Exception.Message) Red
    Say 'Rien n''a ete casse : les addons deja en place sont restes (ou sont dans AddOns_sauvegardes).' Yellow
    $exit = 1
} finally {
    if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    if ($tempDir -and (Test-Path -LiteralPath $tempDir)) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}
exit $exit
