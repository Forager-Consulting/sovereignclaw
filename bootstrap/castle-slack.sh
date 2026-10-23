#!/usr/bin/env bash
# Optional: lets you message Sir Clawsalot from Slack. Socket Mode: the castle opens an
# outbound connection to Slack, so nothing on this PC is reachable from the internet.
# What you type to him, and what he answers, passes through Slack; the model and
# everything else stay local.
#
# Before running: create the Slack app from bootstrap/slack-manifest.json
# (api.slack.com/apps > Create New App > From a manifest), then
#   Basic Information > App-Level Tokens > Generate (scope connections:write) -> xapp-... token
#   Install App > Install to Workspace                                        -> xoxb-... token
#
# Direct messages only, and only from people you approve (dmPolicy "pairing": DM the bot,
# it answers with a code, then run: openclaw pairing approve slack <code>). Channels are off.
# Tokens are read with a hidden prompt into OpenClaw's .env (mode 600), never printed.
# Safe to re-run; --rotate asks for new tokens.
#
# usage (inside the castle distro): bootstrap/castle-slack.sh [--rotate]
set -euo pipefail
SLACK_PLUGIN='@openclaw/slack@2026.5.22'   # must match the gateway's OpenClaw version
ROTATE="${1:-}"
oc() { kubectl exec -n openclaw deploy/openclaw -c main -- "$@" </dev/null; }

# npm's default cache (~/.npm) is not writable in the pod, so cache and logs go to /tmp.
if ! oc test -d /home/node/.openclaw/npm/node_modules/@openclaw/slack; then
  oc sh -c "cd /tmp && npm_config_cache=/tmp/npm-cache npm_config_logs_dir=/tmp/npm-logs openclaw plugins install '$SLACK_PLUGIN' 2>&1 | grep -v '^npm notice' | tail -2"
  oc test -d /home/node/.openclaw/npm/node_modules/@openclaw/slack || { echo "Slack plugin did not install." >&2; exit 1; }
fi

HAVE="$(oc sh -c 'cut -d= -f1 /home/node/.openclaw/.env 2>/dev/null')"
for pair in SLACK_APP_TOKEN:xapp- SLACK_BOT_TOKEN:xoxb-; do
  NAME="${pair%%:*}"; PREFIX="${pair#*:}"
  if [ "$ROTATE" != "--rotate" ] && grep -qx "$NAME" <<<"$HAVE"; then echo "$NAME already set."; continue; fi
  read -rsp "$NAME ($PREFIX..., input hidden): " VAL </dev/tty; echo
  case "$VAL" in "$PREFIX"*) ;; *) echo "That is not a $PREFIX token; nothing changed." >&2; exit 1;; esac
  printf '%s\n' "$VAL" | kubectl exec -i -n openclaw deploy/openclaw -c main -- sh -c '
    f=/home/node/.openclaw/.env; umask 077; touch "$f"; read -r u
    grep -v "^$0=" "$f" > "$f.tmp" || true
    printf "%s=\"%s\"\n" "$0" "$u" >> "$f.tmp"; mv "$f.tmp" "$f"; chmod 600 "$f"' "$NAME"
  unset VAL
  echo "  $NAME saved."
done

# Written into the live config, like castle-plugins.sh: plugins.allow is an array, which the
# Helm config merge would replace on every restart. The tokens come from the env above.
oc node -e '
const fs = require("fs"), f = "/home/node/.openclaw/openclaw.json";
const c = JSON.parse(fs.readFileSync(f, "utf8"));
fs.copyFileSync(f, f + ".bak-before-castle-slack");
c.plugins = c.plugins || {};
c.plugins.allow = [...new Set([...(c.plugins.allow || []), "slack"])];
c.channels = c.channels || {};
c.channels.slack = Object.assign(c.channels.slack || {}, {
  enabled: true, mode: "socket", dmPolicy: "pairing", groupPolicy: "disabled", unfurlLinks: false
});
fs.writeFileSync(f, JSON.stringify(c, null, 2));
console.log("plugins.allow:", c.plugins.allow.join(", "));
console.log("channels.slack:", JSON.stringify(c.channels.slack));
'
kubectl rollout restart deployment/openclaw -n openclaw >/dev/null
kubectl rollout status deployment/openclaw -n openclaw --timeout=600s </dev/null | tail -1
sleep 20
oc openclaw channels status --probe 2>&1 | grep -i -A3 slack || true
echo "Now DM Sir Clawsalot in Slack. He replies with a pairing code; approve it with:"
echo "  kubectl exec -n openclaw deploy/openclaw -c main -- openclaw pairing approve slack <code>"
