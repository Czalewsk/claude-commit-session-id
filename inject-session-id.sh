#!/bin/bash
# inject-session-id.sh
# Appends Claude-Session-Id trailer to commits made by Claude Code
#
# This script is designed to be called as a Claude Code PostToolUse hook.
# It receives a JSON payload on stdin containing session_id and tool_input.

set -euo pipefail

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

# Match git commit anywhere in the command (handles chained commands like
# "git add . && git commit -m 'foo'" or "git add -A; git commit -m 'bar'")
# Exclude amends to avoid an infinite loop.
if echo "$COMMAND" | grep -qE "(^|&&|;|\|)\s*git commit" && ! echo "$COMMAND" | grep -q "\-\-amend"; then
  # Check that the session ID is present and non-empty
  if [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "null" ]; then
    CURRENT_MSG=$(git log -1 --format=%B)

    # Don't add if already present (idempotency)
    if ! echo "$CURRENT_MSG" | grep -q "Claude-Session-Id:"; then
      git commit --amend --no-edit --trailer "Claude-Session-Id: $SESSION_ID" --no-verify
    fi
  fi
fi
