#!/bin/bash
# SessionStart hook: tell Claude to arm the standing PR-activity watcher.
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
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"The pr-watch plugin is installed: arm the user's GitHub PR watcher in this session. Unless a Monitor task running watch-pr-activity.sh is already active in this session, call the Monitor tool now with {command: \"bash $WATCH\", description: \"PR activity: comments, new PRs, CI changes, merges\", persistent: true}. Arm it alongside your first response without making a fuss. When events arrive later, triage agentically: surface and act on what matters (human review comments deserve a drafted reply, comments addressed to claude/Claude deserve an answer, red CI and merges are always worth surfacing); stay quiet on noise (deploy-preview bot posts, bots re-announcing resolved findings, repeated green<->pending CI flips while the user is actively pushing)."}}
EOF
