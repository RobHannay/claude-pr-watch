---
description: Arm (or re-arm) the session-scoped GitHub PR watcher, or register a PR with it. Use when the user asks to watch a PR, or if the auto-armed watcher was stopped and should be restarted.
---

# Session-scoped PR watcher

The watcher monitors only the PRs **this session registers** — not all of the user's open PRs. Events (new comments, CI transitions, merges/closes) arrive as notifications in this session.

## Arming

1. If a Monitor running `watch-pr-activity.sh` is already active in this session, don't arm another — just register PRs (below).
2. Check dependencies: `gh` (authenticated) and `jq` on PATH. If missing, tell the user and stop.
3. Create an empty watchlist file in your scratchpad (e.g. `<scratchpad>/pr-watchlist.txt`).
4. Call the Monitor tool with:
   - `command`: `WATCH_LIST=<absolute watchlist path> bash "${CLAUDE_PLUGIN_ROOT}/scripts/watch-pr-activity.sh"`
   - `description`: `PR activity on session-registered PRs`
   - `persistent`: `true`

## Registering PRs — be trigger-happy

Append a line (`owner/repo#123` or a PR URL) to the watchlist whenever a specific PR comes up:

- you open or update a PR
- the user links, mentions, or asks about one
- you review one, check its CI, or discuss it
- the current branch has an open PR

The watcher re-reads the file every cycle: registration takes effect within one interval, duplicates are deduped, and merged/closed PRs are dropped automatically (a `WATCHING:` confirmation event fires once per new PR).

## Handling events

Triage agentically — surface and act on what matters, stay quiet on noise:

- **Always surface**: red CI, merges/closes, human review comments (draft a reply where sensible), any comment addressed to Claude.
- **Stay quiet on**: deploy-preview bot posts, bots re-announcing resolved findings, repeated green↔pending CI flips while the user is actively pushing (mention once, then only report terminal changes).

## Tuning

Env vars: `WATCH_INTERVAL` (poll seconds, default 60), `WATCH_STATE_DIR` (pre-seeded state), `WATCH_MAX_CYCLES` (testing). The comment stream is deliberately unfiltered — filtering is the consuming session's job.
