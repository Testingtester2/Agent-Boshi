#!/usr/bin/env bash
###############################################################################
# The Librarian — One-Click Setup (Linux / macOS)
#
# What this does:
#   1. Asks how you want to install (Docker or native on host)
#   2. Asks you to pick a model tier based on your GPU VRAM
#   3. Installs Ollama + OpenClaw Gateway
#   4. Pulls the selected model
#   5. Deploys The Librarian's personality (SOUL.md) and skills
#   6. Opens the OpenClaw dashboard in your browser
#
# Usage:
#   chmod +x setup.sh
#   ./setup.sh                      # Interactive setup
#   ./setup.sh --docker             # Docker mode (skip install-mode prompt)
#   ./setup.sh --native             # Native mode (recommended for VMs)
#   ./setup.sh --cpu                # CPU-only mode (no GPU)
#   ./setup.sh --tier <1-5>         # Skip menu, pick tier directly
#   ./setup.sh --tier 4 --coder     # Use qwen3-coder instead of qwen3.5
#
# Model Tiers:
#   1) CPU-only  — qwen3.5:4b            (~3.4GB download, needs 8GB+ RAM)
#   2) 8GB VRAM  — qwen3.5:9b            (~6.6GB download)  [RTX 3060/4060]
#   3) 16GB VRAM — gemma4:26b             (~18GB download)   [RTX 4080/4070Ti-16GB]
#   4) 24GB VRAM — gemma4:31b             (~20GB download)   [RTX 4090]
#                  or qwen3-coder:30b-a3b (~19GB, code-specialized MoE)
#   5) 48GB VRAM — gemma4:31b-it-q8_0    (~34GB, Q8 quality) [A6000/dual GPU]
#                  or qwen3-coder:30b-a3b-q8_0 (~32GB, code-specialized MoE Q8)
###############################################################################

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Cleanup trap ───────────────────────────────────────────────
CLEANUP_DOCKER=false
cleanup() {
  echo ""
  warn "Setup interrupted. Cleaning up..."
  if [ -n "${OLLAMA_PID:-}" ]; then
    kill "$OLLAMA_PID" 2>/dev/null || true
  fi
  if [ -n "${GATEWAY_PID:-}" ]; then
    kill "$GATEWAY_PID" 2>/dev/null || true
  fi
  if [ "$CLEANUP_DOCKER" = true ]; then
    warn "Stopping Docker containers..."
    docker compose down 2>/dev/null || true
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
  return 1
}

suggest_tier() {
  local vram_mb=$1
  if [ "$vram_mb" -ge 40000 ]; then echo 5
  elif [ "$vram_mb" -ge 20000 ]; then echo 4
  elif [ "$vram_mb" -ge 14000 ]; then echo 3
  elif [ "$vram_mb" -ge 6000 ]; then echo 2
  else echo 1; fi
}

# ── Disk space check ──────────────────────────────────────────
model_disk_gb() {
  case "$1" in
    1) echo 5 ;;  2) echo 8 ;;  3) echo 20 ;;  4) echo 22 ;;  5) echo 36 ;;
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
echo -e "${CYAN}"
cat << 'BANNER'

  +=========================================================+
  |                                                           |
  |   The Librarian                                           |
  |   Keeper of the Ancient Code                              |
  |                                                           |
  |   A Shiba dev-sage from Shibatopia                        |
  |   Powered by OpenClaw + Ollama + Gemma4/Qwen3.5            |
  |                                                           |
  +=========================================================+

BANNER
echo -e "${NC}"

# ── Parse args ──────────────────────────────────────────────────
CPU_ONLY=false
TIER=""
USE_CODER=""
INSTALL_MODE=""
DO_UNINSTALL=false
for arg in "$@"; do
  case "$arg" in
    --cpu) CPU_ONLY=true; TIER=1 ;;
    --coder) USE_CODER=true ;;
    --docker) INSTALL_MODE=docker ;;
    --native) INSTALL_MODE=native ;;
    --uninstall) DO_UNINSTALL=true ;;
    --tier)
      # Next arg is the tier number — handled below
      ;;
    1|2|3|4|5)
      # Accept bare numbers after --tier
      if [ "${PREV_ARG:-}" = "--tier" ]; then
        TIER="$arg"
      fi
      ;;
    --help|-h)
      echo "Usage: ./setup.sh [--docker|--native] [--cpu] [--tier <1-5>] [--coder] [--uninstall]"
      echo ""
      echo "Install modes:"
      echo "  --docker      Run everything in Docker containers (needs Docker Desktop)"
      echo "  --native      Install directly on the host (recommended for VMs)"
      echo ""
      echo "Options:"
      echo "  --cpu         Run without GPU (CPU-only inference, uses qwen3.5:4b)"
      echo "  --tier <N>    Skip the interactive menu and use tier N directly"
      echo "  --coder       Use qwen3-coder (code-specialized) instead of qwen3.5 for tiers 4-5"
      echo "  --uninstall   Remove The Librarian (Docker containers/volumes or native install)"
      echo ""
      echo "Tiers:"
      echo "  1  CPU-only   qwen3.5:4b            (~3.4GB)  Needs 8GB+ RAM"
      echo "  2  8GB VRAM   qwen3.5:9b            (~6.6GB)  RTX 3060 / 4060"
      echo "  3  16GB VRAM  gemma4:26b (MoE)      (~18GB)   RTX 4080 / 4070Ti-16GB"
      echo "  4  24GB VRAM  gemma4:31b            (~20GB)   RTX 4090"
      echo "              or qwen3-coder:30b-a3b   (~19GB)   with --coder"
      echo "  5  48GB VRAM  gemma4:31b-it-q8_0    (~34GB)   A6000 / dual GPU (Q8)"
      echo "              or qwen3-coder:30b-a3b-q8_0 (~32GB) with --coder (Q8)"
      exit 0
      ;;
  esac
  PREV_ARG="$arg"
done

# Handle --tier N (two-arg form)
i=0
for arg in "$@"; do
  i=$((i + 1))
  if [ "$arg" = "--tier" ]; then
    # Get next arg
    next_i=$((i + 1))
    j=0
    for a2 in "$@"; do
      j=$((j + 1))
      if [ $j -eq $next_i ]; then
        TIER="$a2"
        break
      fi
    done
  fi
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Uninstall ─────────────────────────────────────────────────
if [ "$DO_UNINSTALL" = true ]; then
  echo ""
  echo -e "${BOLD}Uninstall The Librarian${NC}"
  echo ""
  echo -e "  ${CYAN}1)${NC}  Docker — Remove containers, images, and volumes"
  echo -e "  ${CYAN}2)${NC}  Native — Remove config, stop services"
  echo -e "  ${CYAN}3)${NC}  Both"
  echo ""

  while true; do
    read -rp "  What to uninstall? [1/2/3]: " UNINST_CHOICE
    case "$UNINST_CHOICE" in
      1|2|3) break ;;
      *) echo -e "  ${RED}Please enter 1, 2, or 3.${NC}" ;;
    esac
  done

  if [ "$UNINST_CHOICE" = "1" ] || [ "$UNINST_CHOICE" = "3" ]; then
    info "Removing Docker containers and volumes..."
    cd "$SCRIPT_DIR"
    docker compose down -v 2>/dev/null || true
    docker rmi openclaw-sandbox:bookworm-slim 2>/dev/null || true
    success "Docker containers, volumes, and sandbox image removed."
  fi

  if [ "$UNINST_CHOICE" = "2" ] || [ "$UNINST_CHOICE" = "3" ]; then
    info "Stopping native services..."
    pkill -f 'openclaw serve' 2>/dev/null || true

    if [ -d "$HOME/.openclaw" ]; then
      read -rp "  Remove ~/.openclaw config directory? [y/N]: " RM_CONFIG
      case "${RM_CONFIG:-N}" in
        y|Y|yes|Yes)
          rm -rf "$HOME/.openclaw"
          success "Removed ~/.openclaw"
          ;;
        *) info "Kept ~/.openclaw" ;;
      esac
    fi
    success "Native services stopped."
  fi

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

# ── Model tier definitions ─────────────────────────────────────
# Each tier: MODEL_TAG  DOWNLOAD_SIZE  DESCRIPTION
tier_model()   {
  case "$1" in
    1) echo "qwen3.5:4b" ;;
    2) echo "qwen3.5:9b" ;;
    3) echo "gemma4:26b" ;;
    4) echo "gemma4:31b" ;;
    5) echo "gemma4:31b-it-q8_0" ;;
  esac
}

tier_size()    {
  case "$1" in
    1) echo "~3.4GB" ;;
    2) echo "~6.6GB" ;;
    3) echo "~18GB" ;;
    4) echo "~20GB" ;;
    5) echo "~34GB" ;;
  esac
}

tier_label()   {
  case "$1" in
    1) echo "CPU-only    (qwen3.5:4b)             — Lightweight, needs 8GB+ RAM" ;;
    2) echo "8GB VRAM    (qwen3.5:9b)             — RTX 3060 / 4060" ;;
    3) echo "16GB VRAM   (gemma4:26b MoE)          — RTX 4080 / 4070Ti-16GB" ;;
    4) echo "24GB VRAM   (gemma4:31b)              — RTX 4090" ;;
    5) echo "48GB VRAM   (gemma4:31b-it-q8_0)      — A6000 / dual GPU (best)" ;;
  esac
}

# Coder model alternatives for tiers 4-5
coder_model()  {
  case "$1" in
    4) echo "qwen3-coder:30b-a3b" ;;
    5) echo "qwen3-coder:30b-a3b-q8_0" ;;
  esac
}

coder_size()   {
  case "$1" in
    4) echo "~19GB" ;;
    5) echo "~32GB" ;;
  esac
}

model_note()   {
  if [ "$USE_CODER" = "true" ] && [ "$TIER" -ge 4 ]; then
    case "$TIER" in
      4) echo "30B MoE (3.3B active), Q4_K_M — code-specialized, fast inference, 256K context." ;;
      5) echo "30B MoE (3.3B active), Q8_0 — max quality code-specialized agent." ;;
    esac
  else
    case "$TIER" in
      1) echo "4B params — lightweight model for CPU inference. Needs 8GB+ system RAM." ;;
      2) echo "9B params, Q4_K_M quantization — fits comfortably in 8GB VRAM." ;;
      3) echo "Google Gemma 4 26B MoE (3.8B active), Q4_K_M — code & reasoning optimized, 256K context." ;;
      4) echo "Google Gemma 4 31B dense, Q4_K_M — best quality model for 24GB VRAM, 256K context." ;;
      5) echo "Google Gemma 4 31B dense, Q8_0 — max quality for 48GB+ VRAM." ;;
    esac
  fi
}

# ── Install mode selection ────────────────────────────────────
if [ -z "$INSTALL_MODE" ]; then
  echo ""
  echo -e "${BOLD}How would you like to install The Librarian?${NC}"
  echo ""
  echo -e "  ${CYAN}1)${NC}  ${BOLD}Docker${NC} — Run everything in containers"
  echo -e "      Easy to install and remove. Requires Docker Desktop."
  echo ""
  echo -e "  ${CYAN}2)${NC}  ${BOLD}Native${NC} — Install directly on this machine"
  echo -e "      Better GPU performance, no Docker needed."
  echo -e "      ${YELLOW}Recommended: run this inside a VM for easy cleanup.${NC}"
  echo ""

  while true; do
    read -rp "  Enter choice [1/2]: " MODE_CHOICE
    case "$MODE_CHOICE" in
      1) INSTALL_MODE=docker; break ;;
      2) INSTALL_MODE=native; break ;;
      *) echo -e "  ${RED}Please enter 1 or 2.${NC}" ;;
    esac
  done
  echo ""
fi

info "Install mode: $INSTALL_MODE"

# ── Tier selection menu ─────────────────────────────────────────
if [ -z "$TIER" ]; then
  # Auto-detect VRAM and suggest a tier
  DETECTED_VRAM=$(detect_vram_mb)
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
# For tiers 4 and 5, offer a choice between qwen3.5 (general/agentic)
# and qwen3-coder (code-specialized MoE).
if [ "$TIER" -ge 4 ] && [ -z "$USE_CODER" ]; then
  echo ""
  echo -e "${BOLD}Choose your model variant for tier $TIER:${NC}"
  echo ""
  echo -e "  ${CYAN}a)${NC}  gemma4   — Google Gemma 4, best code & reasoning, multimodal, 256K context"
  echo -e "      $(tier_model "$TIER") ($(tier_size "$TIER") download)"
  echo ""
  echo -e "  ${CYAN}b)${NC}  qwen3-coder — Code-specialized MoE (3.3B active params, very fast)"
  echo -e "      $(coder_model "$TIER") ($(coder_size "$TIER") download)"
  echo ""

  while true; do
    read -rp "  Enter variant [a/b]: " VARIANT
    case "$VARIANT" in
      a|A) USE_CODER=false; break ;;
      b|B) USE_CODER=true; break ;;
      *) echo -e "  ${RED}Please enter 'a' or 'b'.${NC}" ;;
    esac
  done
  echo ""
fi

if [ "$USE_CODER" = "true" ] && [ "$TIER" -ge 4 ]; then
  MODEL=$(coder_model "$TIER")
  MODEL_SIZE=$(coder_size "$TIER")
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

###############################################################################
#                           DOCKER INSTALL PATH                               #
###############################################################################
if [ "$INSTALL_MODE" = "docker" ]; then

  # ── Check / Install Docker ────────────────────────────────────
  info "Checking for Docker..."
  if ! command -v docker &> /dev/null; then
    warn "Docker is not installed."
    echo ""
    if [[ "$OSTYPE" == "linux"* ]]; then
      echo -e "  ${BOLD}Install Docker Engine now?${NC}"
      echo "  This will run the official Docker install script (https://get.docker.com)."
      echo ""
      read -rp "  Install Docker? [Y/n]: " INSTALL_DOCKER
      case "${INSTALL_DOCKER:-Y}" in
        n|N|no|No)
          echo ""
          echo "  Install Docker manually from https://www.docker.com/products/docker-desktop/"
          echo "  Then re-run this script."
          exit 1
          ;;
        *)
          info "Installing Docker Engine..."
          curl -fsSL https://get.docker.com | sh
          # Add current user to docker group so we don't need sudo
          if [ "$(id -u)" -ne 0 ]; then
            sudo usermod -aG docker "$USER"
            warn "Added $USER to 'docker' group. You may need to log out and back in,"
            warn "or run 'newgrp docker' before re-running this script."
          fi
          if ! command -v docker &> /dev/null; then
            error "Docker installation failed. Please install manually."
            exit 1
          fi
          success "Docker installed."
          ;;
      esac
    elif [[ "$OSTYPE" == "darwin"* ]]; then
      if command -v brew &> /dev/null; then
        echo -e "  ${BOLD}Install Docker Desktop via Homebrew?${NC}"
        read -rp "  Install Docker? [Y/n]: " INSTALL_DOCKER
        case "${INSTALL_DOCKER:-Y}" in
          n|N|no|No)
            echo ""
            echo "  Install Docker Desktop from https://www.docker.com/products/docker-desktop/"
            echo "  Then re-run this script."
            exit 1
            ;;
          *)
            info "Installing Docker Desktop via Homebrew..."
            brew install --cask docker
            echo ""
            warn "Docker Desktop installed. Please open it from Applications to start the daemon,"
            warn "then re-run this script."
            exit 0
            ;;
        esac
      else
        error "Docker is not installed."
        echo ""
        echo "  Install Docker Desktop from:"
        echo "    https://www.docker.com/products/docker-desktop/"
        echo ""
        echo "  Then re-run this script."
        exit 1
      fi
    else
      error "Docker is not installed. Please install from https://www.docker.com/products/docker-desktop/"
      exit 1
    fi
  fi

  if ! docker info &> /dev/null 2>&1; then
    error "Docker is not running. Please start Docker Desktop and try again."
    exit 1
  fi
  success "Docker is running."

  # ── Check Docker Compose ────────────────────────────────────
  if ! docker compose version &> /dev/null 2>&1; then
    error "Docker Compose V2 not found. Please update Docker Desktop."
    exit 1
  fi
  success "Docker Compose available."

  # ── GPU Check ─────────────────────────────────────────────────
  COMPOSE_FILES=(-f docker-compose.yml)
  if [ "$CPU_ONLY" = true ]; then
    warn "CPU-only mode. Inference will be slower but functional."
    COMPOSE_FILES+=(-f docker-compose.cpu.yml)
  else
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
      success "NVIDIA GPU detected."
    else
      warn "No NVIDIA GPU detected. Falling back to CPU-only mode."
      warn "Use --cpu flag to suppress this warning."
      COMPOSE_FILES+=(-f docker-compose.cpu.yml)
      CPU_ONLY=true
    fi
  fi

  # ── Pre-flight checks ─────────────────────────────────────────
  check_port 11434 "Ollama"
  check_port 18789 "OpenClaw Gateway"
  check_disk_space "$(model_disk_gb "$TIER")"

  # Confirmation before download
  echo ""
  echo -e "  ${BOLD}Ready to install:${NC}"
  echo -e "    Mode:      Docker"
  echo -e "    Model:     $MODEL ($MODEL_SIZE download)"
  if [ "$CPU_ONLY" = true ]; then
    echo -e "    GPU:       CPU-only"
  fi
  echo ""
  read -rp "  Proceed? [Y/n]: " PROCEED
  case "${PROCEED:-Y}" in
    n|N|no|No) echo "  Aborting."; exit 0 ;;
  esac
  echo ""

  # ── Start Services ────────────────────────────────────────────
  info "Starting The Librarian's workstation..."
  CLEANUP_DOCKER=true
  echo ""

  cd "$SCRIPT_DIR"

  # Pull images first
  info "Pulling Docker images (this may take a few minutes on first run)..."
  docker compose "${COMPOSE_FILES[@]}" pull

  # Start Ollama and OpenClaw Gateway
  info "Starting Ollama + OpenClaw Gateway..."
  docker compose "${COMPOSE_FILES[@]}" up -d ollama openclaw-gateway

  # Wait for Ollama to be ready
  info "Waiting for Ollama to initialize..."
  if ! spin_wait 30 "http://localhost:11434/api/tags" "Ollama"; then
    error "Ollama failed to start after 60 seconds."
    echo "  Check logs: docker compose logs ollama"
    exit 1
  fi
  success "Ollama is ready."

  # Pull the model
  info "Pulling $MODEL ($MODEL_SIZE download, this is a one-time operation)..."
  echo "  $(model_note)"
  echo ""
  docker exec librarian-ollama ollama pull "$MODEL"
  success "Model downloaded and ready."

  # ── Write model selection to config ───────────────────────────
  info "Configuring OpenClaw to use $MODEL..."
  CONFIG_FILE="openclaw/config.json5"
  if [ -f "$CONFIG_FILE" ]; then
    sed -i.bak "s|name: \"[^\"]*\"|name: \"$MODEL\"|" "$CONFIG_FILE" && rm -f "${CONFIG_FILE}.bak"
    success "Config updated: model set to $MODEL"
  else
    warn "Config file not found at $CONFIG_FILE — you may need to set the model manually."
  fi

  # ── Build Sandbox Image ──────────────────────────────────────
  info "Building sandbox image for agent isolation..."
  if docker image inspect openclaw-sandbox:bookworm-slim > /dev/null 2>&1; then
    success "Sandbox image already exists."
  else
    docker build -t openclaw-sandbox:bookworm-slim -f - . <<'DOCKERFILE'
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Run as non-root
RUN useradd -m -s /bin/bash sandbox
USER sandbox
WORKDIR /home/sandbox
DOCKERFILE
    success "Sandbox image built."
  fi

  # ── Verify OpenClaw Gateway ──────────────────────────────────
  info "Waiting for OpenClaw Gateway to start..."
  if ! spin_wait 30 "http://localhost:18789/healthz" "Gateway"; then
    error "OpenClaw Gateway failed to start after 60 seconds."
    echo "  Check logs: docker compose logs openclaw-gateway"
    exit 1
  fi
  success "OpenClaw Gateway is running."

  # ── Done (Docker) ────────────────────────────────────────────
  echo ""
  echo -e "${GREEN}==========================================================${NC}"
  echo -e "${GREEN}  The Librarian is ready!  (Docker mode)${NC}"
  echo -e "${GREEN}==========================================================${NC}"
  echo ""
  echo -e "  Model:  ${BOLD}$MODEL${NC} ($(tier_label "$TIER"))"
  echo ""
  echo "  Open in your browser:"
  echo -e "    ${CYAN}http://localhost:18789${NC}"
  echo ""
  echo "  Useful commands:"
  echo "    docker compose logs -f openclaw-gateway   # Watch OpenClaw logs"
  echo "    docker compose logs -f ollama             # Watch Ollama logs"
  echo "    docker compose down                       # Stop everything"
  echo "    docker compose up -d                      # Restart"
  echo ""
  echo "  Change model tier:"
  echo "    docker exec librarian-ollama ollama pull <model>"
  echo "    Then update 'model.name' in openclaw/config.json5"
  echo ""
  echo "  Sandboxing:"
  echo "    Agent tool execution runs inside isolated Docker containers."
  echo "    Sandbox containers have no network access by default."
  echo "    Edit openclaw/config.json5 to adjust sandbox settings."
  echo ""
  echo -e "  ${YELLOW}The Librarian guards the Ancient Lore. May your code be free"
  echo -e "  of Shadowcats.${NC}"
  echo ""

fi # end Docker path

###############################################################################
#                           NATIVE INSTALL PATH                               #
###############################################################################
if [ "$INSTALL_MODE" = "native" ]; then

  # ── Pre-flight checks ─────────────────────────────────────────
  check_port 11434 "Ollama"
  check_port 18789 "OpenClaw Gateway"
  check_disk_space "$(model_disk_gb "$TIER")"

  # Confirmation before download
  echo ""
  echo -e "  ${BOLD}Ready to install:${NC}"
  echo -e "    Mode:      Native (host install)"
  echo -e "    Model:     $MODEL ($MODEL_SIZE download)"
  if [ "$CPU_ONLY" = true ]; then
    echo -e "    GPU:       CPU-only"
  fi
  echo ""
  read -rp "  Proceed? [Y/n]: " PROCEED
  case "${PROCEED:-Y}" in
    n|N|no|No) echo "  Aborting."; exit 0 ;;
  esac
  echo ""

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
  # Check if ollama is already serving
  if curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
    success "Ollama is already running."
  else
    # Try systemctl first (Linux), then launch in background
    if command -v systemctl &> /dev/null && systemctl is-enabled ollama &> /dev/null 2>&1; then
      sudo systemctl start ollama
    else
      # Start in background (macOS or non-systemd Linux)
      ollama serve &> /dev/null &
      OLLAMA_PID=$!
      disown "$OLLAMA_PID" 2>/dev/null || true
    fi

    # Wait for Ollama to be ready
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

  # ── Install Node.js (if needed) ──────────────────────────────
  info "Checking for Node.js..."
  if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    success "Node.js $NODE_VERSION is installed."
  else
    info "Installing Node.js..."
    if command -v apt-get &> /dev/null; then
      # Debian/Ubuntu
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
      sudo apt-get install -y nodejs
    elif command -v dnf &> /dev/null; then
      # Fedora/RHEL
      curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo bash -
      sudo dnf install -y nodejs
    elif command -v brew &> /dev/null; then
      # macOS with Homebrew
      brew install node
    else
      error "Could not auto-install Node.js. Please install Node.js 18+ from https://nodejs.org"
      exit 1
    fi
    success "Node.js installed ($(node --version))."
  fi

  # ── Install OpenClaw Gateway ─────────────────────────────────
  info "Installing OpenClaw Gateway..."
  if command -v openclaw &> /dev/null; then
    success "OpenClaw Gateway is already installed."
  else
    npm install -g @openclaw/gateway
    if ! command -v openclaw &> /dev/null; then
      error "OpenClaw Gateway installation failed."
      echo "  Try: npm install -g @openclaw/gateway"
      exit 1
    fi
    success "OpenClaw Gateway installed."
  fi

  # ── Deploy configuration ─────────────────────────────────────
  OPENCLAW_DIR="$HOME/.openclaw"
  info "Deploying configuration to $OPENCLAW_DIR..."
  mkdir -p "$OPENCLAW_DIR/skills"

  # Copy personality and config
  cp "$SCRIPT_DIR/openclaw/SOUL.md" "$OPENCLAW_DIR/SOUL.md"
  cp -r "$SCRIPT_DIR/openclaw/skills/"* "$OPENCLAW_DIR/skills/" 2>/dev/null || true

  # Write native config (Ollama on localhost, no Docker sandbox)
  cat > "$OPENCLAW_DIR/config.json5" << NATIVECONF
{
  // ── The Librarian — OpenClaw Configuration (native install) ───
  //
  // Model: $MODEL via local Ollama
  // Install mode: native (no Docker sandboxing)

  // Model provider configuration
  model: {
    provider: "ollama",
    name: "$MODEL",
    ollama: {
      baseUrl: "http://localhost:11434"
    }
  },

  // Gateway settings
  gateway: {
    bind: "lan"
  },

  // Tool approval policies
  tools: {
    requireApproval: [
      "shell:rm",
      "shell:sudo",
      "write:/etc/*",
      "write:/usr/*"
    ]
  }
}
NATIVECONF

  success "Config deployed: model set to $MODEL"

  # ── Start OpenClaw Gateway ───────────────────────────────────
  info "Starting OpenClaw Gateway..."

  # Check if already running
  if curl -sf http://localhost:18789/healthz > /dev/null 2>&1; then
    success "OpenClaw Gateway is already running."
  else
    openclaw serve --config "$OPENCLAW_DIR/config.json5" &> "$OPENCLAW_DIR/gateway.log" &
    GATEWAY_PID=$!
    disown "$GATEWAY_PID" 2>/dev/null || true

    if ! spin_wait 30 "http://localhost:18789/healthz" "Gateway"; then
      error "OpenClaw Gateway failed to start after 60 seconds."
      echo "  Check logs: cat $OPENCLAW_DIR/gateway.log"
      exit 1
    fi
    success "OpenClaw Gateway is running (PID $GATEWAY_PID)."
  fi

  # ── Done (Native) ────────────────────────────────────────────
  echo ""
  echo -e "${GREEN}==========================================================${NC}"
  echo -e "${GREEN}  The Librarian is ready!  (native install)${NC}"
  echo -e "${GREEN}==========================================================${NC}"
  echo ""
  echo -e "  Model:  ${BOLD}$MODEL${NC} ($(tier_label "$TIER"))"
  echo ""
  echo "  Open in your browser:"
  echo -e "    ${CYAN}http://localhost:18789${NC}"
  echo ""
  echo "  Useful commands:"
  echo "    tail -f ~/.openclaw/gateway.log         # Watch gateway logs"
  echo "    ollama ps                               # Check running models"
  echo "    ollama stop $MODEL                      # Unload model from VRAM"
  echo ""
  echo "  Change model:"
  echo "    ollama pull <model>"
  echo "    Then update 'model.name' in ~/.openclaw/config.json5"
  echo ""
  echo "  Stop everything:"
  echo "    pkill -f 'openclaw serve'               # Stop gateway"
  echo "    ollama stop $MODEL                      # Unload model"
  echo "    # Or: sudo systemctl stop ollama        # Stop Ollama service"
  echo ""
  echo "  Config: $OPENCLAW_DIR/config.json5"
  echo ""
  echo -e "  ${YELLOW}NOTE: Native mode does not include Docker sandboxing."
  echo -e "  For isolation, run this setup inside a VM.${NC}"
  echo ""
  echo -e "  ${YELLOW}The Librarian guards the Ancient Lore. May your code be free"
  echo -e "  of Shadowcats.${NC}"
  echo ""

fi # end Native path

# Try to open browser
if command -v xdg-open &> /dev/null; then
  xdg-open "http://localhost:18789" 2>/dev/null || true
elif command -v open &> /dev/null; then
  open "http://localhost:18789" 2>/dev/null || true
fi
