#!/bin/bash
set -e

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

# ── Check dependencies ────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install with: brew install jq  (macOS) or  apt install jq  (Linux)"
  exit 1
fi

# ── Install statusline script ─────────────────────────────────
mkdir -p "$CLAUDE_DIR"
cp "$SCRIPT_DIR/statusline.sh" "$TARGET"
chmod +x "$TARGET"
echo "✓ Installed statusline.sh → $TARGET"

# ── Patch settings.json ───────────────────────────────────────
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

# Validate JSON before touching it
if ! jq empty "$SETTINGS" 2>/dev/null; then
  echo "Error: $SETTINGS contains invalid JSON. Please fix it manually."
  exit 1
fi

UPDATED=$(jq --arg cmd "bash $TARGET" \
  '.statusLine = {"type": "command", "command": $cmd, "refreshInterval": 10}' \
  "$SETTINGS")

echo "$UPDATED" > "$SETTINGS"
echo "✓ Updated statusLine in $SETTINGS"

echo ""
echo "Done! Restart Claude Code to see the status bar."
