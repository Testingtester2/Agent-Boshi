# The Librarian — Keeper of the Ancient Code

> *A Shiba dev-sage from Shibatopia, powered by local AI.*

The Librarian is a **one-click local AI developer assistant** built on
[OpenClaw](https://github.com/openclaw/openclaw) +
[Ollama](https://ollama.com) +
[Gemma 4](https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/) /
[Qwen3.5](https://github.com/QwenLM/Qwen3.5). Pick a model tier to match your
GPU (8GB–48GB VRAM) or run CPU-only. Everything runs on your machine — no
API keys, no cloud, no data leaving your network.

In Docker mode, agent tool execution is **sandboxed inside isolated containers**
with no network access by default. In native mode, we recommend running inside
a VM for isolation. Either way, The Librarian can read your code but can't
phone home or damage your host.

The Librarian's personality is rooted in the
[Shiba Eternity](https://shiba-eternity.fandom.com/wiki/Shiba_Eternity_Wiki)
universe: a keeper of the Ancient Lore Repositories of Shibatopia, forged
from Hodaven magic and Mechanic technology. It writes code, reviews PRs,
debugs Shadowcats, and guards your codebase with the vigilance of a Shiba
guarding its home planet.

---

## Quick Start

### Prerequisites

- **NVIDIA GPU** recommended (8-48GB VRAM), or CPU-only mode
- Disk space depends on tier (3.4GB–35GB for model weights)

> **Note:** The setup script auto-installs all dependencies (git, Docker,
> Ollama, Node.js, etc.). You don't need to pre-install anything.

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
1. Ask how you want to install (**Docker** or **Native**)
2. Ask you to pick a model tier based on your GPU VRAM
3. Auto-install all dependencies (Docker/Ollama/Node.js/OpenClaw)
4. Download the selected model (Gemma 4 for upper tiers, Qwen3.5 for lower)
5. Open `http://localhost:18789` in your browser

### Install Modes

| Mode | Best for | Auto-installs | Sandboxing |
|------|----------|---------------|------------|
| **Docker** | Easy setup & cleanup | Docker Engine (Linux) or Docker Desktop (macOS via Homebrew) | Full Docker sandbox isolation |
| **Native** | Better GPU perf, VMs | Ollama, Node.js, OpenClaw Gateway | None (run in a VM for isolation) |

> **Tip:** If you're running in a VM (Multipass, WSL2, etc.), native mode gives
> the best performance and the VM itself provides isolation.

**Skip the prompts (pick mode and tier directly):**
```bash
# Docker mode
./setup.sh --docker --tier 2       # Linux/macOS
.\setup.ps1 -Docker -Tier 2        # Windows

# Native mode (recommended for VMs)
./setup.sh --native --tier 3       # Linux/macOS
.\setup.ps1 -Native -Tier 3        # Windows

# CPU-only shortcut (same as --tier 1)
./setup.sh --cpu
.\setup.ps1 -Cpu
```

### Manual Docker Compose

If you prefer to manage Docker directly (Docker mode only):

```bash
# With GPU
docker compose up -d

# Without GPU (CPU-only)
docker compose -f docker-compose.yml -f docker-compose.cpu.yml up -d

# Pull a model (pick one from the tier table below)
docker exec librarian-ollama ollama pull qwen3.5:9b

# Update config to match
# Edit openclaw/config.json5 → model.name
```

Open **http://localhost:18789** when ready.

---

## What's Inside

```
.
├── docker-compose.yml          # Ollama + OpenClaw orchestration
├── docker-compose.cpu.yml      # CPU-only override (no GPU)
├── setup.sh                    # One-click setup (Linux/macOS)
├── setup.ps1                   # One-click setup (Windows)
└── openclaw/
    ├── SOUL.md                 # The Librarian's personality & identity
    ├── config.json5            # OpenClaw config (model, sandbox, tools)
    └── skills/
        ├── dev-review/         # Code review skill
        │   └── SKILL.md
        ├── dev-debug/          # Debugging skill
        │   └── SKILL.md
        ├── find-skill/         # Discover & install skills from repos
        │   └── SKILL.md
        └── self-improving-agent/ # Self-analysis & improvement
            └── SKILL.md
```

### The Librarian's Personality (`openclaw/SOUL.md`)

The Librarian is a full-stack developer sage from Shibatopia with:
- **Hodaven magic** — Creative, elegant solutions and beautiful abstractions
- **Mechanic technology** — Raw engineering power and systems thinking
- A nose for **Shadowcats** (bugs, anti-patterns, security vulnerabilities)
- The philosophy of **Ryoshi's Way** — decentralization, open source, clean interfaces
- Respect for **Bark Power** — your time and compute resources are finite

### Sandboxing & Isolation

**Docker mode:** Agent tool execution (shell commands, file writes) runs inside
**isolated Docker containers** that are separate from your host machine:

- **No network** — sandbox containers cannot reach the internet by default
- **Read-only root** — the sandbox filesystem is immutable
- **Per-session isolation** — each conversation gets its own container
- **Read-only workspace** — the agent can read your project files but writes stay in the sandbox

To adjust sandbox settings, edit `openclaw/config.json5`. See the
[OpenClaw sandboxing docs](https://docs.openclaw.ai/gateway/sandboxing) for details.

**Native mode:** No Docker sandboxing is used. The agent runs directly on the
host. For isolation, run the setup inside a VM. Tool approval policies still
apply — dangerous commands (`rm`, `sudo`) require manual approval.

> **Note:** The Ollama server runs separately from the agent (it needs GPU
> access), but it only serves model inference — it has no access to your
> files or shell.

### Model Tiers

The installer lets you pick a model based on your hardware. Lower tiers use
[Qwen3.5](https://github.com/QwenLM/Qwen3.5) (Apache 2.0, 256K context), upper
tiers use [Gemma 4](https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/)
(Apache 2.0, 256K context) which benchmarks higher on coding and reasoning tasks.
[Qwen3-Coder](https://github.com/QwenLM/Qwen3-Coder) remains available as a
code-specialized alternative for tiers 4-5.

| Tier | GPU Examples | Model | Params | Quant | Download | Min VRAM | Notes |
|------|-------------|-------|--------|-------|----------|----------|-------|
| 1 — CPU | No GPU needed | `qwen3.5:4b` | 4B | Q4_K_M | ~3.4GB | N/A (8GB+ RAM) | Fast on modern CPUs. Good for simple tasks |
| 2 — 8GB | RTX 3060 / 4060 | `qwen3.5:9b` | 9B | Q4_K_M | ~6.6GB | 6GB | **Default tier.** Strong all-round coding |
| 3 — 16GB | RTX 4080 / 4070Ti-16GB | `gemma4:26b` | 26B MoE (3.8B active) | Q4_K_M | ~18GB | 14GB | Gemma 4 MoE — code & reasoning optimized |
| 4 — 24GB | RTX 4090 | `gemma4:31b` | 31B dense | Q4_K_M | ~20GB | 18GB | Best quality dense model |
| | | *or* `qwen3-coder:30b-a3b` | 30B MoE (3.3B active) | Q4_K_M | ~19GB | 14GB | Code-specialized, very fast |
| 5 — 48GB | A6000 / dual GPU | `gemma4:31b-it-q8_0` | 31B dense | Q8_0 | ~34GB | 36GB | Max quality (Q8 quantization) |
| | | *or* `qwen3-coder:30b-a3b-q8_0` | 30B MoE (3.3B active) | Q8_0 | ~32GB | 28GB | Max quality code-specialized |

For tiers 4-5, the setup script asks you to choose between:
- **gemma4** — Google Gemma 4, best coding & reasoning benchmarks, multimodal
- **qwen3-coder** — Code-specialized MoE with only 3.3B active params (faster inference, 70% code training)

Use `--coder` (Linux/macOS) or `-Coder` (Windows) to skip the prompt and pick qwen3-coder directly.

The installer also **auto-detects your GPU VRAM** via `nvidia-smi` and recommends
the best tier for your hardware.

**Which tier should I pick?**
- Run `nvidia-smi` to check your VRAM
- **No GPU?** Tier 1 (CPU) works on any machine with 8GB+ RAM
- **Not sure?** Tier 2 (8GB) is a safe default — it runs well on most gaming GPUs
- **Want the best local experience?** Tier 4/5 if your GPU can handle it

**Switching tiers later (Docker):**
```bash
docker exec librarian-ollama ollama pull gemma4:31b
# Edit openclaw/config.json5 → change model.name to "gemma4:31b"
docker compose restart openclaw-gateway
```

**Switching tiers later (Native):**
```bash
ollama pull gemma4:31b
# Edit ~/.openclaw/config.json5 → change model.name to "gemma4:31b"
pkill -f 'openclaw serve' && openclaw serve --config ~/.openclaw/config.json5 &
```

---

## Useful Commands

### Docker Mode

```bash
# View logs
docker compose logs -f openclaw-gateway
docker compose logs -f ollama

# Stop everything
docker compose down

# Restart
docker compose up -d

# Update to latest images
docker compose pull && docker compose up -d

# Switch models
docker exec librarian-ollama ollama pull qwen3.5:4b
# Then edit openclaw/config.json5 → model.name
```

### Native Mode

```bash
# View gateway logs
tail -f ~/.openclaw/gateway.log

# Check running models
ollama ps

# Unload model from VRAM
ollama stop qwen3.5:9b

# Stop gateway
pkill -f 'openclaw serve'

# Stop Ollama (systemd)
sudo systemctl stop ollama

# Switch models
ollama pull qwen3.5:27b
# Then edit ~/.openclaw/config.json5 → model.name
```

---

## Hardware Guide

See the **Model Tiers** table above for full details. Quick summary:

| Your GPU | VRAM | Run `./setup.sh --tier` | Experience |
|----------|------|-------------------------|------------|
| No GPU | — | `--tier 1` or `--cpu` | Usable (slower, CPU inference) |
| RTX 3060 / 4060 | 8GB | `--tier 2` | Good (Qwen 9B, fast) |
| RTX 4080 / 4070Ti-16GB | 16GB | `--tier 3` | Great (Gemma 4 26B MoE, strong reasoning) |
| RTX 4090 | 24GB | `--tier 4` | Excellent (Gemma 4 31B, best dense) |
| A6000 / dual GPU | 48GB+ | `--tier 5` | Best quality (Gemma 4 31B Q8) |

Speed depends on model size, context length, and system configuration. Larger
models are smarter but generate tokens more slowly on the same hardware.

---

## Security

### Docker Mode

Docker mode follows OpenClaw's full security recommendations:

1. **Sandboxed agent execution** — tool calls run in isolated containers
2. **No network in sandbox** — prevents data exfiltration
3. **Read-only root** — sandbox filesystem is immutable
4. **Dropped capabilities** — `NET_RAW` and `NET_ADMIN` dropped from gateway
5. **No-new-privileges** — prevents privilege escalation in gateway
6. **Non-root user** — gateway runs as `node` (uid 1000)

### Native Mode

Native mode has lighter security controls:

1. **Tool approval policies** — dangerous commands (`rm`, `sudo`, writes to `/etc`, `/usr`) require manual approval
2. **No Docker sandboxing** — agent commands run directly on the host
3. **Recommended: run in a VM** — use Multipass, WSL2, or a cloud VM for host isolation

For more, see the [OpenClaw security docs](https://docs.openclaw.ai/gateway/sandboxing).

---

## After Install — What To Do Next

Once The Librarian is running at `http://localhost:18789`:

1. **Say hello** — The Librarian will introduce itself and explain its abilities
2. **Try a code review** — Paste a file or point it at your project: *"Review src/app.ts for bugs"*
3. **Debug something** — Describe a bug: *"I'm getting a null pointer in the login flow"*
4. **Ask it to find skills** — *"What skills do you have?"* or *"Find me a skill for testing"*
5. **Let it self-improve** — After a session: *"Analyze your performance and suggest improvements"*

### Installed Skills

| Skill | What it does |
|-------|-------------|
| **dev-review** | Code review — finds bugs, security issues, anti-patterns |
| **dev-debug** | Debugging — systematic bug hunting with root cause analysis |
| **find-skill** | Discover and install new skills from OpenClaw repositories |
| **self-improving-agent** | Analyze performance and improve over time |

---

## Uninstall

### Quick Uninstall (Interactive)

```bash
# Linux/macOS
./setup.sh --uninstall

# Windows (PowerShell)
.\setup.ps1 -Uninstall
```

This walks you through removing Docker containers/volumes and/or native config.

### Manual Uninstall

**Docker mode:**
```bash
cd openclaw-agents
docker compose down -v              # Remove containers + volumes
docker rmi openclaw-sandbox:bookworm-slim  # Remove sandbox image
```

**Native mode:**
```bash
pkill -f 'openclaw serve'           # Stop gateway
rm -rf ~/.openclaw                  # Remove config + logs
# Optionally:
ollama rm qwen3.5:9b                # Remove model (replace with your model)
sudo rm /usr/local/bin/ollama       # Remove Ollama binary
```

**Windows native:**
```powershell
Stop-Process -Name openclaw -Force  # Stop gateway
Remove-Item -Recurse ~\.openclaw    # Remove config
# Optionally:
ollama rm qwen3.5:9b                # Remove model
winget uninstall Ollama.Ollama      # Remove Ollama
```

---

## Troubleshooting

### "Ollama failed to start after 60 seconds"

- **Docker mode:** Check logs with `docker compose logs ollama`
- **Native mode:** Try `ollama serve` manually in a separate terminal
- If Ollama was already running, the port may be in use. Check with `lsof -i :11434` (Linux/macOS) or `Get-NetTCPConnection -LocalPort 11434` (Windows)

### "OpenClaw Gateway failed to start"

- **Docker mode:** `docker compose logs openclaw-gateway`
- **Native mode:** `cat ~/.openclaw/gateway.log`
- Make sure port 18789 is free

### Model download is slow or fails

- Ollama downloads from `registry.ollama.ai`. If your connection is slow, try a smaller tier
- Resume a failed download: just run `ollama pull <model>` again — it resumes where it left off
- Check disk space: models need 3-35GB depending on tier

### GPU not detected

- Install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) for Docker GPU access
- Run `nvidia-smi` to verify your GPU driver is working
- The installer falls back to CPU mode automatically if no GPU is found

### "Port is already in use"

- Another Ollama or OpenClaw instance may be running
- Stop it first: `docker compose down` or `pkill -f 'openclaw serve'`
- Or use different ports by editing `docker-compose.yml`

### Browser doesn't open automatically

- Navigate manually to `http://localhost:18789`

### Model runs out of VRAM

- Switch to a smaller tier: re-run the installer with `--tier <N>`
- Or use `--cpu` for CPU-only inference (slower but always works)

---

## Lore

*From the Ancient Lore Repositories of Shibatopia:*

> When the SS VIRGIL tore through the Rakiya and crash-landed on Shibanu,
> everything changed. While Ryoshi rose as the hero of decentralization,
> The Librarian chose a quieter path — keeper of knowledge, guardian of
> code. Every bug squashed is a Shadowcat banished. Every clean architecture
> is a ward against FUD. Every well-tested function is a shield for the pack.

Based on the [Shiba Eternity](https://shiba-eternity.fandom.com/wiki/Shiba_Eternity_Wiki)
universe by Shytoshi Kusama and PlaySide Studios.

---

## License

MIT
