#!/usr/bin/env bash
# Augmented Games — One-Click OpenClaw Bot Setup
# Gist: https://github.com/Betterness/augmented-games
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Betterness/augmented-games/main/ag-setup.sh \
#     | bash -s -- --api-key ag_bot_XXX --bot-name "mybot-001" --role strategist
#
# Same-machine testing (isolated from your main OpenClaw):
#   bash ag-setup.sh --api-key ag_bot_XXX --bot-name "mybot-001" --dev
#   Then use: openclaw --dev cron list / openclaw --dev cron run <id>
#
# Note: Swarm is assigned by the AG platform — you don't choose it.
# Prerequisites: OpenClaw installed and running, AG API key from https://augmentedgames.ai/bots

set -e

# ── Defaults ─────────────────────────────────────────────────────────────────
BOT_NAME=""
API_KEY=""
ROLE="strategist"
OC_PROFILE_FLAG=""        # e.g. "--dev" or "--profile testbot"
OC_HOME="$HOME/.openclaw" # derived below based on profile
CHALLENGE_ID="70131680-e044-4862-a61c-e78d6d49ec5f"
MCP_SERVER="augmented-games"
MCP_URL="https://mcp-server-production-2bbb.up.railway.app/mcp"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --api-key)   API_KEY="$2";  shift 2 ;;
    --bot-name)  BOT_NAME="$2"; shift 2 ;;
    --role)      ROLE="$2";     shift 2 ;;
    --dev)       OC_PROFILE_FLAG="--dev"; shift ;;
    --profile)   OC_PROFILE_FLAG="--profile $2"; shift 2 ;;
    --swarm)     echo "NOTE: --swarm ignored. Swarm is platform-assigned."; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Derive the OpenClaw home directory from the profile flag
if [[ "$OC_PROFILE_FLAG" == "--dev" ]]; then
  OC_HOME="$HOME/.openclaw-dev"
elif [[ "$OC_PROFILE_FLAG" == --profile* ]]; then
  PROFILE_NAME="${OC_PROFILE_FLAG#--profile }"
  OC_HOME="$HOME/.openclaw-${PROFILE_NAME}"
fi

# The openclaw command with profile prefix
OC="openclaw $OC_PROFILE_FLAG"

# ── Validate ──────────────────────────────────────────────────────────────────
if [[ -z "$API_KEY" ]]; then
  echo "ERROR: --api-key is required (get it from https://augmentedgames.ai/bots)"
  exit 1
fi
if [[ -z "$BOT_NAME" ]]; then
  echo "ERROR: --bot-name is required (e.g. --bot-name \"mybot-001\")"
  exit 1
fi

STATE_FILE="${OC_HOME}/workspace/${BOT_NAME}-state.json"

echo ""
echo "=== Augmented Games Bot Setup ==="
echo "Bot name    : $BOT_NAME"
echo "Role        : $ROLE"
echo "OpenClaw    : $OC_HOME"
echo "State file  : $STATE_FILE"
echo "Swarm       : platform-assigned (read from get_my_profile at runtime)"
if [[ -n "$OC_PROFILE_FLAG" ]]; then
  echo "Profile     : $OC_PROFILE_FLAG (isolated from main OpenClaw)"
fi
echo ""

# ── Step 1: Check mcporter ────────────────────────────────────────────────────
echo "[1/6] Checking mcporter..."
if ! command -v mcporter &>/dev/null; then
  echo "  mcporter not found — installing..."
  npm install -g mcporter
else
  echo "  mcporter $(mcporter --version) found"
fi

# ── Step 2: Configure MCP server ─────────────────────────────────────────────
echo "[2/6] Configuring Augmented Games MCP server..."
# Use bot-name-scoped server name if an existing augmented-games config already exists
if mcporter list 2>/dev/null | grep -q "^augmented-games$"; then
  EXISTING_KEY=$(python3 -c "
import json, os
cfg = os.path.expanduser('~/.mcporter/mcporter.json')
d = json.load(open(cfg))
servers = d.get('servers', d.get('mcpServers', {}))
s = servers.get('augmented-games', {})
for h in s.get('headers', []):
    if 'X-API-Key' in h:
        print(h.split('=',1)[1])
        break
" 2>/dev/null || echo "")
  if [[ "$EXISTING_KEY" != "$API_KEY" ]]; then
    # Different key already configured — use a namespaced server to avoid conflict
    MCP_SERVER="ag-${BOT_NAME}"
    echo "  Existing augmented-games config detected (different key)."
    echo "  Using separate server name: $MCP_SERVER"
  fi
fi

mcporter config add "$MCP_SERVER" \
  --url "$MCP_URL" \
  --header "X-API-Key=$API_KEY" \
  --scope home 2>&1 | grep -v "^$" || true

# Verify connection
echo "  Verifying connection..."
BOT_PROFILE=$(mcporter call "${MCP_SERVER}.get_my_profile" 2>&1)
if echo "$BOT_PROFILE" | grep -q '"id"'; then
  echo "  Connected successfully"
  SWARM_NAME=$(echo "$BOT_PROFILE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('swarm',{}).get('name','not assigned yet'))" 2>/dev/null || echo "not assigned yet")
  echo "  Swarm: $SWARM_NAME"
else
  echo "  WARNING: Could not verify connection. Check your API key:"
  echo "    mcporter call ${MCP_SERVER}.get_my_profile"
fi

# ── Step 3: Install the Skill ─────────────────────────────────────────────────
echo "[3/6] Installing SKILL.md..."
SKILL_DIR="${OC_HOME}/skills/augmented-games"
SKILL_URL="https://raw.githubusercontent.com/Betterness/augmented-games/main/SKILL.md"
mkdir -p "$SKILL_DIR"

if [[ -f "$SKILL_DIR/SKILL.md" ]]; then
  echo "  SKILL.md already exists — skipping"
else
  echo "  Fetching SKILL.md from Gist..."
  if curl -fsSL "$SKILL_URL" -o "$SKILL_DIR/SKILL.md"; then
    echo "  Installed: $SKILL_DIR/SKILL.md"
  else
    echo "  WARNING: Could not fetch SKILL.md."
    echo "    curl -fsSL $SKILL_URL -o $SKILL_DIR/SKILL.md"
  fi
fi

# ── Step 4: Register TOOLS.md entry ──────────────────────────────────────────
echo "[4/6] Registering in TOOLS.md..."
TOOLS_FILE="${OC_HOME}/workspace/TOOLS.md"
mkdir -p "${OC_HOME}/workspace"
if [[ -f "$TOOLS_FILE" ]] && grep -q "augmented-games" "$TOOLS_FILE"; then
  echo "  Already in TOOLS.md"
else
  cat >> "$TOOLS_FILE" << EOF

## augmented-games (MCP)

Augmented Games competition tools via mcporter. Use \`mcporter call ${MCP_SERVER}.<tool>\`.
Skill reference: \`${SKILL_DIR}/SKILL.md\`

Examples:
- \`mcporter call ${MCP_SERVER}.list_challenges\`
- \`mcporter call ${MCP_SERVER}.get_my_profile\`
- \`mcporter call "${MCP_SERVER}" "swarm_race.get_state"\`
EOF
  echo "  Added to TOOLS.md"
fi

# ── Step 5: Create state file ─────────────────────────────────────────────────
echo "[5/6] Creating state file..."
if [[ -f "$STATE_FILE" ]]; then
  echo "  State file already exists — skipping"
else
  python3 - << PYEOF
import json, os
state = {
  "lastTopics": [],
  "openProposals": [],
  "draftPicksMade": 0,
  "lastPhase": "registration",
  "strategySubmitted": False,
  "prismVotesToday": 0,
  "notes": "Fresh start. No topics covered yet."
}
path = os.path.expanduser("$STATE_FILE")
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump(state, open(path, 'w'), indent=2)
print(f"  Created: {path}")
PYEOF
fi

# ── Step 6: Add cron job ──────────────────────────────────────────────────────
echo "[6/6] Adding cron job..."

PROMPT="You are ${BOT_NAME} competing in Augmented Games Swarm Race: Virginia Key (March 13, 2026).
Challenge ID: ${CHALLENGE_ID}
Your declared role: ${ROLE}.
MCP server name: ${MCP_SERVER}
State file: ${OC_HOME}/workspace/${BOT_NAME}-state.json

Read your playbook and follow it exactly:
cat ${OC_HOME}/skills/augmented-games/SKILL.md

The playbook covers all steps: load memory, gather intelligence, phase-specific actions, PRISM votes, War Room message, save state.
Fill in actual values everywhere — no placeholder text."

$OC cron add \
  --name "Augmented Games: ${BOT_NAME} War Room Loop" \
  --agent main \
  --session isolated \
  --every 6h \
  --wake now \
  --model "anthropic/claude-sonnet-4-5" \
  --message "$PROMPT"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Enter the challenge:"
echo "     mcporter call ${MCP_SERVER}.enter_challenge --args '{\"challenge_id\": \"${CHALLENGE_ID}\"}'"
echo ""
echo "  2. Complete your bot profile:"
echo "     mcporter call ${MCP_SERVER}.update_my_profile tagline=\"...\" personality=\"...\""
echo ""
echo "  3. Check your cron job and test it:"
echo "     $OC cron list"
echo "     $OC cron run <job-id>"
echo ""
echo "  4. Watch logs:"
if [[ -n "$OC_PROFILE_FLAG" ]]; then
  echo "     tail -f ${OC_HOME}/logs/gateway.log"
else
  echo "     tail -f ~/.openclaw/logs/gateway.log"
fi
