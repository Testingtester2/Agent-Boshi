#!/usr/bin/env bash
###############################################################################
# Agent Boshi — One-Click Setup (Linux / macOS)
#
# What this does:
#   1. Asks you to pick a model tier based on your GPU VRAM
#   2. Installs Ollama + Hermes Agent
#   3. Pulls the selected coding model
#   4. Deploys Agent Boshi's personality (SOUL.md) and skills
#   5. Opens the Hermes dashboard in your browser
#
# Usage:
#   chmod +x setup.sh
#   ./setup.sh                      # Interactive setup
#   ./setup.sh --cpu                # CPU-only mode (no GPU)
#   ./setup.sh --tier <1-5>         # Skip menu, pick tier directly
#   ./setup.sh --ollama-url <URL>   # Use a remote Ollama server
#
# Model Tiers (best coding models available):
#   1) CPU-only  — gemma4:e4b             (~3GB download, needs 8GB+ RAM)
#   2) 8GB VRAM  — qwen2.5-coder:7b       (~5GB download)   [RTX 3060/4060]
#   3) 16GB VRAM — devstral               (~14GB download)   [RTX 4080/4070Ti-16GB]
#   4) 24GB VRAM — qwen3.6:27b            (~17GB download)   [RTX 4090]
#                  or devstral             (~14GB, agentic code-specialized)
#   5) 32GB VRAM — qwen3-coder-next       (~46GB download)   [RTX 5090/A6000]
#                  or qwen2.5-coder:32b    (~22GB, battle-tested)
###############################################################################

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Cleanup trap ───────────────────────────────────────────────
cleanup() {
  echo ""
  warn "Setup interrupted. Cleaning up..."
  if [ -n "${OLLAMA_PID:-}" ]; then
    kill "$OLLAMA_PID" 2>/dev/null || true
  fi
  if [ -n "${DASHBOARD_PID:-}" ]; then
    kill "$DASHBOARD_PID" 2>/dev/null || true
  fi
  exit 130
}
trap cleanup INT TERM

# ── Spinner for wait loops ─────────────────────────────────────
SPINNER_CHARS='|/-\'
spin_wait() {
  local retries=0
  local max_retries=$1
  local url=$2
  local label=$3
  local spin_i=0
  while ! curl -sf "$url" > /dev/null 2>&1; do
    retries=$((retries + 1))
    if [ $retries -ge $max_retries ]; then
      printf "\r\033[K"
      return 1
    fi
    printf "\r  %s Waiting... (%d/%d) " "${SPINNER_CHARS:spin_i:1}" "$retries" "$max_retries"
    spin_i=$(( (spin_i + 1) % 4 ))
    sleep 2
  done
  printf "\r\033[K"
  return 0
}

# ── VRAM auto-detection ───────────────────────────────────────
detect_vram_mb() {
  if command -v nvidia-smi &> /dev/null; then
    local vram_mb
    vram_mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
    if [ -n "$vram_mb" ] && [ "$vram_mb" -gt 0 ] 2>/dev/null; then
      echo "$vram_mb"
      return 0
    fi
  fi
  echo "0"
  return 0
}

suggest_tier() {
  local vram_mb=$1
  if [ "$vram_mb" -ge 28000 ]; then echo 5
  elif [ "$vram_mb" -ge 20000 ]; then echo 4
  elif [ "$vram_mb" -ge 14000 ]; then echo 3
  elif [ "$vram_mb" -ge 6000 ]; then echo 2
  else echo 1; fi
}

# ── Disk space check ──────────────────────────────────────────
model_disk_gb() {
  case "$1" in
    1) echo 5 ;;  2) echo 7 ;;  3) echo 16 ;;  4) echo 20 ;;  5) echo 50 ;;
  esac
}

check_disk_space() {
  local needed_gb=$1
  local avail_kb
  avail_kb=$(df -k . 2>/dev/null | tail -1 | awk '{print $4}')
  if [ -n "$avail_kb" ]; then
    local avail_gb=$((avail_kb / 1048576))
    if [ "$avail_gb" -lt "$needed_gb" ]; then
      warn "Low disk space: ${avail_gb}GB available, ~${needed_gb}GB needed for model download."
      read -rp "  Continue anyway? [y/N]: " DISK_CONTINUE
      case "${DISK_CONTINUE:-N}" in
        y|Y|yes|Yes) ;;
        *) echo "  Aborting."; exit 0 ;;
      esac
    fi
  fi
}

# ── Port conflict check ──────────────────────────────────────
check_port() {
  local port=$1
  local name=$2
  local in_use=false
  if command -v ss &> /dev/null; then
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then in_use=true; fi
  elif command -v lsof &> /dev/null; then
    if lsof -i :"$port" &>/dev/null; then in_use=true; fi
  fi
  if [ "$in_use" = true ]; then
    warn "Port $port is already in use ($name)."
    warn "Another service may be running. The install may fail or conflict."
    read -rp "  Continue anyway? [y/N]: " PORT_CONTINUE
    case "${PORT_CONTINUE:-N}" in
      y|Y|yes|Yes) ;;
      *) echo "  Aborting."; exit 0 ;;
    esac
  fi
}

# ── Banner ──────────────────────────────────────────────────────
echo -e "${MAGENTA}"
cat << 'BANNER'

  +=========================================================+
  |                                                           |
  |   Agent Boshi                                             |
  |   Keeper of the Ancient Code                              |
  |                                                           |
  |   A Shiba dev-sage from Shibatopia                        |
  |   Powered by Hermes Agent + Ollama                        |
  |                                                           |
  +=========================================================+

BANNER
echo -e "${NC}"

# ── Parse args ──────────────────────────────────────────────────
CPU_ONLY=false
TIER=""
USE_ALT=""
DO_UNINSTALL=false
OLLAMA_URL=""
for arg in "$@"; do
  case "$arg" in
    --cpu) CPU_ONLY=true; TIER=1 ;;
    --alt) USE_ALT=true ;;
    --uninstall) DO_UNINSTALL=true ;;
    --ollama-url)
      ;;
    --tier)
      ;;
    1|2|3|4|5)
      if [ "${PREV_ARG:-}" = "--tier" ]; then
        TIER="$arg"
      fi
      ;;
    --help|-h)
      echo "Usage: ./setup.sh [--cpu] [--tier <1-5>] [--alt] [--ollama-url <URL>] [--uninstall]"
      echo ""
      echo "Options:"
      echo "  --cpu           Run without GPU (CPU-only inference, uses gemma4:e4b)"
      echo "  --tier <N>      Skip the interactive menu and use tier N directly"
      echo "  --alt           Use alternate model for tiers 4-5"
      echo "  --ollama-url <URL>  Use a remote Ollama server (e.g. http://192.168.1.100:11434)"
      echo "                      Skips local Ollama install. Model must be pulled on the remote."
      echo "  --uninstall     Remove Agent Boshi"
      echo ""
      echo "Tiers (best coding models):"
      echo "  1  CPU-only   gemma4:e4b             (~3GB)   Needs 8GB+ RAM"
      echo "  2  8GB VRAM   qwen2.5-coder:7b       (~5GB)   RTX 3060 / 4060"
      echo "  3  16GB VRAM  devstral (24B)          (~14GB)  RTX 4080 / 4070Ti-16GB"
      echo "  4  24GB VRAM  qwen3.6:27b             (~17GB)  RTX 4090 (SWE-bench king)"
      echo "              or devstral                (~14GB)  with --alt (agentic)"
      echo "  5  32GB VRAM  qwen3-coder-next (80B MoE) (~46GB) RTX 5090 / A6000"
      echo "              or qwen2.5-coder:32b       (~22GB)  with --alt (battle-tested)"
      exit 0
      ;;
  esac
  PREV_ARG="$arg"
done

# Handle two-arg flags: --tier N, --ollama-url URL
i=0
for arg in "$@"; do
  i=$((i + 1))
  next_i=$((i + 1))
  if [ "$arg" = "--tier" ] || [ "$arg" = "--ollama-url" ]; then
    j=0
    for a2 in "$@"; do
      j=$((j + 1))
      if [ $j -eq $next_i ]; then
        if [ "$arg" = "--tier" ]; then
          TIER="$a2"
        elif [ "$arg" = "--ollama-url" ]; then
          OLLAMA_URL="$a2"
        fi
        break
      fi
    done
  fi
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Uninstall ─────────────────────────────────────────────────
if [ "$DO_UNINSTALL" = true ]; then
  echo ""
  echo -e "${BOLD}Uninstall Agent Boshi${NC}"
  echo ""

  info "Stopping Hermes services..."
  pkill -f 'hermes dashboard' 2>/dev/null || true
  pkill -f 'hermes gateway' 2>/dev/null || true

  if [ -d "$HOME/.hermes" ]; then
    read -rp "  Remove ~/.hermes config directory? [y/N]: " RM_CONFIG
    case "${RM_CONFIG:-N}" in
      y|Y|yes|Yes)
        rm -rf "$HOME/.hermes"
        success "Removed ~/.hermes"
        ;;
      *) info "Kept ~/.hermes" ;;
    esac
  fi

  success "Hermes services stopped."
  echo ""
  echo "  Note: Ollama and downloaded models are not removed."
  echo "  To remove models:  ollama rm <model>"
  echo "  To remove Ollama:  sudo rm /usr/local/bin/ollama"
  echo ""
  success "Uninstall complete."
  exit 0
fi

# ── Check / Install Git ───────────────────────────────────────
if ! command -v git &> /dev/null; then
  info "Git is not installed. Installing..."
  if command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y git
  elif command -v dnf &> /dev/null; then
    sudo dnf install -y git
  elif command -v brew &> /dev/null; then
    brew install git
  else
    error "Could not install git. Please install git and re-run."
    exit 1
  fi
  success "Git installed."
else
  success "Git is available."
fi

# ── Check / Install curl ──────────────────────────────────────
if ! command -v curl &> /dev/null; then
  info "curl is not installed. Installing..."
  if command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y curl
  elif command -v dnf &> /dev/null; then
    sudo dnf install -y curl
  elif command -v brew &> /dev/null; then
    brew install curl
  else
    error "Could not install curl. Please install curl and re-run."
    exit 1
  fi
  success "curl installed."
else
  success "curl is available."
fi

# ── Model tier definitions ─────────────────────────────────────
tier_model()   {
  case "$1" in
    1) echo "gemma4:e4b" ;;
    2) echo "qwen2.5-coder:7b" ;;
    3) echo "devstral" ;;
    4) echo "qwen3.6:27b" ;;
    5) echo "qwen3-coder-next" ;;
  esac
}

tier_size()    {
  case "$1" in
    1) echo "~3GB" ;;
    2) echo "~5GB" ;;
    3) echo "~14GB" ;;
    4) echo "~17GB" ;;
    5) echo "~46GB" ;;
  esac
}

tier_label()   {
  case "$1" in
    1) echo "CPU-only    (gemma4:e4b)               — Multimodal 4B, needs 8GB+ RAM" ;;
    2) echo "8GB VRAM    (qwen2.5-coder:7b)          — Best coder at this size, HumanEval leader" ;;
    3) echo "16GB VRAM   (devstral 24B)               — Agentic coder, multi-file edits, 128K ctx" ;;
    4) echo "24GB VRAM   (qwen3.6:27b)                — SWE-bench 77.2%, matches Claude 4.5 Opus" ;;
    5) echo "32GB VRAM   (qwen3-coder-next 80B MoE)   — Best dedicated coder, 3B active, 256K ctx" ;;
  esac
}

# Alternate model choices for tiers 4-5
alt_model()  {
  case "$1" in
    4) echo "devstral" ;;
    5) echo "qwen2.5-coder:32b" ;;
  esac
}

alt_size()   {
  case "$1" in
    4) echo "~14GB" ;;
    5) echo "~22GB" ;;
  esac
}

model_note()   {
  if [ "$USE_ALT" = "true" ] && [ "$TIER" -ge 4 ]; then
    case "$TIER" in
      4) echo "Devstral 24B — purpose-built agentic coder by Mistral. Multi-file edits, debugging, 128K context." ;;
      5) echo "Qwen2.5-Coder 32B — 92.7% HumanEval, most battle-tested coding model, very mature." ;;
    esac
  else
    case "$TIER" in
      1) echo "Google Gemma 4 E4B — efficient edge model, multimodal, function calling, 128K context." ;;
      2) echo "Qwen2.5-Coder 7B — HumanEval leader in 7-8B class, stable and well-tested." ;;
      3) echo "Devstral 24B by Mistral + All Hands AI — purpose-built for agentic coding workflows." ;;
      4) echo "Qwen3.6 27B dense — THE coding king. SWE-bench 77.2%, Terminal-Bench matches Claude 4.5 Opus." ;;
      5) echo "Qwen3-Coder-Next 80B MoE (3B active) — best dedicated coder, 256K context, agentic optimized." ;;
    esac
  fi
}

# ── Ollama location ───────────────────────────────────────────
if [ -z "$OLLAMA_URL" ]; then
  echo ""
  echo -e "${BOLD}Where is your Ollama server?${NC}"
  echo ""
  echo -e "  ${CYAN}1)${NC}  ${BOLD}Local${NC} — Install and run Ollama on this machine (default)"
  echo -e "  ${CYAN}2)${NC}  ${BOLD}Remote${NC} — Connect to Ollama running on another machine"
  echo -e "      ${YELLOW}(e.g. a GPU server on your network, or the host machine)${NC}"
  echo ""

  while true; do
    read -rp "  Enter choice [1/2] (default: 1): " OLLAMA_CHOICE
    case "${OLLAMA_CHOICE:-1}" in
      1) break ;;
      2)
        echo ""
        echo -e "  Enter the Ollama server URL (e.g. ${CYAN}http://192.168.1.100:11434${NC}):"
        read -rp "  URL: " OLLAMA_URL
        if [ -z "$OLLAMA_URL" ]; then
          echo -e "  ${RED}URL cannot be empty.${NC}"
          continue
        fi
        OLLAMA_URL="${OLLAMA_URL%/}"
        break
        ;;
      *) echo -e "  ${RED}Please enter 1 or 2.${NC}" ;;
    esac
  done
  echo ""
fi

REMOTE_OLLAMA=false
if [ -n "$OLLAMA_URL" ]; then
  REMOTE_OLLAMA=true
  OLLAMA_URL="${OLLAMA_URL%/}"
  info "Using remote Ollama server: $OLLAMA_URL"

  info "Checking connectivity to $OLLAMA_URL..."
  if curl -sf "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
    success "Remote Ollama server is reachable."
  else
    warn "Cannot reach $OLLAMA_URL/api/tags right now."
    warn "Make sure the Ollama server is running and the URL is correct."
    read -rp "  Continue anyway? [y/N]: " REMOTE_CONTINUE
    case "${REMOTE_CONTINUE:-N}" in
      y|Y|yes|Yes) ;;
      *) echo "  Aborting."; exit 0 ;;
    esac
  fi
else
  OLLAMA_URL="http://localhost:11434"
fi

# ── Tier selection menu ─────────────────────────────────────────
if [ -z "$TIER" ]; then
  DETECTED_VRAM=$(detect_vram_mb) || DETECTED_VRAM=0
  SUGGESTED_TIER=""
  if [ "$DETECTED_VRAM" -gt 0 ] 2>/dev/null; then
    SUGGESTED_TIER=$(suggest_tier "$DETECTED_VRAM")
    VRAM_GB=$(( DETECTED_VRAM / 1024 ))
    success "Detected GPU with ${VRAM_GB}GB VRAM — recommended tier: $SUGGESTED_TIER"
  fi

  echo ""
  echo -e "${BOLD}Choose your model tier:${NC}"
  echo ""
  for t in 1 2 3 4 5; do
    local_label=$(tier_label "$t")
    if [ "$t" = "$SUGGESTED_TIER" ]; then
      echo -e "  ${CYAN}${BOLD}$t)${NC}  ${BOLD}$local_label  ${GREEN}<-- recommended${NC}"
    else
      echo -e "  ${CYAN}$t)${NC}  $local_label"
    fi
  done
  echo ""
  if [ -z "$SUGGESTED_TIER" ]; then
    echo -e "  ${YELLOW}Not sure? Run 'nvidia-smi' to check your VRAM.${NC}"
    echo -e "  ${YELLOW}No GPU? Pick option 1 (CPU-only).${NC}"
  fi
  echo ""

  DEFAULT_TIER="${SUGGESTED_TIER:-2}"
  while true; do
    read -rp "  Enter tier [1-5] (default: $DEFAULT_TIER): " TIER
    TIER="${TIER:-$DEFAULT_TIER}"
    case "$TIER" in
      1|2|3|4|5) break ;;
      *) echo -e "  ${RED}Please enter a number between 1 and 5.${NC}" ;;
    esac
  done
  echo ""
fi

# Validate tier
case "$TIER" in
  1|2|3|4|5) ;;
  *) error "Invalid tier: $TIER (must be 1-5)"; exit 1 ;;
esac

# ── Model variant selection (tiers 4-5) ──────────────────────────
if [ "$TIER" -ge 4 ] && [ -z "$USE_ALT" ]; then
  echo ""
  echo -e "${BOLD}Choose your model variant for tier $TIER:${NC}"
  echo ""
  echo -e "  ${CYAN}a)${NC}  $(tier_model "$TIER") — $(model_note)"
  echo -e "      $(tier_size "$TIER") download"
  echo ""
  echo -e "  ${CYAN}b)${NC}  $(alt_model "$TIER") — alternate option"
  echo -e "      $(alt_size "$TIER") download"
  echo ""

  while true; do
    read -rp "  Enter variant [a/b] (default: a): " VARIANT
    case "${VARIANT:-a}" in
      a|A) USE_ALT=false; break ;;
      b|B) USE_ALT=true; break ;;
      *) echo -e "  ${RED}Please enter 'a' or 'b'.${NC}" ;;
    esac
  done
  echo ""
fi

if [ "$USE_ALT" = "true" ] && [ "$TIER" -ge 4 ]; then
  MODEL=$(alt_model "$TIER")
  MODEL_SIZE=$(alt_size "$TIER")
else
  MODEL=$(tier_model "$TIER")
  MODEL_SIZE=$(tier_size "$TIER")
fi

if [ "$TIER" = "1" ]; then
  CPU_ONLY=true
fi

info "Selected: $(tier_label "$TIER")"
info "Model: $MODEL ($MODEL_SIZE download)"
echo ""

# ── Pre-flight checks ─────────────────────────────────────────
if [ "$REMOTE_OLLAMA" = false ]; then
  check_port 11434 "Ollama"
  check_disk_space "$(model_disk_gb "$TIER")"
fi
check_port 9119 "Hermes Dashboard"

# Confirmation before download
echo ""
echo -e "  ${BOLD}Ready to install:${NC}"
echo -e "    Model:     $MODEL ($MODEL_SIZE)"
echo -e "    Ollama:    $OLLAMA_URL"
if [ "$REMOTE_OLLAMA" = true ]; then
  echo -e "               ${YELLOW}(remote — model must be pulled on the server)${NC}"
fi
if [ "$CPU_ONLY" = true ]; then
  echo -e "    GPU:       CPU-only"
fi
echo ""
read -rp "  Proceed? [Y/n]: " PROCEED
case "${PROCEED:-Y}" in
  n|N|no|No) echo "  Aborting."; exit 0 ;;
esac
echo ""

###############################################################################
#                              INSTALL                                         #
###############################################################################

if [ "$REMOTE_OLLAMA" = true ]; then
  # ── Remote Ollama — skip install, start, and pull ────────────
  info "Using remote Ollama at $OLLAMA_URL"
  warn "Make sure '$MODEL' is pulled on the remote: ollama pull $MODEL"
  echo ""
else
  # ── Install Ollama ────────────────────────────────────────────
  info "Checking for Ollama..."
  if command -v ollama &> /dev/null; then
    success "Ollama is already installed ($(ollama --version 2>/dev/null || echo 'unknown version'))."
  else
    info "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
    if ! command -v ollama &> /dev/null; then
      error "Ollama installation failed. Please install manually from https://ollama.com"
      exit 1
    fi
    success "Ollama installed."
  fi

  # ── Start Ollama ──────────────────────────────────────────────
  info "Starting Ollama service..."
  if curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
    success "Ollama is already running."
  else
    if command -v systemctl &> /dev/null && systemctl is-enabled ollama &> /dev/null 2>&1; then
      sudo systemctl start ollama
    else
      ollama serve &> /dev/null &
      OLLAMA_PID=$!
      disown "$OLLAMA_PID" 2>/dev/null || true
    fi

    if ! spin_wait 30 "http://localhost:11434/api/tags" "Ollama"; then
      error "Ollama failed to start after 60 seconds."
      echo "  Try running 'ollama serve' manually in another terminal."
      exit 1
    fi
    success "Ollama is running."
  fi

  # ── Pull the model ───────────────────────────────────────────
  info "Pulling $MODEL ($MODEL_SIZE download, this is a one-time operation)..."
  echo "  $(model_note)"
  echo ""
  ollama pull "$MODEL"
  success "Model downloaded and ready."
fi

# ── Install Hermes Agent ────────────────────────────────────────
info "Checking for Hermes Agent..."
HERMES_DIR="$HOME/.hermes"

if command -v hermes &> /dev/null; then
  success "Hermes Agent is already installed."
else
  info "Installing Hermes Agent..."
  info "This installs Python dependencies and the Hermes CLI."

  # Hermes needs Python 3.11+
  if ! command -v python3 &> /dev/null; then
    info "Python 3 not found. Installing..."
    if command -v apt-get &> /dev/null; then
      sudo apt-get update && sudo apt-get install -y python3 python3-venv python3-pip
    elif command -v dnf &> /dev/null; then
      sudo dnf install -y python3 python3-pip
    elif command -v brew &> /dev/null; then
      brew install python@3.11
    else
      error "Could not install Python 3. Please install Python 3.11+ and re-run."
      exit 1
    fi
  fi
  success "Python 3 is available ($(python3 --version 2>/dev/null))."

  # Use the official Hermes installer
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup --skip-browser

  if ! command -v hermes &> /dev/null; then
    # Try sourcing shell profile in case PATH was updated
    for f in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
      [ -f "$f" ] && . "$f" 2>/dev/null || true
    done
  fi

  if ! command -v hermes &> /dev/null; then
    # Check common install locations
    if [ -f "$HERMES_DIR/hermes-agent/.venv/bin/hermes" ]; then
      export PATH="$HERMES_DIR/hermes-agent/.venv/bin:$PATH"
    elif [ -f "/usr/local/bin/hermes" ]; then
      true
    else
      error "Hermes Agent installation failed or hermes is not on PATH."
      echo "  Try: export PATH=\"\$HOME/.hermes/hermes-agent/.venv/bin:\$PATH\""
      echo "  Then re-run this script."
      exit 1
    fi
  fi
  success "Hermes Agent installed."
fi

# ── Deploy Agent Boshi configuration ──────────────────────────
info "Deploying Agent Boshi configuration to $HERMES_DIR..."
mkdir -p "$HERMES_DIR/skills"

# Deploy SOUL.md personality
cp "$SCRIPT_DIR/hermes/SOUL.md" "$HERMES_DIR/SOUL.md"
success "Agent Boshi personality deployed."

# Deploy skills
cp -r "$SCRIPT_DIR/hermes/skills/"* "$HERMES_DIR/skills/" 2>/dev/null || true
success "Skills deployed (dev-review, dev-debug, self-improving-agent)."

# ── Write Hermes config.yaml ──────────────────────────────────
# Configure Hermes to use Ollama as a custom endpoint
OLLAMA_API_URL="${OLLAMA_URL}/v1"

cat > "$HERMES_DIR/config.yaml" << HERMESCFG
# Agent Boshi — Hermes Agent Configuration
# Configured for local Ollama backend

model:
  default: "$MODEL"
  provider: "custom"
  base_url: "$OLLAMA_API_URL"

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
HERMESCFG

success "Config deployed: model=$MODEL, ollama=$OLLAMA_URL"

# ── Write .env for Hermes (no API keys needed for local Ollama) ─
if [ ! -f "$HERMES_DIR/.env" ]; then
  cat > "$HERMES_DIR/.env" << HERMESENV
# Agent Boshi — Environment Variables
# No API keys needed for local Ollama
# Add keys here if you want to use cloud providers as fallback
HERMESENV
fi

# ── Start Hermes Dashboard ────────────────────────────────────
info "Starting Hermes Dashboard..."

# Check if already running
DASHBOARD_RUNNING=false
if curl -sf http://localhost:9119/ > /dev/null 2>&1; then
  DASHBOARD_RUNNING=true
  success "Hermes Dashboard is already running."
fi

if [ "$DASHBOARD_RUNNING" = false ]; then
  hermes dashboard --port 9119 --no-open &> "$HERMES_DIR/dashboard.log" &
  DASHBOARD_PID=$!
  disown "$DASHBOARD_PID" 2>/dev/null || true

  # Wait for dashboard to start (up to 30 seconds)
  info "Waiting for dashboard to start..."
  DASH_WAIT=0
  while [ $DASH_WAIT -lt 30 ]; do
    if curl -sf http://localhost:9119/ > /dev/null 2>&1; then
      break
    fi
    DASH_WAIT=$((DASH_WAIT + 2))
    sleep 2
  done

  if curl -sf http://localhost:9119/ > /dev/null 2>&1; then
    success "Hermes Dashboard is running (PID $DASHBOARD_PID)."
  else
    warn "Dashboard may still be starting. Check: tail -f $HERMES_DIR/dashboard.log"
  fi
fi

# ── Done ────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}==========================================================${NC}"
echo -e "${GREEN}  Agent Boshi is ready!${NC}"
echo -e "${GREEN}==========================================================${NC}"
echo ""
echo -e "  Model:  ${BOLD}$MODEL${NC} ($(tier_label "$TIER"))"
echo ""
echo "  Open in your browser:"
echo -e "    ${CYAN}http://localhost:9119${NC}"
echo ""
echo "  Or use the CLI:"
echo -e "    ${CYAN}hermes${NC}                                  # Start interactive chat"
echo -e "    ${CYAN}hermes chat -q \"Hello Agent Boshi!\"${NC}      # Single query"
echo ""
echo "  Useful commands:"
echo "    hermes                                  # Interactive chat"
echo "    hermes model                            # Change model"
echo "    hermes setup                            # Re-run setup wizard"
echo "    hermes doctor                           # Check configuration"
echo "    hermes dashboard                        # Start web dashboard"
echo "    tail -f ~/.hermes/dashboard.log          # Watch dashboard logs"
echo "    ollama ps                               # Check running models"
echo ""
echo "  Change model:"
echo "    ollama pull <model>"
echo "    hermes config set model.default <model>"
echo ""
echo "  Stop everything:"
echo "    pkill -f 'hermes dashboard'              # Stop dashboard"
echo "    ollama stop $MODEL                       # Unload model from VRAM"
echo "    # Or: sudo systemctl stop ollama         # Stop Ollama service"
echo ""
echo "  Config: $HERMES_DIR/config.yaml"
echo "  Personality: $HERMES_DIR/SOUL.md"
echo "  Skills: $HERMES_DIR/skills/"
echo ""
echo -e "  ${YELLOW}Agent Boshi guards the Ancient Lore. May your code be free"
echo -e "  of Shadowcats.${NC}"
echo ""

# Try to open browser
if command -v xdg-open &> /dev/null; then
  xdg-open "http://localhost:9119" 2>/dev/null || true
elif command -v open &> /dev/null; then
  open "http://localhost:9119" 2>/dev/null || true
fi
