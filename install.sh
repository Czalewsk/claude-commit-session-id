#!/bin/bash
# install.sh
# Installs the claude-session-commit hook for Claude Code

set -euo pipefail

HOOK_DIR="$HOME/.claude/hooks"
HOOK_SCRIPT="inject-session-id.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "Installing claude-session-commit..."

# Check for jq
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed."
  echo "Install it with:"
  echo "  macOS:  brew install jq"
  echo "  Ubuntu: sudo apt install jq"
  echo "  Arch:   sudo pacman -S jq"
  exit 1
fi

# Create hooks directory
mkdir -p "$HOOK_DIR"

# Copy the hook script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/$HOOK_SCRIPT" "$HOOK_DIR/$HOOK_SCRIPT"
chmod +x "$HOOK_DIR/$HOOK_SCRIPT"
echo "Copied hook script to $HOOK_DIR/$HOOK_SCRIPT"

# Configure settings.json
HOOK_ENTRY='{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "~/.claude/hooks/inject-session-id.sh"
    }
  ]
}'

if [ -f "$SETTINGS_FILE" ]; then
  # Check if already installed
  if jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command | test("inject-session-id"))' "$SETTINGS_FILE" > /dev/null 2>&1; then
    echo "Hook already configured in $SETTINGS_FILE — skipping."
  else
    # Merge into existing settings
    UPDATED=$(jq --argjson entry "$HOOK_ENTRY" '
      .hooks //= {} |
      .hooks.PostToolUse //= [] |
      .hooks.PostToolUse += [$entry]
    ' "$SETTINGS_FILE")
    echo "$UPDATED" > "$SETTINGS_FILE"
    echo "Added hook configuration to $SETTINGS_FILE"
  fi
else
  # Create new settings file
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  jq -n --argjson entry "$HOOK_ENTRY" '{
    hooks: {
      PostToolUse: [$entry]
    }
  }' > "$SETTINGS_FILE"
  echo "Created $SETTINGS_FILE with hook configuration"
fi

echo ""
echo "Installation complete!"
echo ""
echo "The hook will now automatically add Claude-Session-Id trailers"
echo "to any commit made through Claude Code."
echo ""
echo "To resume a session from a commit, run:"
echo '  claude --resume $(git log -1 --format=%B | grep "Claude-Session-Id:" | awk '"'"'{print $2}'"'"')'
echo ""
echo "Tip: add the claude-resume alias to your shell — see README.md for details."
