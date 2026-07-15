---
description: Arm (or re-arm) the live GitHub PR watcher for this session. Use when the user asks to watch their PRs, or if the auto-armed watcher was stopped and should be restarted.
---

# Arm the PR watcher

Start a persistent Monitor for the user's open GitHub PRs. Events (new comments, new PRs, CI transitions, merges/closes) arrive as notifications in this session.

1. If a Monitor task running `watch-pr-activity.sh` is already active in this session, say so and stop — never arm two.
2. Check dependencies: `gh` (authenticated) and `jq` must be on PATH. If missing, tell the user what to install and stop.
3. Call the Monitor tool with:
   - `command`: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/watch-pr-activity.sh"`
   - `description`: `PR activity: comments, new PRs, CI changes, merges`
   - `persistent`: `true`

## Handling events

Triage agentically — surface and act on what matters, stay quiet on noise:

- **Always surface**: red CI, merges/closes, new PRs, human review comments (draft a reply where sensible), any comment addressed to Claude.
- **Stay quiet on**: deploy-preview bot posts, bots re-announcing resolved findings, repeated green↔pending CI flips while the user is actively pushing (mention once, then only report terminal changes).

## Tuning

The script honors env vars: `WATCH_INTERVAL` (poll seconds, default 60), `WATCH_STATE_DIR` (pre-seeded state), `WATCH_MAX_CYCLES` (testing). The comment stream is deliberately unfiltered — filtering is the consuming session's job, per the guidance above.
