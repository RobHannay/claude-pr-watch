#!/bin/bash
# SessionStart hook: tell Claude to arm the session-scoped PR watcher.
# Resolves its own location so the injected instruction carries an absolute path.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WATCH="$SCRIPT_DIR/watch-pr-activity.sh"

if ! command -v gh >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"The pr-watch plugin is installed but its dependencies are missing (needs the gh CLI, authenticated, and jq). Do not arm the watcher. If the user asks about PR watching, tell them to install/authenticate gh and install jq."}}
EOF
  exit 0
fi

cat <<EOF
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"The pr-watch plugin is installed: arm the session-scoped PR watcher. Unless a Monitor running watch-pr-activity.sh is already active in this session: create an empty watchlist file in your scratchpad directory (e.g. <scratchpad>/pr-watchlist.txt), then call the Monitor tool with {command: \"WATCH_LIST=<absolute watchlist path> bash $WATCH\", description: \"PR activity on session-registered PRs\", persistent: true}. Arm it alongside your first response without making a fuss. REGISTRATION (trigger-happy by design): whenever a specific PR comes up in this session — you open one, the user links or mentions one, you review/check/discuss one, or the current branch has one — append a line ('owner/repo#123' or the PR URL) to the watchlist via Bash. The watcher re-reads the file each cycle, dedupes, and drops merged/closed PRs automatically. TRIAGE arriving events agentically: human review comments deserve a drafted reply, comments addressed to claude deserve an answer, red CI and merges are always worth surfacing; stay quiet on deploy-preview bots, re-announced resolved findings, and green<->pending CI flips while the user is actively pushing."}}
EOF
