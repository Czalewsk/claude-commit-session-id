# claude-session-commit

Automatically embed Claude Code session IDs into your git commit messages, so you can resume any conversation directly from your git history.

Ever finished a coding session with Claude Code, come back days later to a commit, and wished you could jump straight back into the conversation that produced it? This hook solves that. It appends a `Claude-Session-Id` trailer to every commit Claude makes, turning your git log into a map of your AI conversations.

## How it works

`claude-session-commit` is a [Claude Code hook](https://code.claude.com/docs/en/hooks) that listens for `git commit` commands. When Claude Code runs a commit, the hook:

1. Reads the JSON payload from stdin (which includes `session_id`)
2. Checks whether the Bash command was a `git commit`
3. Amends the commit to append a `Claude-Session-Id` trailer

Your commits end up looking like this:

```
feat: add user authentication with JWT tokens

Implement login/logout endpoints, token refresh middleware,
and protected route guards.

Co-Authored-By: Claude <noreply@anthropic.com>
Claude-Session-Id: eb5b0174-0555-4601-804e-672d68069c89
```

Later, you can resume that exact conversation:

```bash
claude --resume eb5b0174-0555-4601-804e-672d68069c89
```

## Requirements

- [Claude Code](https://code.claude.com) installed and configured
- `jq` (JSON processor) — available on most systems, or install via your package manager
- `git` 2.0+
- Bash-compatible shell

## Installation

### Quick install

```bash
# Clone the repository
git clone https://github.com/yourname/claude-session-commit.git
cd claude-session-commit

# Run the installer
./install.sh
```

The installer will:
- Copy the hook script to `~/.claude/hooks/inject-session-id.sh`
- Add the hook configuration to your `~/.claude/settings.json` (user-wide)
- Make the script executable

### Manual install

**1. Copy the hook script**

Place `inject-session-id.sh` somewhere permanent:

```bash
mkdir -p ~/.claude/hooks
cp inject-session-id.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/inject-session-id.sh
```

**2. Configure Claude Code**

Add the hook to your settings file. You have three options for where:

| File | Scope |
|------|-------|
| `~/.claude/settings.json` | All projects (recommended) |
| `.claude/settings.json` | Single project (version-controlled) |
| `.claude/settings.local.json` | Single project (git-ignored) |

Add or merge the following into your chosen settings file:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/inject-session-id.sh"
          }
        ]
      }
    ]
  }
}
```

If you already have other `PostToolUse` hooks, add the new entry to the existing array — don't replace it.

## The hook script

```bash
#!/bin/bash
# inject-session-id.sh
# Appends Claude-Session-Id trailer to commits made by Claude Code

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
```

## Usage

Once installed, the hook works automatically. Just use Claude Code as you normally would — ask it to commit, and the session ID gets added.

### Resume a session from a commit

```bash
# Get the session ID from the last commit
git log -1 --format=%B | grep "Claude-Session-Id:" | awk '{print $2}'

# Or resume directly in one line
claude --resume $(git log -1 --format=%B | grep "Claude-Session-Id:" | awk '{print $2}')
```

### Resume from a specific commit

```bash
claude --resume $(git log <commit-sha> -1 --format=%B | grep "Claude-Session-Id:" | awk '{print $2}')
```

### Helper alias

Add this to your `~/.bashrc` or `~/.zshrc`:

```bash
# Resume Claude session from a git commit
claude-resume() {
  local ref="${1:-HEAD}"
  local sid
  sid=$(git log "$ref" -1 --format=%B | grep "Claude-Session-Id:" | awk '{print $2}')
  if [ -z "$sid" ]; then
    echo "No Claude-Session-Id found in commit $(git rev-parse --short "$ref")"
    return 1
  fi
  echo "Resuming session: $sid"
  claude --resume "$sid"
}
```

Then:

```bash
claude-resume            # resume from HEAD
claude-resume abc1234    # resume from a specific commit
claude-resume HEAD~3     # resume from 3 commits ago
```

### Browse sessions in your git log

```bash
# List all commits with Claude session IDs
git log --all --grep="Claude-Session-Id:" --oneline

# Show session IDs alongside commit messages
git log --format="%h %s" --all | while read -r line; do
  sha=$(echo "$line" | awk '{print $1}')
  sid=$(git log "$sha" -1 --format=%B | grep "Claude-Session-Id:" | awk '{print $2}')
  if [ -n "$sid" ]; then
    echo "$line  [$sid]"
  fi
done
```

## Why Claude Code hooks instead of git hooks?

You might wonder: why not use git's native `prepare-commit-msg` or `post-commit` hook?

The problem is **scope**. A git hook fires on every commit — yours, Claude's, scripts, CI, everything. There's no reliable way for a git hook to know that a commit was made by Claude Code, or to access the Claude session ID.

Claude Code hooks solve both problems. They only fire when Claude Code performs an action, and they receive the `session_id` in their JSON payload. This means the trailer is added exclusively to Claude-authored commits, and the session ID is always available.

| | Git hooks | Claude Code hooks |
|---|---|---|
| Fires on Claude commits | Yes | Yes |
| Fires on manual commits | Yes | No |
| Has access to session ID | No | Yes |
| Can distinguish Claude vs human | No | Yes |

## Limitations and known issues

**Session ID stability on resume.** There is a [known issue](https://github.com/anthropics/claude-code/issues/12235) where resumed Claude Code sessions may receive a new session ID instead of preserving the original. This means if Claude resumes a session and then commits, the trailer will contain the new ID, not the original. Both IDs point to the same conversation content, but you may need to try the original ID if the new one doesn't resume as expected.

**No native PreCommit/PostCommit hooks yet.** Claude Code doesn't have dedicated git commit lifecycle hooks. There's a [feature request](https://github.com/anthropics/claude-code/issues/4834) for this. The current approach uses `PostToolUse` on Bash commands and amends after the fact, which works but is slightly indirect.

**Amend-based approach.** Because the hook runs *after* the commit, it uses `git commit --amend` to inject the trailer. This changes the commit SHA. In practice this is harmless since it happens immediately and before any push, but it's worth being aware of if you have other post-commit automation.

**Session storage is local.** Claude Code stores sessions on your local machine under `~/.claude/projects/`. If you switch machines, the session files won't be there, so the session ID in the commit becomes a reference you can't resume from. Consider backing up your session files if you work across multiple machines.

## Uninstall

Remove the hook entry from your `~/.claude/settings.json` and delete the script:

```bash
rm ~/.claude/hooks/inject-session-id.sh
```

Then edit `~/.claude/settings.json` and remove the `PostToolUse` entry for `inject-session-id.sh`.

## Related projects

- [jjagent](https://github.com/schpet/jjagent) — Similar concept for the `jj` version control system, stores `Claude-session-id` trailers and manages branches per session
- [claude-commit](https://github.com/JohannLai/claude-commit) — AI-powered commit message generator using Claude
- [claude-auto-commit](https://github.com/0xkaz/claude-auto-commit) — Automatic commit message generation with Claude Code SDK

## License

MIT
