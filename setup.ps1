###############################################################################
# Agent Boshi - One-Click Setup (Windows PowerShell)
#
# What this does:
#   1. Asks you to pick a model tier based on your GPU VRAM
#   2. Installs Ollama + Hermes Agent
#   3. Pulls the selected coding model
#   4. Deploys Agent Boshi's personality (SOUL.md) and skills
#   5. Opens the Hermes dashboard in your browser
#
# Usage (run in PowerShell):
#   .\setup.ps1                     # Interactive setup
#   .\setup.ps1 -Cpu                # CPU-only mode
#   .\setup.ps1 -Tier 3             # Skip menu, use tier 3 (16GB)
#   .\setup.ps1 -Tier 4 -Alt        # Use alternate model for tier 4-5
#
# Model Tiers (best coding models):
#   1  CPU-only   gemma4:e4b             (~3GB)   Needs 8GB+ RAM
#   2  8GB VRAM   qwen2.5-coder:7b       (~5GB)   RTX 3060 / 4060
#   3  16GB VRAM  devstral (24B)          (~14GB)  RTX 4080 / 4070Ti-16GB
#   4  24GB VRAM  qwen3.6:27b            (~17GB)  RTX 4090
#                 or devstral             (~14GB)  with -Alt
#   5  32GB VRAM  qwen3.6:27b-q8_0       (~30GB)  RTX 5090 / A6000 (SWE-bench king Q8)
#                 or qwen3-coder:30b      (~19GB)  with -Alt (MoE, faster)
###############################################################################

param(
    [switch]$Cpu,
    [switch]$Alt,
    [switch]$Help,
    [switch]$Uninstall,
    [string]$OllamaUrl = "",
    [ValidateRange(1,5)][int]$Tier = 0
)

$ErrorActionPreference = "Stop"

# -- Banner -------------------------------------------------------------------
Write-Host ""
Write-Host "  +========================================================+" -ForegroundColor Magenta
Write-Host "  |                                                        |" -ForegroundColor Magenta
Write-Host "  |   Agent Boshi                                          |" -ForegroundColor Magenta
Write-Host "  |   Keeper of the Ancient Code                           |" -ForegroundColor Magenta
Write-Host "  |                                                        |" -ForegroundColor Magenta
Write-Host "  |   A Shiba dev-sage from Shibatopia                     |" -ForegroundColor Magenta
Write-Host "  |   Powered by Hermes Agent + Ollama                     |" -ForegroundColor Magenta
Write-Host "  |                                                        |" -ForegroundColor Magenta
Write-Host "  +========================================================+" -ForegroundColor Magenta
Write-Host ""

if ($Help) {
    Write-Host "Usage: .\setup.ps1 [-Cpu] [-Tier <1-5>] [-Alt] [-OllamaUrl <URL>] [-Uninstall]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Cpu             Run without GPU (CPU-only inference, uses gemma4:e4b)"
    Write-Host "  -Tier <N>        Skip the interactive menu and use tier N directly"
    Write-Host "  -Alt             Use alternate model for tiers 4-5"
    Write-Host "  -OllamaUrl <URL> Use a remote Ollama server (e.g. http://192.168.1.100:11434)"
    Write-Host "                   Skips local Ollama install. Model must be pulled on the remote."
    Write-Host "  -Uninstall       Remove Agent Boshi"
    Write-Host ""
    Write-Host "Tiers (best coding models):"
    Write-Host "  1  CPU-only   gemma4:e4b             (~3GB)   Needs 8GB+ RAM"
    Write-Host "  2  8GB VRAM   qwen2.5-coder:7b       (~5GB)   RTX 3060 / 4060"
    Write-Host "  3  16GB VRAM  devstral (24B)          (~14GB)  RTX 4080 / 4070Ti-16GB"
    Write-Host "  4  24GB VRAM  qwen3.6:27b            (~17GB)  RTX 4090 (SWE-bench king)"
    Write-Host "              or devstral              (~14GB)  with -Alt"
    Write-Host "  5  32GB VRAM  qwen3.6:27b-q8_0      (~30GB)  RTX 5090 / A6000 (SWE-bench king Q8)"
    Write-Host "              or qwen2.5-coder:32b     (~22GB)  with -Alt"
    exit 0
}

function Write-Info($msg)    { Write-Host "[INFO]  $msg" -ForegroundColor Blue }
function Write-Ok($msg)      { Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)     { Write-Host "[ERROR] $msg" -ForegroundColor Red }

# -- Spinner wait function ----------------------------------------------------
function Wait-ForUrl {
    param([string]$Url, [int]$MaxRetries = 30, [string]$Label = "service")
    $spinChars = @('|','/','-','\')
    $retries = 0
    while ($true) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
            if ($resp.StatusCode -eq 200) {
                Write-Host "`r                                          `r" -NoNewline
                return $true
            }
        } catch {}
        $retries++
        if ($retries -ge $MaxRetries) {
            Write-Host "`r                                          `r" -NoNewline
            return $false
        }
        $spin = $spinChars[$retries % 4]
        Write-Host "`r  $spin Waiting... ($retries/$MaxRetries) " -NoNewline
        Start-Sleep -Seconds 2
    }
}

# -- VRAM auto-detection ------------------------------------------------------
function Get-GpuVramMB {
    try {
        $nvsmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
        if ($nvsmi) {
            $output = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
            if ($LASTEXITCODE -eq 0 -and $output) {
                return [int]($output.Trim().Split("`n")[0])
            }
        }
    } catch {}
    return 0
}

function Get-SuggestedTier([int]$VramMB) {
    if ($VramMB -ge 28000) { return 5 }
    if ($VramMB -ge 20000) { return 4 }
    if ($VramMB -ge 14000) { return 3 }
    if ($VramMB -ge 6000)  { return 2 }
    return 1
}

# -- Disk space check ---------------------------------------------------------
$ModelDiskGB = @{ 1 = 5; 2 = 7; 3 = 16; 4 = 20; 5 = 35 }

function Test-DiskSpace([int]$NeededGB) {
    try {
        $drive = (Get-Location).Drive
        $freeGB = [math]::Floor($drive.Free / 1GB)
        if ($freeGB -lt $NeededGB) {
            Write-Warn "Low disk space: ${freeGB}GB available, ~${NeededGB}GB needed for model download."
            $choice = Read-Host "  Continue anyway? [y/N]"
            if ($choice -ne "y" -and $choice -ne "Y") {
                Write-Host "  Aborting."
                exit 0
            }
        }
    } catch {}
}

# -- Port conflict check ------------------------------------------------------
function Test-PortFree([int]$Port, [string]$Name) {
    try {
        $listener = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        if ($listener) {
            Write-Warn "Port $Port is already in use ($Name)."
            $choice = Read-Host "  Continue anyway? [y/N]"
            if ($choice -ne "y" -and $choice -ne "Y") {
                Write-Host "  Aborting."
                exit 0
            }
        }
    } catch {}
}

# -- Uninstall ----------------------------------------------------------------
if ($Uninstall) {
    Write-Host ""
    Write-Host "  Uninstall Agent Boshi" -ForegroundColor White
    Write-Host ""

    Write-Info "Stopping Hermes services..."
    try { Stop-Process -Name hermes -Force -ErrorAction SilentlyContinue } catch {}

    $hermesDir = Join-Path $env:USERPROFILE ".hermes"
    if (Test-Path $hermesDir) {
        $rmChoice = Read-Host "  Remove $hermesDir config directory? [y/N]"
        if ($rmChoice -eq "y" -or $rmChoice -eq "Y") {
            Remove-Item -Recurse -Force $hermesDir
            Write-Ok "Removed $hermesDir"
        } else {
            Write-Info "Kept $hermesDir"
        }
    }
    Write-Ok "Hermes services stopped."

    Write-Host ""
    Write-Host "  Note: Ollama and downloaded models are not removed."
    Write-Host "  To remove models:  ollama rm <model>"
    Write-Host "  To remove Ollama:  winget uninstall Ollama.Ollama"
    Write-Host ""
    Write-Ok "Uninstall complete."
    exit 0
}

# -- Check / Install Git ------------------------------------------------------
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Write-Info "Git is not installed. Installing via winget..."
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        winget install Git.Git --accept-package-agreements --accept-source-agreements
        $env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    }
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        Write-Err "Could not install git. Please install from https://git-scm.com and re-run."
        exit 1
    }
    Write-Ok "Git installed."
} else {
    Write-Ok "Git is available."
}

# -- Model tier definitions ---------------------------------------------------
$TierModels = @{
    1 = "gemma4:e4b"
    2 = "qwen2.5-coder:7b"
    3 = "devstral"
    4 = "qwen3.6:27b"
    5 = "qwen3.6:27b-q8_0"
}

$TierSizes = @{
    1 = "~3GB"
    2 = "~5GB"
    3 = "~14GB"
    4 = "~17GB"
    5 = "~30GB"
}

$TierLabels = @{
    1 = "CPU-only    (gemma4:e4b)               - Multimodal 4B, needs 8GB+ RAM"
    2 = "8GB VRAM    (qwen2.5-coder:7b)          - Best coder at this size"
    3 = "16GB VRAM   (devstral 24B)               - Agentic coder, multi-file edits"
    4 = "24GB VRAM   (qwen3.6:27b)                - SWE-bench 77.2%, coding king"
    5 = "32GB VRAM   (qwen3.6:27b-q8_0)             - SWE-bench king at Q8 quality"
}

$TierNotes = @{
    1 = "Google Gemma 4 E4B - efficient edge model, multimodal, function calling, 128K context."
    2 = "Qwen2.5-Coder 7B - HumanEval leader in 7-8B class, stable and well-tested."
    3 = "Devstral 24B by Mistral + All Hands AI - purpose-built for agentic coding."
    4 = "Qwen3.6 27B dense - THE coding king. SWE-bench 77.2%, matches Claude 4.5 Opus."
    5 = "Qwen3.6 27B dense at Q8 - SWE-bench 77.2%, near-FP16 precision, 262K context."
}

$AltModels = @{
    4 = "devstral"
    5 = "qwen3-coder:30b"
}

$AltSizes = @{
    4 = "~14GB"
    5 = "~19GB"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# -- Ollama location ----------------------------------------------------------
if ($OllamaUrl -eq "") {
    Write-Host ""
    Write-Host "  Where is your Ollama server?" -ForegroundColor White
    Write-Host ""
    Write-Host "    1)  Local - Install and run Ollama on this machine (default)" -ForegroundColor Cyan
    Write-Host "    2)  Remote - Connect to Ollama running on another machine" -ForegroundColor Cyan
    Write-Host "        (e.g. a GPU server on your network)" -ForegroundColor Yellow
    Write-Host ""

    do {
        $ollamaChoice = Read-Host "  Enter choice [1/2] (default: 1)"
        if ($ollamaChoice -eq "") { $ollamaChoice = "1" }
    } while ($ollamaChoice -ne "1" -and $ollamaChoice -ne "2")

    if ($ollamaChoice -eq "2") {
        Write-Host ""
        Write-Host "  Enter the Ollama server URL (e.g. http://192.168.1.100:11434):"
        $OllamaUrl = Read-Host "  URL"
        if ($OllamaUrl -eq "") {
            Write-Err "URL cannot be empty."
            exit 1
        }
    }
    Write-Host ""
}

$RemoteOllama = $false
if ($OllamaUrl -ne "") {
    $RemoteOllama = $true
    $OllamaUrl = $OllamaUrl.TrimEnd('/')
    Write-Info "Using remote Ollama server: $OllamaUrl"

    Write-Info "Checking connectivity to $OllamaUrl..."
    try {
        $resp = Invoke-WebRequest -Uri "$OllamaUrl/api/tags" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
        if ($resp.StatusCode -eq 200) {
            Write-Ok "Remote Ollama server is reachable."
        }
    } catch {
        Write-Warn "Cannot reach $OllamaUrl/api/tags right now."
        Write-Warn "Make sure the Ollama server is running and the URL is correct."
        $choice = Read-Host "  Continue anyway? [y/N]"
        if ($choice -ne "y" -and $choice -ne "Y") {
            Write-Host "  Aborting."
            exit 0
        }
    }
} else {
    $OllamaUrl = "http://localhost:11434"
}

# -- Tier selection -----------------------------------------------------------
if ($Cpu -and $Tier -gt 0 -and $Tier -ne 1) {
    Write-Warn "-Cpu flag overrides -Tier $Tier. Using tier 1 (CPU-only)."
}
if ($Cpu) { $Tier = 1 }

if ($Tier -eq 0) {
    $detectedVram = Get-GpuVramMB
    $suggestedTier = 0
    if ($detectedVram -gt 0) {
        $suggestedTier = Get-SuggestedTier $detectedVram
        $vramGB = [math]::Floor($detectedVram / 1024)
        Write-Ok "Detected GPU with ${vramGB}GB VRAM - recommended tier: $suggestedTier"
    }

    Write-Host ""
    Write-Host "  Choose your model tier:" -ForegroundColor White
    Write-Host ""
    for ($i = 1; $i -le 5; $i++) {
        if ($i -eq $suggestedTier) {
            Write-Host "    $i)  $($TierLabels[$i])  <-- recommended" -ForegroundColor Green
        } else {
            Write-Host "    $i)  $($TierLabels[$i])" -ForegroundColor Cyan
        }
    }
    Write-Host ""
    if ($suggestedTier -eq 0) {
        Write-Host "  Not sure? Run 'nvidia-smi' to check your VRAM." -ForegroundColor Yellow
        Write-Host "  No GPU? Pick option 1 (CPU-only)." -ForegroundColor Yellow
    }
    Write-Host ""

    $defaultTier = if ($suggestedTier -gt 0) { $suggestedTier } else { 2 }
    do {
        $input = Read-Host "  Enter tier [1-5] (default: $defaultTier)"
        if ($input -eq "") { $input = "$defaultTier" }
        $Tier = [int]$input
    } while ($Tier -lt 1 -or $Tier -gt 5)
    Write-Host ""
}

# -- Model variant selection (tiers 4-5) --------------------------------------
$UseAlt = $Alt

if ($Tier -ge 4 -and -not $Alt) {
    Write-Host ""
    Write-Host "  Choose your model variant for tier $Tier`:" -ForegroundColor White
    Write-Host ""
    Write-Host "    a)  $($TierModels[$Tier]) - $($TierNotes[$Tier])" -ForegroundColor Cyan
    Write-Host "        $($TierSizes[$Tier]) download"
    Write-Host ""
    Write-Host "    b)  $($AltModels[$Tier]) - alternate option" -ForegroundColor Cyan
    Write-Host "        $($AltSizes[$Tier]) download"
    Write-Host ""

    do {
        $variant = Read-Host "  Enter variant [a/b] (default: a)"
        if ($variant -eq "") { $variant = "a" }
    } while ($variant -ne "a" -and $variant -ne "A" -and $variant -ne "b" -and $variant -ne "B")

    if ($variant -eq "b" -or $variant -eq "B") { $UseAlt = $true }
    Write-Host ""
}

if ($UseAlt -and $Tier -ge 4) {
    $Model = $AltModels[$Tier]
    $ModelSize = $AltSizes[$Tier]
} else {
    $Model = $TierModels[$Tier]
    $ModelSize = $TierSizes[$Tier]
}

$CpuOnly = ($Tier -eq 1)

Write-Info "Selected: $($TierLabels[$Tier])"
Write-Info "Model: $Model ($ModelSize download)"
Write-Host ""

# -- Pre-flight checks -------------------------------------------------------
if (-not $RemoteOllama) {
    Test-PortFree 11434 "Ollama"
    Test-DiskSpace $ModelDiskGB[$Tier]
}
Test-PortFree 9119 "Hermes Dashboard"

# Confirmation
Write-Host ""
Write-Host "  Ready to install:" -ForegroundColor White
Write-Host "    Model:     $Model ($ModelSize)"
Write-Host "    Ollama:    $OllamaUrl"
if ($RemoteOllama) { Write-Host "               (remote - model must be pulled on the server)" -ForegroundColor Yellow }
if ($CpuOnly) { Write-Host "    GPU:       CPU-only" }
Write-Host ""
$proceed = Read-Host "  Proceed? [Y/n]"
if ($proceed -eq "n" -or $proceed -eq "N") { Write-Host "  Aborting."; exit 0 }
Write-Host ""

###############################################################################
#                              INSTALL                                         #
###############################################################################

if ($RemoteOllama) {
    Write-Info "Using remote Ollama at $OllamaUrl"
    Write-Warn "Make sure '$Model' is pulled on the remote: ollama pull $Model"
    Write-Host ""
} else {
    # -- Install Ollama -------------------------------------------------------
    Write-Info "Checking for Ollama..."
    $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($ollamaCmd) {
        Write-Ok "Ollama is already installed."
    } else {
        Write-Info "Installing Ollama..."
        $ollamaInstaller = Join-Path $env:TEMP "OllamaSetup.exe"
        Invoke-WebRequest -Uri "https://ollama.com/download/OllamaSetup.exe" -OutFile $ollamaInstaller
        Start-Process -FilePath $ollamaInstaller -Args "/SILENT" -Wait
        Remove-Item $ollamaInstaller -ErrorAction SilentlyContinue

        $env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
        if (-not $ollamaCmd) {
            Write-Err "Ollama installation failed. Please install manually from https://ollama.com"
            exit 1
        }
        Write-Ok "Ollama installed."
    }

    # -- Start Ollama ---------------------------------------------------------
    Write-Info "Starting Ollama..."
    $ollamaRunning = $false
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
        if ($resp.StatusCode -eq 200) { $ollamaRunning = $true }
    } catch {}

    if ($ollamaRunning) {
        Write-Ok "Ollama is already running."
    } else {
        Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
        Write-Info "Waiting for Ollama..."
        if (-not (Wait-ForUrl "http://localhost:11434/api/tags" 30 "Ollama")) {
            Write-Err "Ollama failed to start after 60 seconds."
            Write-Host "  Try running 'ollama serve' manually in another terminal."
            exit 1
        }
        Write-Ok "Ollama is running."
    }

    # -- Pull model -----------------------------------------------------------
    Write-Info "Pulling $Model ($ModelSize download, one-time operation)..."
    Write-Host "  $($TierNotes[$Tier])"
    Write-Host ""
    & ollama pull $Model
    if ($LASTEXITCODE -ne 0) { Write-Err "Failed to pull model."; exit 1 }
    Write-Ok "Model downloaded and ready."
}

# -- Install Hermes Agent -----------------------------------------------------
Write-Info "Checking for Hermes Agent..."
$hermesDir = Join-Path $env:USERPROFILE ".hermes"
$hermesCmd = Get-Command hermes -ErrorAction SilentlyContinue

if ($hermesCmd) {
    Write-Ok "Hermes Agent is already installed."
} else {
    Write-Info "Installing Hermes Agent..."

    # Check for Python
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
    }
    if (-not $pythonCmd) {
        Write-Info "Python not found. Installing via winget..."
        try {
            winget install Python.Python.3.11 --accept-package-agreements --accept-source-agreements
            $env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        } catch {
            Write-Err "Could not install Python. Please install Python 3.11+ from https://python.org and re-run."
            exit 1
        }
    }
    Write-Ok "Python is available."

    # Use the official Windows installer
    $installScript = Join-Path $env:TEMP "hermes-install.ps1"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1" -OutFile $installScript
    & powershell -ExecutionPolicy Bypass -File $installScript -SkipSetup -SkipBrowser

    $env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    $hermesCmd = Get-Command hermes -ErrorAction SilentlyContinue
    if (-not $hermesCmd) {
        # Check common install locations
        $venvPath = Join-Path $hermesDir "hermes-agent" ".venv" "Scripts"
        if (Test-Path (Join-Path $venvPath "hermes.exe")) {
            $env:PATH = "$venvPath;$env:PATH"
        } else {
            Write-Err "Hermes Agent installation failed or hermes is not on PATH."
            Write-Host "  Check: $hermesDir\hermes-agent\.venv\Scripts\"
            exit 1
        }
    }
    Write-Ok "Hermes Agent installed."
}

# -- Deploy Agent Boshi configuration -----------------------------------------
Write-Info "Deploying Agent Boshi configuration to $hermesDir..."
New-Item -ItemType Directory -Path $hermesDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $hermesDir "skills") -Force | Out-Null

# Copy personality
Copy-Item "$scriptDir\hermes\SOUL.md" "$hermesDir\SOUL.md" -Force
Write-Ok "Agent Boshi personality deployed."

# Copy skills
$skillsDir = "$scriptDir\hermes\skills"
if (Test-Path $skillsDir) {
    Copy-Item "$skillsDir\*" "$hermesDir\skills" -Recurse -Force
}
Write-Ok "Skills deployed (dev-review, dev-debug, self-improving-agent)."

# -- Write Hermes config.yaml ------------------------------------------------
$ollamaApiUrl = "$OllamaUrl/v1"

$hermesConfig = @"
# Agent Boshi - Hermes Agent Configuration
# Configured for local Ollama backend

model:
  default: "$Model"
  provider: "custom"
  base_url: "$ollamaApiUrl"

agent:
  max_turns: 60
  reasoning_effort: "medium"
  verbose: false

terminal:
  backend: "local"
  cwd: "."
  timeout: 180
  lifetime_seconds: 300

memory:
  memory_enabled: true
  user_profile_enabled: true
  memory_char_limit: 2200
  user_char_limit: 1375
  nudge_interval: 10
  flush_min_turns: 6

skills:
  creation_nudge_interval: 15

compression:
  enabled: true
  threshold: 0.50
  target_ratio: 0.20
  protect_last_n: 20
  protect_first_n: 3

display:
  compact: false
  tool_progress: all
  streaming: true
  skin: default

platform_toolsets:
  cli: [hermes-cli]
"@
Set-Content -Path (Join-Path $hermesDir "config.yaml") -Value $hermesConfig -NoNewline
Write-Ok "Config deployed: model=$Model, ollama=$OllamaUrl"

# -- Write .env ---------------------------------------------------------------
$envPath = Join-Path $hermesDir ".env"
if (-not (Test-Path $envPath)) {
    $envContent = @"
# Agent Boshi - Environment Variables
# No API keys needed for local Ollama
# Add keys here if you want to use cloud providers as fallback
"@
    Set-Content -Path $envPath -Value $envContent -NoNewline
}

# -- Start Hermes Dashboard ---------------------------------------------------
Write-Info "Starting Hermes Dashboard..."
$dashboardRunning = $false
try {
    $resp = Invoke-WebRequest -Uri "http://localhost:9119/" -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
    if ($resp.StatusCode -eq 200) { $dashboardRunning = $true }
} catch {}

if ($dashboardRunning) {
    Write-Ok "Hermes Dashboard is already running."
} else {
    $logFile = Join-Path $hermesDir "dashboard.log"
    Start-Process -FilePath "hermes" -ArgumentList "dashboard","--port","9119","--no-open" -WindowStyle Hidden -RedirectStandardOutput $logFile -RedirectStandardError $logFile

    Write-Info "Waiting for Hermes Dashboard..."
    if (-not (Wait-ForUrl "http://localhost:9119/" 30 "Dashboard")) {
        Write-Warn "Dashboard may still be starting. Check: Get-Content $logFile -Tail 20"
    } else {
        Write-Ok "Hermes Dashboard is running."
    }
}

# -- Done ---------------------------------------------------------------------
Write-Host ""
Write-Host "  ========================================================" -ForegroundColor Green
Write-Host "    Agent Boshi is ready!" -ForegroundColor Green
Write-Host "  ========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Model:  $Model ($($TierLabels[$Tier]))"
Write-Host ""
Write-Host "  Open in your browser:"
Write-Host "    http://localhost:9119" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Or use the CLI:"
Write-Host "    hermes                                  # Start interactive chat" -ForegroundColor Cyan
Write-Host "    hermes chat -q `"Hello Agent Boshi!`"     # Single query" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Useful commands:"
Write-Host "    hermes                                  # Interactive chat"
Write-Host "    hermes model                            # Change model"
Write-Host "    hermes setup                            # Re-run setup wizard"
Write-Host "    hermes doctor                           # Check configuration"
Write-Host "    hermes dashboard                        # Start web dashboard"
Write-Host "    ollama ps                               # Check running models"
Write-Host ""
Write-Host "  Change model:" -ForegroundColor Yellow
Write-Host "    ollama pull <model>"
Write-Host "    hermes config set model.default <model>"
Write-Host ""
Write-Host "  Stop everything:" -ForegroundColor Yellow
Write-Host "    Stop-Process -Name hermes               # Stop dashboard"
Write-Host "    ollama stop $Model                      # Unload model"
Write-Host ""
Write-Host "  Config: $hermesDir\config.yaml"
Write-Host "  Personality: $hermesDir\SOUL.md"
Write-Host "  Skills: $hermesDir\skills\"
Write-Host ""
Write-Host "  Agent Boshi guards the Ancient Lore. May your code be" -ForegroundColor Yellow
Write-Host "  free of Shadowcats." -ForegroundColor Yellow
Write-Host ""

# Open browser
Start-Process "http://localhost:9119"
