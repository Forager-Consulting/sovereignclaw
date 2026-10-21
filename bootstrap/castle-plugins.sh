#!/usr/bin/env bash
# Names the castle's own plugins in OpenClaw's plugins.allow, so no unknown plugin
# dropped into the extensions folder can load by itself. plugins.allow covers bundled
# plugins too, so every plugin the castle uses must be listed.
#
# This only ADDS the castle's ids; it never replaces the list. Add-ons add their own
# ids the same way at their install, and the castle never names them. (It is written
# into the live config, not the Helm values: the config merge replaces arrays on every
# restart, which would wipe the add-ons' entries.)
#
# Run at install by bootstrap.sh; safe to re-run. Takes effect after a gateway restart.
set -euo pipefail
CASTLE_PLUGINS='["browser","canvas","device-pair","file-transfer","memory-core","openai","phone-control","talk-voice"]'

kubectl exec -n openclaw deploy/openclaw -c main -- node -e '
const fs = require("fs"), f = "/home/node/.openclaw/openclaw.json";
const c = JSON.parse(fs.readFileSync(f, "utf8"));
const add = JSON.parse(process.argv[1]);
c.plugins = c.plugins || {};
const have = c.plugins.allow || [];
const next = [...new Set([...have, ...add])];
if (next.length === have.length) { console.log("plugins.allow already names the castle plugins."); process.exit(0); }
fs.copyFileSync(f, f + ".bak-before-castle-plugins");
c.plugins.allow = next;
fs.writeFileSync(f, JSON.stringify(c, null, 2));
console.log("plugins.allow:", next.join(", "));
' "$CASTLE_PLUGINS" </dev/null
