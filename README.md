# claude-pr-watch

Live GitHub PR watching **inside your Claude Code session**. Each session registers the PRs it actually touches — ones you open, link, review, or discuss — and a background monitor pushes their events into the running session. Claude wakes on each one, with your full working context, and triages:

- 💬 **Comments** — every new issue/inline comment on watched PRs. Claude drafts replies to human review comments, answers anything addressed to it, and quietly ignores bot noise.
- 🚦 **CI transitions** — passing / failing / pending (red is always surfaced; green↔pending flapping while you push is self-throttled)
- 🎉 **Merges and closes** — detected from PR state, then the PR drops off the watchlist automatically
- 👀 **WATCHING confirmations** — one event when a PR joins the list

A `SessionStart` hook arms the watcher automatically in every session and tells Claude to register PRs liberally as they come up. It also checks whether your current branch has an open PR (`gh pr list --head`) and seeds the watchlist with it — so the PR you're working on is watched from the first minute, zero-touch.

## Why session-scoped?

Watching *all* your open PRs sounds nice and is mostly noise: with dozens of PRs across repos you drown in bot chatter and CI flaps from work you're not thinking about. Scoping to the PRs this session has interacted with keeps events relevant to what you and Claude are actually doing. It also avoids GitHub's flaky search index entirely — the watcher only ever does direct PR lookups.

## Why this instead of the GitHub App / webhooks?

Nothing event-driven can reach a local process, and the GitHub App responds on GitHub with fresh context. This plugin is the "push into the session that has my context" equivalent: polling under the hood (60s, a few API calls per cycle), push from the session's perspective.

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

## Usage

- It just runs: mention a PR, open a PR, review a PR — Claude registers it, and its events appear in your session as they happen.
- Ask Claude to "watch this PR" / "watch MetaviewAI/web-app#1234" to register one explicitly.
- `/pr-watch` — arm manually (e.g. after stopping it, or if you disable the auto-arm hook).
- The watchlist is a plain text file (one `owner/repo#num` or PR URL per line), re-read every cycle — you can edit it yourself.

## Tuning

Environment variables read by `scripts/watch-pr-activity.sh`:

| Var | Default | Purpose |
| --- | --- | --- |
| `WATCH_LIST` | — (required) | Path to the watchlist file |
| `WATCH_INTERVAL` | `60` | Poll interval in seconds |
| `WATCH_STATE_DIR` | temp dir | Persistent state dir (pre-seeded state diffs on the first cycle) |
| `WATCH_MAX_CYCLES` | `0` (forever) | Stop after N cycles — useful for testing |

## Limitations

- **Session-scoped**: nothing watches while no Claude Code session is open. For always-on coverage, pair with the [Claude Code GitHub App](https://code.claude.com/docs/en/github-actions) (`@claude` mentions).
- Review-level bodies (a bare "LGTM" approval with no comments) use a different API and aren't covered; issue comments and inline review comments are.
- Polling: comments/CI can lag up to one interval (~60s).

## License

MIT
