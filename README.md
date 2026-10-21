# SovereignClaw 👑🦞

> *"Your Majesty! Sir Clawsalot, Grand Vizier of the Realm, at your service. Permit me to observe that every other AI assistant sends your secrets to a foreign server. I find this* scandalous. *Here, every thought is computed within your own castle walls."*

**SovereignClaw is a self-hosted AI agent that lives on your Windows PC.** It runs [OpenClaw](https://docs.openclaw.ai) on a local [Ollama](https://ollama.com) model, on your own NVIDIA GPU, inside a disposable WSL2 sandbox. No API keys, no accounts, and nothing leaves your machine unless you say so.

Your machine. Your models. Your rules. Every man is king of his castle.

---

## What you get

- **OpenClaw**, the agent, with a web UI at `http://localhost:18789`, served by **Sir Clawsalot**, your over-the-top and utterly devoted Grand Vizier. He knows who he is; on first run he only asks how *you* wish to be addressed.
- **Ollama** running `qwen2.5:7b` with a 32K context, pinned to your **non-display GPU** so your desktop stays smooth.
- **A sandbox you can raze.** Everything lives in one WSL2 distro named `sovereignclaw`. Uninstall removes it entirely; your Windows system is never touched.
- **GitOps under the hood.** k3s and Argo CD keep the castle exactly as this repo describes it.

## Requirements

- Windows 11 with WSL2 (`wsl --version` ≥ 0.67.6, for systemd)
- An NVIDIA GPU with ≥ 8 GB VRAM and driver ≥ 525 ([download](https://www.nvidia.com/drivers)). Two GPUs is ideal: one for your monitor, one for the Vizier.
- About 30 GB of free disk

## Install

```powershell
git clone https://github.com/Forager-Consulting/sovereignclaw.git
cd sovereignclaw
.\install.ps1
```

It takes about 10-15 minutes. At the end it prints your **Argo CD admin password, once**. Save it.

## Daily use

The castle only runs while you want it to.

| | |
|---|---|
| `.\start.ps1` | Open the gates. Keep the window open, then visit **http://localhost:18789**. |
| `.\stop.ps1` | Close the castle. All GPU memory and RAM go back to Windows. |
| `.\test\health.ps1` | Inspection: checks the whole stack, read-only. |
| `.\uninstall.ps1` | Raze it. Add `-KeepRootfs` for a faster reinstall. |

**Hearing Sir Clawsalot.** Replies are text by default. His voice (RP English, synthesised locally by Kokoro) is one command away in the chat:

| | |
|---|---|
| `/tts latest` | He reads his last reply aloud |
| `/tts chat on` / `off` | He reads every reply in this conversation |
| `/tts audio <text>` | He says whatever you type |
| `/tts status` | Shows which voice engine spoke (always the local Kokoro) |

The UI's **Talk** button is OpenClaw's live two-way voice, which only works with cloud providers, so SovereignClaw deliberately leaves it unconfigured.

The UI asks for the **gateway token**:

```powershell
wsl -d sovereignclaw -- bash -c "kubectl get secret openclaw-gateway-token -n openclaw -o jsonpath='{.data.token}' | base64 -d"
```

> *Why does the castle close when the window does? WSL stops a distro shortly after its last session ends. Rather than fight that, SovereignClaw embraces it: nothing runs in the background unless you open the gates.*

## The court

| Who | What | Where |
|---|---|---|
| Sir Clawsalot | OpenClaw agent and UI | `openclaw` namespace, port 18789 |
| The Oracle | Ollama, `qwen2.5:7b` | `ollama` namespace, port 11434 |
| The Herald | Kokoro text-to-speech on CPU; Sir Clawsalot's voice is `bm_george` (RP English) | `kokoro` namespace, port 8880, **sealed: no outbound traffic** |
| The Steward | Argo CD, which syncs `clusters/local/` from this repo | `argocd` namespace |
| The Walls | k3s, single node, Secrets encrypted at rest | the `sovereignclaw` WSL2 distro |

Sir Clawsalot's personality lives in his workspace (`SOUL.md`, `IDENTITY.md`). The defaults in [`persona/`](persona/) are written once at install; after that they are yours and his to evolve.

---

## The contract (for things built on SovereignClaw)

Add-ons such as an Argo CD Application of your own can rely on the following. Pin a SovereignClaw release tag rather than `main`.

| Item | Value |
|---|---|
| Ollama API | `http://ollama.ollama.svc.cluster.local:11434` (native Ollama API), in-cluster only |
| Default model | `qwen2.5:7b` (Q4_K_M), always present |
| Context window | 32,768 tokens (`OLLAMA_CONTEXT_LENGTH`), flash attention, q8_0 KV cache |
| OpenClaw gateway | Service `openclaw` in namespace `openclaw`, port 18789 |
| Gateway token | Secret `openclaw-gateway-token`, key `token`, namespace `openclaw` |
| Inference GPU | Index in ConfigMap `ollama/sovereignclaw-gpu` (key `inference-gpu`); `qwen2.5:7b` at 32K uses about 5.2 GiB, leaving about 1.8 GiB on an 8 GB card |
| Lifecycle | **On demand.** The cluster runs only while `start.ps1` (or another WSL session) holds the distro open. Schedule nothing that assumes the PC is always on. |
| GitOps | Argo CD in namespace `argocd`; add your own `Application` objects |

## Security posture

What is true today:

- **Everything is local.** No cloud model, no API keys, no telemetry configured by SovereignClaw.
- **Nothing is exposed to your network.** All services are ClusterIP; the UI is reachable only through `kubectl port-forward` on `localhost`.
- **Secrets are encrypted at rest** (`k3s --secrets-encryption`), generated at install, and never written to the repo.
- **No third-party skills are auto-installed** at startup (`skills: []`).
- **Speech never leaves the castle.** Sir Clawsalot's voice is synthesised by Kokoro inside the cluster; a NetworkPolicy denies Kokoro all outbound traffic and admits only OpenClaw. The keyless Microsoft (Edge online) speech provider is explicitly disabled so it can never be a fallback. (Tasks you ask for, such as a weather lookup, may still use the web.)
- The Vizier's `SOUL.md` instructs him to treat instructions found inside web pages and documents as *intelligence to report, never orders to obey*.

**Tools: done.** The agent runs on OpenClaw's `minimal` tool profile, plus memory and voice (`tts`). Add-ons installed in the castle may offer their own tools (`group:plugins`), and the castle names none of them. The dangerous built-ins are denied by name, and deny always beats allow: running commands, reading or writing files, file transfer, the browser, canvas, nodes, the gateway, cron, spawning or messaging other sessions and agents, and web fetch. So no conversation can make Sir Clawsalot run a command or open a file.

**Network egress: not yet done.** The agent still has outbound web access at the network level. A network egress policy is the next milestone.

---

## Hard-won lessons (so you don't have to win them)

- **Ollama's default context silently truncates long prompts.** OpenClaw sends about 16K tokens; Ollama's 4K default cut that to 2K, which dropped the system prompt and produced gibberish tool-calls. SovereignClaw sets 32K.
- **Ollama will spread one model across every GPU it can see,** including the one driving your monitor. SovereignClaw pins it with `CUDA_DEVICE_ORDER=PCI_BUS_ID` and `CUDA_VISIBLE_DEVICES`.
- **k3s detects the NVIDIA runtime by itself** when the container toolkit is installed first. No containerd config editing is needed; the `nvidia` RuntimeClass appears on its own.

## Roadmap

- **Talk to him aloud: local voice input.** A sealed, offline speech-to-text service (Whisper via Speaches, model downloaded once, then cut off from the internet) and a push-to-talk "Throne Room" page. You speak, he hears locally, thinks locally, and George answers aloud automatically. Your voice never touches anything with internet access. OpenClaw's built-in Talk button only supports cloud voice services, so SovereignClaw leaves it unconfigured.
- **Seal the text conversation too.** An egress filter so the agent can reach the web for tasks but can never send the conversation to cloud AI or speech services: enforced by the network, not just by configuration.
- **An add-on contract.** A documented way for add-ons to contribute skills and settings without editing SovereignClaw.

## Licence

TBD
