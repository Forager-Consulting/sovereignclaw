#!/usr/bin/env bash
# bootstrap.sh — runs inside the sovereignclaw WSL2 distro as root (called by install.ps1).
# Narrated by Lord Clawsworth. Errors and credentials are always plain language.
set -euo pipefail

REPO_URL='https://github.com/Forager-Consulting/sovereignclaw.git'
PERSONA_DIR='/opt/sovereignclaw/persona'
WORKSPACE='/home/node/.openclaw/workspace'

step() { echo; echo "==> $*"; }
ok()   { echo "    OK: $*"; }
die()  { echo; echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# systemd is required by k3s
# ---------------------------------------------------------------------------

if ! systemctl is-system-running --wait 2>/dev/null | grep -qE '^(running|degraded)'; then
    die "systemd is not running as PID 1. Try: wsl --shutdown, wait 10s, then re-run install.ps1"
fi

# ---------------------------------------------------------------------------
# GPU detection — pick the first GPU that is not driving a display
# ---------------------------------------------------------------------------

detect_inference_gpu() {
    local gpus chosen=""
    gpus=$(nvidia-smi --query-gpu=index,name,memory.total,display_active --format=csv,noheader 2>/dev/null || true)
    [[ -n "$gpus" ]] || { echo "ERROR: nvidia-smi found no GPUs inside WSL2. Check your NVIDIA driver." >&2; exit 1; }
    echo "    GPUs found:" >&2
    echo "$gpus" | sed 's/^/      /' >&2
    while IFS=',' read -r idx _name _vram display; do
        idx=$(echo "$idx" | xargs); display=$(echo "$display" | xargs)
        if [[ "$display" == "Disabled" && -z "$chosen" ]]; then chosen="$idx"; fi
    done <<< "$gpus"
    if [[ -z "$chosen" ]]; then
        echo "    WARNING: every GPU drives a display, so GPU 0 will be shared with your desktop." >&2
        chosen="0"
    fi
    echo "$chosen"
}

step 'Surveying the royal treasury (GPUs)'
INFERENCE_GPU=$(detect_inference_gpu)
ok "GPU $INFERENCE_GPU is appointed to the Crown's thinking. The others may keep painting your screens, Majesty."

# ---------------------------------------------------------------------------
# Base packages
# ---------------------------------------------------------------------------

step 'Stocking the larder (base packages)'
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q curl git ca-certificates gnupg jq apache2-utils   # apache2-utils: htpasswd
ok 'The larder is full.'

# ---------------------------------------------------------------------------
# NVIDIA container toolkit — must be installed BEFORE k3s: k3s detects
# nvidia-container-runtime at startup and registers the `nvidia` runtime
# and RuntimeClass itself. No containerd config editing needed.
# ---------------------------------------------------------------------------

step 'Forging the GPU gauntlets (NVIDIA container toolkit)'
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -sL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -q
apt-get install -y -q nvidia-container-toolkit
ok 'Gauntlets forged.'

# ---------------------------------------------------------------------------
# k3s — single node, secrets encrypted at rest, no Traefik
# ---------------------------------------------------------------------------

step 'Raising the castle walls (k3s)'
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="\
    --secrets-encryption \
    --disable=traefik \
    --data-dir=/var/lib/k3s" sh -

# /run is a tmpfs, so after every distro start flannel must rewrite
# /run/flannel/subnet.env before pod sandboxes can be created.
mkdir -p /etc/systemd/system/k3s.service.d
cat > /etc/systemd/system/k3s.service.d/flannel-wait.conf <<'DROPIN'
[Service]
ExecStartPost=/bin/bash -c 'for i in $(seq 60); do [ -f /run/flannel/subnet.env ] && exit 0; sleep 1; done; exit 1'
DROPIN
systemctl daemon-reload

timeout 120 bash -c 'until kubectl get nodes 2>/dev/null | grep -q " Ready"; do sleep 3; done' \
    || die "k3s did not become Ready within 120s. Check: journalctl -u k3s"

mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chmod 600 ~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc

kubectl get runtimeclass nvidia >/dev/null 2>&1 \
    || die "k3s did not register the nvidia RuntimeClass. Is nvidia-container-runtime installed?"
ok 'The walls stand, Majesty. Not a single cloud may pass.'

# ---------------------------------------------------------------------------
# GPU wiring for Ollama (lives outside git: it is specific to this machine)
# ---------------------------------------------------------------------------

step 'Assigning the royal oracle its seat'
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label node "$NODE" sovereignclaw.ai/gpu-inference=true --overwrite >/dev/null
kubectl create namespace ollama --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create configmap sovereignclaw-gpu -n ollama \
    --from-literal=inference-gpu="$INFERENCE_GPU" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "The oracle (Ollama) shall sit at GPU $INFERENCE_GPU, and nowhere else."

# ---------------------------------------------------------------------------
# Helm + Argo CD
# ---------------------------------------------------------------------------

step 'Summoning the master builder (Helm)'
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
ok "$(helm version --short) has arrived."

step 'Appointing the royal steward (Argo CD)'
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update >/dev/null
helm install argocd argo/argo-cd \
    --namespace argocd \
    --version 7.4.4 \
    --set server.service.type=ClusterIP \
    --set configs.params."server\.insecure"=false \
    --wait --timeout 5m
ok 'The steward keeps the castle exactly as the plans decree.'

ARGOCD_PASSWORD=$(dd if=/dev/urandom bs=512 count=1 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 32)
ARGOCD_PASSWORD_HASH=$(htpasswd -bnBC 10 "" "$ARGOCD_PASSWORD" | tr -d ':\n')
kubectl -n argocd patch secret argocd-secret --type=merge \
    -p "{\"stringData\":{\"admin.password\":\"${ARGOCD_PASSWORD_HASH}\",\"admin.passwordMtime\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}}" >/dev/null

# ---------------------------------------------------------------------------
# OpenClaw gateway token
# ---------------------------------------------------------------------------

step 'Cutting the key to the throne room (gateway token)'
kubectl create namespace openclaw --dry-run=client -o yaml | kubectl apply -f - >/dev/null
OPENCLAW_TOKEN=$(dd if=/dev/urandom bs=512 count=1 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 48)
kubectl create secret generic openclaw-gateway-token -n openclaw \
    --from-literal=token="$OPENCLAW_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
unset OPENCLAW_TOKEN
ok 'One key, locked in the vault (an encrypted Kubernetes Secret).'

# ---------------------------------------------------------------------------
# Argo CD root Application — reconciles clusters/local/ from the public repo
# ---------------------------------------------------------------------------

step 'Handing the steward the royal plans'
kubectl apply -f - >/dev/null <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sovereignclaw
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: main
    path: clusters/local
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
ok 'The steward is building the court (Ollama + OpenClaw).'

# ---------------------------------------------------------------------------
# OpenClaw runtime env — the chart hard-codes container env, so patch it in.
# ignoreDifferences in openclaw.yaml keeps Argo CD from reverting this.
# OLLAMA_API_KEY is a dummy: OpenClaw only registers the Ollama provider
# when the variable is non-empty.
# ---------------------------------------------------------------------------

step 'Admitting the Grand Vizier to court (OpenClaw)'
timeout 300 bash -c 'until kubectl get deployment openclaw -n openclaw >/dev/null 2>&1; do sleep 5; done' \
    || die "Argo CD did not create the OpenClaw Deployment within 5 minutes. Check: kubectl get applications -n argocd"
kubectl patch deployment openclaw -n openclaw --type=strategic -p '{
  "spec": {"template": {"spec": {"containers": [{
    "name": "main",
    "env": [
      {"name": "OPENCLAW_GATEWAY_TOKEN", "valueFrom": {"secretKeyRef": {"name": "openclaw-gateway-token", "key": "token"}}},
      {"name": "OLLAMA_API_KEY", "value": "ollama"}
    ]
  }]}}}
}' >/dev/null
kubectl rollout status deployment/openclaw -n openclaw --timeout=600s >/dev/null \
    || die "OpenClaw did not become ready within 10 minutes. Check: kubectl get pods -n openclaw"
ok 'He has arrived, and is adjusting his crown.'

# ---------------------------------------------------------------------------
# Persona — written once, at install, over OpenClaw's stock templates.
# After this the files belong to the user and the agent to evolve.
# ---------------------------------------------------------------------------

step 'Robing Lord Clawsworth'
for f in IDENTITY.md SOUL.md BOOTSTRAP.md; do
    kubectl exec -i -n openclaw deploy/openclaw -c main -- \
        sh -c "mkdir -p '$WORKSPACE' && cat > '$WORKSPACE/$f'" < "$PERSONA_DIR/$f" \
        || die "could not write $f into the OpenClaw workspace"
done
ok 'Robed, briefed, and insufferably pleased with himself.'

# ---------------------------------------------------------------------------
# Done — print the Argo CD password ONCE, in plain language
# ---------------------------------------------------------------------------

cat <<DONE

============================================================
  The realm is secure, Your Majesty.
============================================================

  ARGO CD CREDENTIALS — save to your password manager NOW.
  This is the only time the password is displayed.

    Username:  admin
    Password:  ${ARGOCD_PASSWORD}

  OpenClaw gateway token (paste into the UI's password field):
    wsl -d sovereignclaw -- bash -c "kubectl get secret openclaw-gateway-token -n openclaw -o jsonpath='{.data.token}' | base64 -d"

============================================================
DONE

unset ARGOCD_PASSWORD ARGOCD_PASSWORD_HASH
