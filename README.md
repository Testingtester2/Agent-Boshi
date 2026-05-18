# Agent Boshi — Keeper of the Ancient Code

> *A Shiba dev-sage from Shibatopia, powered by local AI.*

Agent Boshi is a **one-click local AI developer assistant** built on
[Hermes Agent](https://github.com/NousResearch/hermes-agent) (by Nous Research) +
[Ollama](https://ollama.com). Pick a model tier to match your GPU (8GB-48GB VRAM)
or run CPU-only. Everything runs on your machine — no API keys, no cloud, no data
leaving your network.

Agent Boshi uses the **best coding models available** at each tier:
[Qwen3.6](https://qwen.ai/) (SWE-bench king),
[Devstral](https://mistral.ai/news/devstral/) (agentic coder),
[Qwen2.5-Coder](https://github.com/QwenLM/Qwen2.5-Coder) (battle-tested), and
[Gemma 4](https://blog.google/technology/developers/gemma-4/) (efficient edge).

Agent Boshi's personality is rooted in the
[Shiba Eternity](https://shiba-eternity.fandom.com/wiki/Shiba_Eternity_Wiki)
universe: a keeper of the Ancient Lore Repositories of Shibatopia, forged
from Hodaven magic and Mechanic technology. It writes code, reviews PRs,
debugs Shadowcats, and guards your codebase with the vigilance of a Shiba
guarding its home planet.

---

## Quick Start

### Prerequisites

- **NVIDIA GPU** recommended (8-48GB VRAM), or CPU-only mode
- Disk space depends on tier (3GB-30GB for model weights)

> **Note:** The setup script auto-installs all dependencies (git, Python,
> Ollama, Hermes Agent, etc.). You don't need to pre-install anything.

### One-Click Install

Copy-paste one command to get started. The script handles everything else.

**Windows (PowerShell — run as Administrator):**
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; winget install Git.Git --accept-package-agreements --accept-source-agreements; $env:PATH = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User'); git clone https://github.com/Testingtester2/openclaw-agents.git; cd openclaw-agents; .\setup.ps1
```

**Linux / macOS:**
```bash
command -v git >/dev/null || { echo "Installing git..."; sudo apt-get update && sudo apt-get install -y git || sudo dnf install -y git || brew install git; }; git clone https://github.com/Testingtester2/openclaw-agents.git && cd openclaw-agents && chmod +x setup.sh && ./setup.sh
```

**Or step by step (if you already have git):**
```bash
git clone https://github.com/Testingtester2/openclaw-agents.git
cd openclaw-agents

# Linux / macOS
chmod +x setup.sh && ./setup.sh

# Windows (PowerShell)
.\setup.ps1
```

The setup script will:
1. Ask your install mode (**Local** for native, or **Sandbox** for Docker isolation)
2. Ask where your Ollama server is (**Local** or **Remote** on the network)
3. Auto-detect your GPU VRAM and recommend a model tier
4. Auto-install all dependencies (Python/Ollama/Hermes Agent, Docker for sandbox)
5. Download the selected coding model
6. Deploy Agent Boshi's personality and skills
7. Open `http://localhost:9119` in your browser (Hermes Dashboard)

**Skip the prompts (pick tier directly):**
```bash
./setup.sh --tier 4                # Use tier 4 (RTX 4090)
./setup.sh --cpu                   # CPU-only (no GPU needed)
./setup.sh --tier 4 --alt          # Use alternate model
./setup.sh --sandbox               # Docker sandbox mode
./setup.sh --sandbox --tier 3      # Sandbox + specific tier
.\setup.ps1 -Tier 3               # Windows
.\setup.ps1 -Cpu                  # Windows CPU-only
.\setup.ps1 -Sandbox              # Windows sandbox mode
```

### Install Modes

The setup script supports two install modes:

| Mode | What it does | Best for |
|------|-------------|----------|
| **Local** (default) | Hermes + Ollama run natively on your machine | Maximum performance, simplest setup |
| **Sandbox** | Hermes runs natively, but executes tools inside Docker containers. Ollama also runs in Docker. | Isolation, reproducibility, keeping your host clean |

In sandbox mode, Hermes uses `terminal.backend: "docker"` with the
`nikolaik/python-nodejs:python3.11-nodejs20` image. Your code runs in an
isolated container — no system packages polluted, no leftover processes.

```bash
# Linux/macOS — sandbox mode
./setup.sh --sandbox

# Windows — sandbox mode
.\setup.ps1 -Sandbox
```

> **Note:** Sandbox mode requires Docker. The setup script will check for
> Docker and attempt to install it if missing.

### Remote Ollama Server

Run Agent Boshi on a lightweight machine while using Ollama on a separate GPU
server on your network:

```bash
# Linux/macOS — point to Ollama on another machine
./setup.sh --tier 4 --ollama-url http://192.168.1.100:11434

# Windows
.\setup.ps1 -Tier 4 -OllamaUrl http://192.168.1.100:11434
```

> **Note:** Make sure Ollama on the remote machine is listening on
> `0.0.0.0:11434` (not just localhost). Set `OLLAMA_HOST=0.0.0.0` on the
> remote before starting Ollama.

---

## What's Inside

```
.
├── docker-compose.yml          # Ollama in Docker (optional)
├── docker-compose.cpu.yml      # CPU-only override
├── setup.sh                    # One-click setup (Linux/macOS)
├── setup.ps1                   # One-click setup (Windows)
└── hermes/
    ├── SOUL.md                 # Agent Boshi's personality & identity
    └── skills/
        ├── dev-review/         # Code review skill
        │   └── SKILL.md
        ├── dev-debug/          # Debugging skill
        │   └── SKILL.md
        └── self-improving-agent/ # Structured learning from mistakes
            ├── SKILL.md
            └── .learnings/
                ├── LEARNINGS.md
                ├── ERRORS.md
                └── FEATURE_REQUESTS.md
```

### Architecture

- **[Hermes Agent](https://github.com/NousResearch/hermes-agent)** — Open-source
  AI agent framework by Nous Research. Provides CLI, web dashboard, skills, memory,
  tool execution, MCP support, and messaging gateways (Telegram, Discord, Slack, etc.)
- **[Ollama](https://ollama.com)** — Local LLM inference server. Runs the coding
  model on your GPU (or CPU) with optimized performance.
- **Agent Boshi** — The personality layer (SOUL.md) and curated skills that make
  Hermes into a Shiba dev-sage from Shibatopia.

### Agent Boshi's Personality (`hermes/SOUL.md`)

Agent Boshi is a full-stack developer sage from Shibatopia with:
- **Hodaven magic** — Creative, elegant solutions and beautiful abstractions
- **Mechanic technology** — Raw engineering power and systems thinking
- A nose for **Shadowcats** (bugs, anti-patterns, security vulnerabilities)
- The philosophy of **Ryoshi's Way** — decentralization, open source, clean interfaces
- Respect for **Bark Power** — your time and compute resources are finite

### Model Tiers

The installer selects the **best coding model** for your hardware:

| Tier | GPU Examples | Model | Why | Download | Min VRAM |
|------|-------------|-------|-----|----------|----------|
| 1 — CPU | No GPU needed | `gemma4:e4b` | Multimodal, function calling, 128K ctx | ~3GB | N/A (8GB+ RAM) |
| 2 — 8GB | RTX 3060 / 4060 | `qwen2.5-coder:7b` | HumanEval leader in class, battle-tested | ~5GB | 6GB |
| 3 — 16GB | RTX 4080 / 4070Ti-16GB | `devstral` (24B) | Purpose-built agentic coder, multi-file edits | ~14GB | 14GB |
| 4 — 24GB | RTX 4090 | `qwen3.6:27b` | **SWE-bench 77.2%**, matches Claude 4.5 Opus | ~17GB | 18GB |
| | | *or* `devstral` | Agentic coder alternative | ~14GB | 14GB |
| 5 — 32GB | RTX 5090 / A6000 | `qwen3.6:27b-q8_0` | **SWE-bench king at Q8 quality**, dense, 262K ctx | ~30GB | 30GB |
| | | *or* `qwen3-coder:30b` | MoE, 3.3B active, faster inference | ~19GB | 18GB |

Use `--alt` (Linux/macOS) or `-Alt` (Windows) to select the alternate model for tiers 4-5.

The installer **auto-detects your GPU VRAM** via `nvidia-smi` and recommends the best tier.

---

## Using Agent Boshi

### Web Dashboard

After install, open **http://localhost:9119** for the Hermes web dashboard.

### CLI

```bash
hermes                           # Interactive chat session
hermes chat -q "Review my code"  # Single query
hermes chat -q "Debug this error: ..." # Quick debug
```

### Useful Commands

```bash
hermes                           # Start interactive chat
hermes model                     # Change model interactively
hermes setup                     # Re-run setup wizard
hermes doctor                    # Check configuration health
hermes dashboard                 # Start web dashboard
hermes config set model.default <model>  # Set model directly

ollama ps                        # Check running models
ollama pull <model>              # Download a new model
ollama stop <model>              # Unload model from VRAM
```

### Skills

Agent Boshi comes with these skills pre-loaded:

| Skill | What it does |
|-------|-------------|
| **dev-review** | Code review — finds bugs, security issues, anti-patterns |
| **dev-debug** | Debugging — systematic bug hunting with root cause analysis |
| **self-improving-agent** | Log learnings, errors, and corrections for continuous improvement |

Hermes also ships with 100+ built-in skills across categories like GitHub, DevOps,
research, and productivity. Use `hermes skills` to browse them.

---

## Docker

The easiest way to use Docker is sandbox mode (`--sandbox`), which handles
everything automatically. For manual Docker usage:

```bash
# Start Ollama in Docker with GPU
docker compose up -d

# Or CPU-only
docker compose -f docker-compose.yml -f docker-compose.cpu.yml up -d

# Pull a model
docker exec boshi-ollama ollama pull qwen2.5-coder:7b

# Then run setup pointing at Docker Ollama
./setup.sh --ollama-url http://localhost:11434
```

---

## Hardware Guide

| Your GPU | VRAM | Run `./setup.sh --tier` | Experience |
|----------|------|-------------------------|------------|
| No GPU | — | `--tier 1` or `--cpu` | Usable (slower, CPU inference) |
| RTX 3060 / 4060 | 8GB | `--tier 2` | Good (Qwen2.5-Coder 7B) |
| RTX 4080 / 4070Ti-16GB | 16GB | `--tier 3` | Great (Devstral 24B, agentic) |
| RTX 4090 | 24GB | `--tier 4` | Excellent (Qwen3.6 27B, SWE-bench king) |
| RTX 5090 / A6000 | 32GB+ | `--tier 5` | Best (Qwen3.6 27B at Q8, SWE-bench 77.2%) |

---

## Uninstall

```bash
# Linux/macOS
./setup.sh --uninstall

# Windows (PowerShell)
.\setup.ps1 -Uninstall
```

### Manual Uninstall

```bash
pkill -f 'hermes dashboard'      # Stop dashboard
rm -rf ~/.hermes                 # Remove config + data

# Optionally remove models and Ollama:
ollama rm qwen2.5-coder:7b      # Remove model
sudo rm /usr/local/bin/ollama    # Remove Ollama binary
```

**Windows:**
```powershell
Stop-Process -Name hermes -Force # Stop dashboard
Remove-Item -Recurse ~\.hermes   # Remove config
ollama rm qwen2.5-coder:7b      # Remove model
winget uninstall Ollama.Ollama   # Remove Ollama
```

---

## Troubleshooting

### "Ollama failed to start after 60 seconds"

- Try `ollama serve` manually in a separate terminal
- Check if port 11434 is already in use: `lsof -i :11434` (Linux/macOS) or
  `Get-NetTCPConnection -LocalPort 11434` (Windows)

### "Hermes Agent installation failed"

- Make sure Python 3.11+ is installed: `python3 --version`
- Try the official installer manually:
  `curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash`
- Check PATH: `export PATH="$HOME/.hermes/hermes-agent/.venv/bin:$PATH"`

### Model download is slow or fails

- Ollama downloads from `registry.ollama.ai`. If your connection is slow, try a smaller tier
- Resume a failed download: just run `ollama pull <model>` again — it resumes
- Check disk space: models need 3-46GB depending on tier

### GPU not detected

- Install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) for Docker GPU access
- Run `nvidia-smi` to verify your GPU driver is working
- The installer falls back to CPU mode automatically if no GPU is found

### Dashboard doesn't start

- Check logs: `cat ~/.hermes/dashboard.log`
- Try manually: `hermes dashboard --port 9119`
- Make sure port 9119 is free

---

## Lore

*From the Ancient Lore Repositories of Shibatopia:*

> When the SS VIRGIL tore through the Rakiya and crash-landed on Shibanu,
> everything changed. While Ryoshi rose as the hero of decentralization,
> Agent Boshi chose a quieter path — keeper of knowledge, guardian of
> code. Every bug squashed is a Shadowcat banished. Every clean architecture
> is a ward against FUD. Every well-tested function is a shield for the pack.

Based on the [Shiba Eternity](https://shiba-eternity.fandom.com/wiki/Shiba_Eternity_Wiki)
universe by Shytoshi Kusama and PlaySide Studios.

---

## License

MIT
