#!/usr/bin/env bash
# health-inner.sh - in-distro checks for SovereignClaw. OBSERVE ONLY: never writes state.
# Streamed in over stdin by test/health.ps1. Keep this file ASCII-only.
set -uo pipefail

PASS=0; FAIL=0; WARN=0
pass() { echo "  [PASS] $*"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }
warn() { echo "  [WARN] $*"; WARN=$((WARN + 1)); }
section() { echo; echo "-- $*"; }

# --- Castle walls -----------------------------------------------------------
section "k3s"
systemctl is-active --quiet k3s && pass "k3s service is active" || fail "k3s is not running -> systemctl status k3s"
[[ "$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | head -1)" == "Ready" ]] \
    && pass "node is Ready" || fail "node is not Ready -> kubectl describe node"
kubectl get runtimeclass nvidia >/dev/null 2>&1 \
    && pass "nvidia RuntimeClass registered by k3s" || fail "nvidia RuntimeClass missing -> is nvidia-container-toolkit installed?"

# --- GPU --------------------------------------------------------------------
section "GPU"
DETECTED=""
while IFS=',' read -r idx display; do
    idx=$(echo "$idx" | xargs); display=$(echo "$display" | xargs)
    [[ "$display" == "Disabled" && -z "$DETECTED" ]] && DETECTED="$idx"
done < <(nvidia-smi --query-gpu=index,display_active --format=csv,noheader 2>/dev/null)
[[ -z "$DETECTED" ]] && { warn "every GPU drives a display; inference shares GPU 0 with the desktop"; DETECTED="0"; }
PINNED=$(kubectl get configmap sovereignclaw-gpu -n ollama -o jsonpath='{.data.inference-gpu}' 2>/dev/null)
[[ "$PINNED" == "$DETECTED" ]] \
    && pass "Ollama pinned to GPU $PINNED (the non-display GPU)" \
    || fail "Ollama pinned to GPU '${PINNED:-none}' but the non-display GPU is $DETECTED -> re-run install or fix ConfigMap ollama/sovereignclaw-gpu"

# --- Argo CD ----------------------------------------------------------------
section "Argo CD"
SYNC=$(kubectl get application sovereignclaw -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
case "$SYNC" in
    Synced) pass "root Application 'sovereignclaw' is Synced" ;;
    "")     fail "root Application not found -> kubectl get applications -n argocd" ;;
    *)      warn "root Application is $SYNC (may still be reconciling)" ;;
esac

# --- Ollama -----------------------------------------------------------------
section "Ollama"
[[ "$(kubectl get pods -n ollama -l app=ollama --no-headers 2>/dev/null | awk '{print $3}' | head -1)" == "Running" ]] \
    && pass "Ollama pod is Running" || fail "Ollama pod not Running -> kubectl get pods -n ollama"
CTX=$(kubectl get deploy ollama -n ollama -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="OLLAMA_CONTEXT_LENGTH")].value}' 2>/dev/null)
[[ "${CTX:-0}" -ge 32768 ]] \
    && pass "context length $CTX (OpenClaw's ~16K prompt fits)" \
    || fail "context length '${CTX:-default}' is too small; OpenClaw prompts will be silently truncated"
OLLAMA_URL="http://$(kubectl get svc ollama -n ollama -o jsonpath='{.spec.clusterIP}' 2>/dev/null):11434"
if curl -sf "$OLLAMA_URL/api/tags" --max-time 5 | grep -q '"qwen2.5:7b"'; then
    pass "qwen2.5:7b is pulled"
else
    fail "qwen2.5:7b not available yet -> kubectl get jobs -n ollama (the pull runs after sync)"
fi

# --- OpenClaw ---------------------------------------------------------------
section "OpenClaw"
[[ "$(kubectl get pods -n openclaw --no-headers 2>/dev/null | awk '{print $2" "$3}' | head -1)" == "2/2 Running" ]] \
    && pass "OpenClaw pod is 2/2 Running" || fail "OpenClaw pod not ready -> kubectl get pods -n openclaw"
kubectl get secret openclaw-gateway-token -n openclaw >/dev/null 2>&1 \
    && pass "gateway token Secret exists" || fail "gateway token Secret missing"
kubectl exec -n openclaw deploy/openclaw -c main -- grep -q "Sir Clawsalot" /home/node/.openclaw/workspace/IDENTITY.md 2>/dev/null \
    && pass "Sir Clawsalot is in residence (IDENTITY.md)" \
    || warn "IDENTITY.md does not name Sir Clawsalot (fine if Their Majesty renamed him)"

# --- Inference round trip ---------------------------------------------------
section "Inference"
RESPONSE=$(curl -sf "$OLLAMA_URL/api/generate" --max-time 120 \
    -d '{"model":"qwen2.5:7b","prompt":"Reply with exactly the word PONG and nothing else.","stream":false}' 2>/dev/null)
if echo "$RESPONSE" | grep -qi "PONG"; then
    pass "inference round trip answered"
else
    fail "no answer from qwen2.5:7b -> kubectl logs -n ollama deploy/ollama"
fi
PS_LINE=$(kubectl exec -n ollama deploy/ollama -- ollama ps 2>/dev/null | grep qwen2.5)
if echo "$PS_LINE" | grep -q "100% GPU"; then
    pass "model loaded 100% on GPU"
else
    fail "model is not fully on GPU: ${PS_LINE:-not loaded} (CPU spill slows everything and loads your desktop)"
fi

# --- Summary ----------------------------------------------------------------
echo
echo "==================================================="
echo "  PASSED: $PASS   WARNINGS: $WARN   FAILED: $FAIL"
echo "==================================================="
[[ "$FAIL" -eq 0 ]]
