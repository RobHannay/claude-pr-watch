# claude-pr-watch

Live GitHub PR watching **inside your Claude Code session**. A background monitor polls your open PRs and pushes events into the running session — Claude wakes on each one, with your full working context, and triages:

- 💬 **Comments** — every new issue/inline comment on your open PRs. Claude drafts replies to human review comments, answers anything addressed to it, and quietly ignores bot noise.
- 🆕 **New PRs** — each pull request you open shows up as an event
- 🚦 **CI transitions** — passing / failing / pending per PR (red is always surfaced; green↔pending flapping while you push is self-throttled)
- 🎉 **Merges and closes** — verified against the GitHub API so a flaky response can't fake a merge

A `SessionStart` hook arms the watcher automatically in every session, so there's nothing to remember.

## Why this instead of the GitHub App / webhooks?

Nothing event-driven can reach a local process, and the GitHub App responds on GitHub with fresh context. This plugin is the "push into the session that has my context" equivalent: polling under the hood (60s, a handful of API calls per minute), push from the session's perspective.

## Requirements

- [`gh`](https://cli.github.com) CLI, authenticated (`gh auth status`)
- `jq`
- macOS or Linux (the script is bash-3.2 compatible)

## Install

In Claude Code:

```
/plugin marketplace add RobHannay/claude-pr-watch
/plugin install pr-watch@claude-pr-watch
```

That's it — your next session (or `/pr-watch` right away) arms the watcher.

## Usage

- It just runs: events appear in your session as they happen, and Claude tells you about the ones that matter.
- `/pr-watch` — arm manually (e.g. after stopping it, or if you disable the auto-arm hook).
- Watches **all open PRs authored by you** across every repo your `gh` auth can see.

## Tuning

Environment variables read by `scripts/watch-pr-activity.sh`:

| Var | Default | Purpose |
| --- | --- | --- |
| `WATCH_INTERVAL` | `60` | Poll interval in seconds |
| `WATCH_STATE_DIR` | temp dir | Persistent state dir (pre-seeded state diffs on the first cycle) |
| `WATCH_MAX_CYCLES` | `0` (forever) | Stop after N cycles — useful for testing |
| `WATCH_START` | monitor start time | ISO timestamp; PRs created before it never announce as NEW (guards against GitHub search-index flakes resurfacing old PRs) |

## Limitations

- **Session-scoped**: nothing watches while no Claude Code session is open. For always-on coverage, pair with the [Claude Code GitHub App](https://code.claude.com/docs/en/github-actions) (`@claude` mentions).
- Review-level bodies (a bare "LGTM" approval with no comments) use a different API and aren't covered; issue comments and inline review comments are.
- Polling: comments/CI can lag up to one interval (~60s).

## License

MIT
