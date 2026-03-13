# ============================================================================
# INSTALLATEUR AUTOMATIQUE - Application Controle Qualite
# Usage : .\installer.ps1
# Options : -SkipSeed     (ne pas injecter les donnees de demo)
#
# Ce script detecte automatiquement la meilleure methode pour MySQL :
#   1. Docker Desktop (si disponible et demarre)
#   2. MySQL deja installe localement
#   3. Telechargement automatique de MySQL portable (ZIP, aucune install)
# ============================================================================

param(
  [switch]$SkipSeed,
  [switch]$SkipDocker
)

$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = "Installation - Controle Qualite"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$composeFile = Join-Path $projectRoot "docker-compose.yml"
Set-Location $projectRoot

# -- Couleurs --
function Write-Step  { param([string]$Msg) Write-Host "`n===> $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "  [!] $Msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$Msg) Write-Host "  [ERREUR] $Msg" -ForegroundColor Red }

function Test-Command {
  param([string]$Name)
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-MySqlExeFromServicePath {
  param([string]$ServicePath)

  if ([string]::IsNullOrWhiteSpace($ServicePath)) { return $null }

  # Extrait le chemin de mysqld.exe meme si des arguments suivent.
  if ($ServicePath -match '"([^"]*mysqld\.exe)"') {
    return (Join-Path (Split-Path $matches[1] -Parent) "mysql.exe")
  }
  if ($ServicePath -match '^([^\s]*mysqld\.exe)') {
    return (Join-Path (Split-Path $matches[1] -Parent) "mysql.exe")
  }

  return $null
}

function Resolve-LocalMySqlPort {
  param([string]$MySqlExePath)

  $candidatePorts = @(3307, 3306)
  foreach ($port in $candidatePorts) {
    try {
      & $MySqlExePath -u root --port=$port -e "SELECT 1" 2>&1 | Out-Null
      if ($LASTEXITCODE -eq 0) { return $port }
    } catch {}
  }

  # Fallback: garder la valeur par defaut si test anonyme impossible.
  return $mysqlPort
}

function Restart-WithoutDocker {
  param([string]$Reason)

  Write-Warn $Reason
  Write-Warn "Bascule automatique en mode sans Docker (MySQL local/portable)..."

  $psArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $PSCommandPath,
    "-SkipDocker"
  )

  if ($SkipSeed) { $psArgs += "-SkipSeed" }

  & powershell.exe @psArgs
  exit $LASTEXITCODE
}

# --------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "     INSTALLATION - Application Controle Qualite            " -ForegroundColor Cyan
Write-Host "     Version 1.0.0                                         " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# --------------------------------------------------------------------------
# ETAPE 1 : Verification des prerequis
# --------------------------------------------------------------------------
Write-Step "Verification des prerequis"

# Node.js
if (-not (Test-Command "node")) {
  Write-Err "Node.js n'est pas installe."
  Write-Host "  Telechargez-le ici : https://nodejs.org/fr (version LTS)" -ForegroundColor Yellow
  Write-Host "  Redemarrez PowerShell apres l'installation." -ForegroundColor Yellow
  Read-Host "Appuyez sur Entree pour quitter"
  exit 1
}
$nodeVersion = (node -v)
Write-Ok "Node.js $nodeVersion detecte"

# npm
if (-not (Test-Command "npm")) {
  Write-Err "npm n'est pas disponible. Reinstallez Node.js."
  Read-Host "Appuyez sur Entree pour quitter"
  exit 1
}
$npmVersion = (npm -v)
Write-Ok "npm v$npmVersion detecte"

# --------------------------------------------------------------------------
# ETAPE 2 : Detection de la methode MySQL
# --------------------------------------------------------------------------
Write-Step "Detection de MySQL"

$mysqlMode = "none"       # docker | local | portable
$mysqlBin  = ""           # chemin vers mysql.exe client
$mysqlPort = 3307
$dbUser    = "root"
$dbPass    = "base@controle"
$dbName    = "controle_qualite"
$portableDir = Join-Path $PSScriptRoot "..\mysql-portable"

# --- Option 1 : Docker disponible et demarre ---
$dockerAvailable = $false
if (-not $SkipDocker -and (Test-Command "docker")) {
  try {
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $dockerAvailable = $true }
  } catch {}
}

if ($dockerAvailable) {
  Write-Ok "Docker Desktop detecte et demarre"
  $mysqlMode = "docker"
} elseif ($SkipDocker) {
  Write-Warn "Mode sans Docker force. Recherche MySQL local/portable."
}

# --- Option 2 : MySQL installe localement (service Windows) ---
if ($mysqlMode -eq "none") {
  # Chercher un service MySQL en cours d'execution
  $mysqlService = Get-WmiObject Win32_Service -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "mysql" -and $_.State -eq "Running" } |
    Select-Object -First 1

  if ($mysqlService) {
    # Extraire mysql.exe du chemin du service (avec ou sans arguments).
    $localMysqlExe = Get-MySqlExeFromServicePath $mysqlService.PathName
    if (Test-Path $localMysqlExe) {
      $mysqlBin = $localMysqlExe
      $mysqlMode = "local"
      $mysqlPort = Resolve-LocalMySqlPort $mysqlBin
      Write-Ok "MySQL local detecte (service: $($mysqlService.Name))"
      Write-Host "  Port detecte: $mysqlPort" -ForegroundColor Gray
      Write-Host "  Client: $mysqlBin" -ForegroundColor Gray
    }
  }

  # Dossiers standard MySQL si le service est detecte mais mysql.exe introuvable.
  if ($mysqlMode -eq "none") {
    $commonMysqlBins = @(
      "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe",
      "C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe",
      "C:\xampp\mysql\bin\mysql.exe"
    )
    foreach ($candidate in $commonMysqlBins) {
      if (Test-Path $candidate) {
        $mysqlBin = $candidate
        $mysqlMode = "local"
        $mysqlPort = Resolve-LocalMySqlPort $mysqlBin
        Write-Ok "MySQL local detecte (dossier standard)"
        Write-Host "  Port detecte: $mysqlPort" -ForegroundColor Gray
        Write-Host "  Client: $mysqlBin" -ForegroundColor Gray
        break
      }
    }
  }

  # Chercher dans le PATH aussi
  if ($mysqlMode -eq "none" -and (Test-Command "mysql")) {
    $mysqlBin = (Get-Command "mysql").Source
    $mysqlMode = "local"
    $mysqlPort = Resolve-LocalMySqlPort $mysqlBin
    Write-Ok "MySQL local detecte dans le PATH"
    Write-Host "  Port detecte: $mysqlPort" -ForegroundColor Gray
  }
}

# --- Option 3 : MySQL portable deja telecharge ---
if ($mysqlMode -eq "none") {
  $portableMysqlExe = Join-Path $portableDir "bin\mysql.exe"
  $portableMysqldExe = Join-Path $portableDir "bin\mysqld.exe"
  if ((Test-Path $portableMysqlExe) -and (Test-Path $portableMysqldExe)) {
    $mysqlBin = $portableMysqlExe
    $mysqlMode = "portable"
    Write-Ok "MySQL portable trouve dans: $portableDir"
  }
}

# --- Option 4 : Telecharger MySQL portable ---
if ($mysqlMode -eq "none") {
  Write-Warn "Aucun MySQL detecte (pas de Docker, pas de MySQL local)"
  Write-Host ""
  Write-Host "  Le script va telecharger MySQL portable (~200 MB)." -ForegroundColor Yellow
  Write-Host "  Aucune installation Windows n'est necessaire." -ForegroundColor Yellow
  Write-Host ""
  $confirm = Read-Host "  Continuer ? (O/n)"
  if ($confirm -eq "n" -or $confirm -eq "N") {
    Write-Err "Installation annulee."
    Write-Host "  Vous pouvez :" -ForegroundColor Yellow
    Write-Host "    - Installer Docker Desktop : https://www.docker.com/products/docker-desktop/" -ForegroundColor Yellow
    Write-Host "    - Installer MySQL : https://dev.mysql.com/downloads/installer/" -ForegroundColor Yellow
    Write-Host "    - Relancer ce script apres l'installation" -ForegroundColor Yellow
    Read-Host "Appuyez sur Entree pour quitter"
    exit 1
  }

  Write-Step "Telechargement de MySQL portable"

  $mysqlZipUrl = "https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.36-winx64.zip"
  $zipPath = Join-Path $env:TEMP "mysql-portable.zip"
  $extractPath = Join-Path $env:TEMP "mysql-extract"

  Write-Host "  Telechargement en cours..." -ForegroundColor Gray
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $mysqlZipUrl -OutFile $zipPath -UseBasicParsing
    $ProgressPreference = 'Continue'
  } catch {
    Write-Err "Echec du telechargement de MySQL."
    Write-Host "  Verifiez votre connexion Internet." -ForegroundColor Yellow
    Write-Host "  Vous pouvez aussi telecharger manuellement depuis :" -ForegroundColor Yellow
    Write-Host "  https://dev.mysql.com/downloads/mysql/" -ForegroundColor Yellow
    Read-Host "Appuyez sur Entree pour quitter"
    exit 1
  }
  Write-Ok "Telechargement termine"

  Write-Host "  Extraction..." -ForegroundColor Gray
  if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
  Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

  # Trouver le dossier extrait (ex: mysql-8.0.36-winx64)
  $extractedFolder = Get-ChildItem $extractPath -Directory | Select-Object -First 1
  if (-not $extractedFolder) {
    Write-Err "Echec de l'extraction du ZIP MySQL."
    Read-Host "Appuyez sur Entree pour quitter"
    exit 1
  }

  # Deplacer vers le dossier portable
  if (Test-Path $portableDir) { Remove-Item $portableDir -Recurse -Force }
  Move-Item -Path $extractedFolder.FullName -Destination $portableDir -Force

  # Nettoyage
  Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
  Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

  $mysqlBin = Join-Path $portableDir "bin\mysql.exe"
  $mysqlMode = "portable"
  Write-Ok "MySQL portable installe dans: $portableDir"
}

Write-Host ""
Write-Host "  Mode MySQL : $mysqlMode" -ForegroundColor White

# --------------------------------------------------------------------------
# ETAPE 3 : Configuration (.env)
# --------------------------------------------------------------------------
Write-Step "Configuration de l'environnement"

# Generer un JWT_SECRET aleatoire securise
$jwtSecret = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 64 | ForEach-Object { [char]$_ })

if ($mysqlMode -eq "docker") {
  $dbUrlForEnv = "mysql://qcuser:qc_secure_password@localhost:$mysqlPort/$dbName"
} else {
  $dbPassEncoded = [System.Uri]::EscapeDataString($dbPass)
  $dbUrlForEnv = "mysql://${dbUser}:${dbPassEncoded}@localhost:${mysqlPort}/${dbName}"
}

if (-not (Test-Path ".env")) {
  $envContent = @"
# ============================================================================
# CONFIGURATION - Controle Qualite (generee automatiquement)
# Mode MySQL : $mysqlMode
# ============================================================================

# Base de donnees MySQL
DATABASE_URL="$dbUrlForEnv"
DATABASE_POOL_SIZE=10

# JWT (secret auto-genere)
JWT_SECRET="$jwtSecret"

# Application
NEXT_PUBLIC_APP_URL="http://localhost:3000"
NODE_ENV="development"

# Logging
LOG_LEVEL="INFO"
SLOW_QUERY_THRESHOLD=500

# Docker (utilise uniquement en mode Docker)
APP_PORT=3000
DB_PORT=$mysqlPort
MYSQL_ROOT_PASSWORD="$dbPass"
MYSQL_DATABASE="$dbName"
MYSQL_PASSWORD="qc_secure_password"
ADMINER_PORT=8080
"@
  
  $envContent | Out-File -FilePath ".env" -Encoding utf8 -NoNewline
  Write-Ok "Fichier .env cree (mode: $mysqlMode)"
} else {
  Write-Ok "Fichier .env deja existant (conserve)"
}

# --------------------------------------------------------------------------
# ETAPE 4 : Demarrage de MySQL
# --------------------------------------------------------------------------
Write-Step "Demarrage de la base de donnees MySQL"

if ($mysqlMode -eq "docker") {
  # --- Mode Docker ---
  $composeUpOutput = cmd /c "docker compose -f ""$composeFile"" --project-directory ""$projectRoot"" up -d db 2>&1"
  if ($LASTEXITCODE -ne 0) {
    # Compatibilite avec d'anciens packages qui utilisaient le nom fixe 'qc-db'.
    if ($composeUpOutput -match 'container name "/qc-db" is already in use') {
      Write-Warn "Un ancien conteneur 'qc-db' bloque le demarrage. Suppression puis nouvelle tentative."
      cmd /c "docker rm -f qc-db 2>&1" | Out-Null
      cmd /c "docker compose -f ""$composeFile"" --project-directory ""$projectRoot"" up -d db 2>&1" | Out-Null
    }

    if ($LASTEXITCODE -ne 0) {
      Restart-WithoutDocker "Echec du demarrage Docker (service db)."
    }
  }

  $dbContainerId = (cmd /c "docker compose -f ""$composeFile"" --project-directory ""$projectRoot"" ps -q db").Trim()
  if ([string]::IsNullOrWhiteSpace($dbContainerId)) {
    Write-Warn "Docker n'a pas cree le service 'db' pour ce projet."
    Write-Host "  Etat compose:" -ForegroundColor Yellow
    cmd /c "docker compose -f ""$composeFile"" --project-directory ""$projectRoot"" ps"
    Write-Host "  Logs db:" -ForegroundColor Yellow
    cmd /c "docker compose -f ""$composeFile"" --project-directory ""$projectRoot"" logs db --tail 100"
    Restart-WithoutDocker "Le service Docker 'db' est introuvable."
  }
  
  Write-Ok "Conteneur MySQL demarre"
  Write-Host "  Attente que MySQL soit pret (peut prendre 30-60 secondes)..." -ForegroundColor Gray
  
  $maxRetries = 30
  $retry = 0
  $mysqlReady = $false
  do {
    Start-Sleep -Seconds 3
    $retry++
    try {
      $result = cmd /c "docker compose -f ""$composeFile"" --project-directory ""$projectRoot"" exec -T db mysqladmin ping -h localhost -u qcuser -pqc_secure_password 2>&1"
      if ($result -match "alive") {
        $mysqlReady = $true
      }
    } catch {}
    Write-Host "  [$retry/$maxRetries] Attente..." -ForegroundColor Gray
  } while (-not $mysqlReady -and $retry -lt $maxRetries)
  
  if ($mysqlReady) {
    Write-Ok "MySQL Docker est pret"
  } else {
    Write-Warn "MySQL Docker n'a pas repondu dans le delai."
    Write-Host "  Verifiez avec: docker compose ps ; docker compose logs db --tail 100" -ForegroundColor Yellow
    Restart-WithoutDocker "MySQL Docker ne demarre pas correctement."
  }

} elseif ($mysqlMode -eq "portable") {
  # --- Mode Portable : initialiser et demarrer mysqld ---
  $mysqldExe = Join-Path $portableDir "bin\mysqld.exe"
  $dataDir = Join-Path $portableDir "data"

  if (-not (Test-Path $dataDir)) {
    Write-Host "  Initialisation de MySQL portable (premiere fois)..." -ForegroundColor Gray
    & $mysqldExe --initialize-insecure --basedir="$portableDir" --datadir="$dataDir" 2>&1 | Out-Null
    Write-Ok "MySQL portable initialise (sans mot de passe root)"
  }

  # Verifier si mysqld est deja en cours d'execution
  $mysqldProcess = Get-Process mysqld -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path -like "*mysql-portable*" }

  if (-not $mysqldProcess) {
    Write-Host "  Demarrage du serveur MySQL portable..." -ForegroundColor Gray
    Start-Process -FilePath $mysqldExe -ArgumentList "--basedir=`"$portableDir`"","--datadir=`"$dataDir`"","--port=$mysqlPort","--console" -WindowStyle Hidden
    
    # Attendre que MySQL reponde
    $maxRetries = 20
    $retry = 0
    $mysqlReady = $false
    do {
      Start-Sleep -Seconds 2
      $retry++
      try {
        $result = & $mysqlBin -u root --port=$mysqlPort -e "SELECT 1" 2>&1
        if ($LASTEXITCODE -eq 0) { $mysqlReady = $true }
      } catch {}
      Write-Host "  [$retry/$maxRetries] Attente..." -ForegroundColor Gray
    } while (-not $mysqlReady -and $retry -lt $maxRetries)
    
    if ($mysqlReady) {
      Write-Ok "MySQL portable demarre et operationnel"
    } else {
      Write-Err "MySQL portable n'a pas repondu."
      Read-Host "Appuyez sur Entree pour quitter"
      exit 1
    }
  } else {
    Write-Ok "MySQL portable est deja en cours d'execution"
  }

  # Creer la base de donnees et l'utilisateur
  Write-Host "  Creation de la base de donnees..." -ForegroundColor Gray
  & $mysqlBin -u root --port=$mysqlPort -e "CREATE DATABASE IF NOT EXISTS ``$dbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>&1 | Out-Null
  & $mysqlBin -u root --port=$mysqlPort -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$dbPass';" 2>&1 | Out-Null
  Write-Ok "Base de donnees '$dbName' creee"

} elseif ($mysqlMode -eq "local") {
  # --- Mode Local : MySQL deja en cours, creer la base ---
  Write-Host "  MySQL local detecte. Creation de la base de donnees..." -ForegroundColor Gray

  # Tester d'abord sans mot de passe (evite l'echec PowerShell sur stderr MySQL).
  $useRootPassword = $false
  cmd /c """$mysqlBin"" -u root --port=$mysqlPort -e ""SELECT 1"" 2>&1" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  MySQL necessite un mot de passe root." -ForegroundColor Yellow
    $securePass = Read-Host "  Entrez le mot de passe root MySQL" -AsSecureString
    $dbPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
    )
    $useRootPassword = $true
  } else {
    $dbPass = ""
  }

  if ($useRootPassword) {
    cmd /c """$mysqlBin"" -u root -p""$dbPass"" --port=$mysqlPort -e ""CREATE DATABASE IF NOT EXISTS ``$dbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"" 2>&1" | Out-Null
  } else {
    cmd /c """$mysqlBin"" -u root --port=$mysqlPort -e ""CREATE DATABASE IF NOT EXISTS ``$dbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"" 2>&1" | Out-Null
  }

  if ($LASTEXITCODE -ne 0) {
    Write-Err "Impossible de se connecter a MySQL. Verifiez le mot de passe."
    Read-Host "Appuyez sur Entree pour quitter"
    exit 1
  }

  # Mettre a jour le .env avec la bonne methode d'authentification.
  if ($useRootPassword) {
    $dbPassEncoded = [System.Uri]::EscapeDataString($dbPass)
    $newDbUrl = "mysql://${dbUser}:${dbPassEncoded}@localhost:${mysqlPort}/${dbName}"
  } else {
    $newDbUrl = "mysql://${dbUser}@localhost:${mysqlPort}/${dbName}"
  }
  $envText = Get-Content ".env" -Raw
  $envText = $envText -replace 'DATABASE_URL="[^"]*"', "DATABASE_URL=`"$newDbUrl`""
  $envText | Out-File -FilePath ".env" -Encoding utf8 -NoNewline

  Write-Ok "Base de donnees '$dbName' creee sur MySQL local"
}

# --------------------------------------------------------------------------
# ETAPE 5 : Installation des dependances
# --------------------------------------------------------------------------
Write-Step "Installation des dependances npm"

npm install
if ($LASTEXITCODE -ne 0) {
  Write-Err "Echec de l'installation des dependances npm."
  Read-Host "Appuyez sur Entree pour quitter"
  exit 1
}

Write-Ok "Dependances installees"

# --------------------------------------------------------------------------
# ETAPE 6 : Configuration de la base de donnees (Prisma)
# --------------------------------------------------------------------------
Write-Step "Configuration de la base de donnees"

Write-Host "  Generation du client Prisma..." -ForegroundColor Gray
npx prisma generate
if ($LASTEXITCODE -ne 0) {
  Write-Err "Echec de la generation du client Prisma."
  Read-Host "Appuyez sur Entree pour quitter"
  exit 1
}
Write-Ok "Client Prisma genere"

Write-Host "  Creation des tables..." -ForegroundColor Gray
npx prisma db push
if ($LASTEXITCODE -ne 0) {
  Write-Err "Echec de la creation des tables Prisma."
  Read-Host "Appuyez sur Entree pour quitter"
  exit 1
}
Write-Ok "Tables creees dans la base de donnees"

# --------------------------------------------------------------------------
# ETAPE 7 : Donnees de demonstration (seed)
# --------------------------------------------------------------------------
if (-not $SkipSeed) {
  Write-Step "Injection des donnees de demonstration"
  
  npx prisma db seed
  if ($LASTEXITCODE -ne 0) {
    Write-Err "Echec de l'injection des donnees de demonstration."
    Read-Host "Appuyez sur Entree pour quitter"
    exit 1
  }
  Write-Ok "Donnees de demonstration injectees"
}

# --------------------------------------------------------------------------
# RESUME FINAL
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "          INSTALLATION TERMINEE AVEC SUCCES !               " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Mode MySQL : $mysqlMode" -ForegroundColor White
Write-Host ""
Write-Host "  Pour lancer l'application :" -ForegroundColor White
Write-Host "    npm run dev" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Puis ouvrez votre navigateur :" -ForegroundColor White
Write-Host "    http://localhost:3000" -ForegroundColor Yellow
Write-Host ""
Write-Host "  ----------------------------------------------------------" -ForegroundColor White
Write-Host "    Comptes de connexion :                                   " -ForegroundColor White
Write-Host "                                                             " -ForegroundColor White
Write-Host "    Admin      : admin@entreprise.com / Admin@2026           " -ForegroundColor White
Write-Host "    Controleur : controleur@entreprise.com / Ctrl@2026       " -ForegroundColor White
Write-Host "    Controleur : labo@entreprise.com / Labo@2026             " -ForegroundColor White
Write-Host "  ----------------------------------------------------------" -ForegroundColor White
if ($mysqlMode -eq "portable") {
  Write-Host ""
  Write-Host "  NOTE: MySQL portable est lance en arriere-plan." -ForegroundColor Yellow
  Write-Host "  Pour l'arreter : Get-Process mysqld | Stop-Process" -ForegroundColor Yellow
  Write-Host "  Pour le relancer : .\installer.ps1 -SkipSeed" -ForegroundColor Yellow
}
Write-Host ""

Read-Host "Appuyez sur Entree pour fermer"
