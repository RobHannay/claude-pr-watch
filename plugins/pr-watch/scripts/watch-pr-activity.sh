#!/bin/bash
# Watch a session-registered list of GitHub PRs and emit one line per event
# on stdout (consumed by a Claude Code Monitor):
#   WATCHING — a PR was added to the watchlist (confirmation, emitted once)
#   COMMENTS — new issue/inline comments, grouped per PR per cycle with a
#              count (unfiltered snippets; the consuming Claude session
#              should fetch the full comments before acting)
#   CI       — a PR's check rollup changed (passing/failing/pending/no-checks)
#   MERGED / CLOSED — the PR's state changed (watching then stops)
#
# WATCH_LIST (required): path to the watchlist file. One PR per line, either
#   owner/repo#123   or   https://github.com/owner/repo/pull/123
# The file is re-read every cycle, so appending a line starts watching that PR
# within one interval — no restart needed. Duplicates are fine.
#
# Env overrides (for testing): WATCH_INTERVAL, WATCH_MAX_CYCLES (0 = forever),
# WATCH_STATE_DIR (pre-seeded state diffs on the first cycle).
set -u

LIST="${WATCH_LIST:?set WATCH_LIST to the watchlist file path}"
INTERVAL="${WATCH_INTERVAL:-60}"
MAX_CYCLES="${WATCH_MAX_CYCLES:-0}"

STATE_DIR="${WATCH_STATE_DIR:-}"
CLEANUP=0
if [ -z "$STATE_DIR" ]; then
  STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pr-watch.XXXXXX") || exit 1
  CLEANUP=1
else
  mkdir -p "$STATE_DIR"
fi
trap '[ "$CLEANUP" = 1 ] && rm -rf "$STATE_DIR"' EXIT

PREV="$STATE_DIR/prev.tsv"   # lines: owner/repo#num <TAB> state <TAB> ci <TAB> title
CUR="$STATE_DIR/cur.tsv"
DONE="$STATE_DIR/done.keys"  # merged/closed keys — skipped on every later cycle
touch "$DONE"
TAB=$(printf '\t')

# Emits TSV: key <TAB> author[ on path] <TAB> snippet — aggregated per PR below.
COMMENT_FILTER='
  .[]
  | ((.issue_url // .pull_request_url) | capture("/(?<n>[0-9]+)$").n) as $n
  | select(($numlist | split(",")) | index($n))
  | select(.created_at > $last)
  | "\($repo)#\($n)\t\(.user.login)\(if .path then " on \(.path)" else "" end)\t\(.body | gsub("[\\r\\n\\t]+"; " ") | .[0:120])"
'

PR_FILTER='
  ([.statusCheckRollup[]? | (.conclusion // .state // .status // "PENDING") | ascii_upcase]) as $s
  | (if ($s | length) == 0 then "no-checks"
     elif ($s | any(. == "FAILURE" or . == "ERROR" or . == "TIMED_OUT" or . == "CANCELLED" or . == "STARTUP_FAILURE")) then "failing"
     elif ($s | any(. == "PENDING" or . == "IN_PROGRESS" or . == "QUEUED" or . == "EXPECTED" or . == "WAITING" or . == "ACTION_REQUIRED" or . == "REQUESTED")) then "pending"
     else "passing" end) as $ci
  | "\($key)\t\(.state)\t\($ci)\t\(.title | gsub("[\\r\\n\\t]+"; " "))"
'

cycle=0
last=$(date -u +%Y-%m-%dT%H:%M:%SZ)

while true; do
  [ "$cycle" -gt 0 ] && sleep "$INTERVAL"
  cycle=$((cycle + 1))
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Normalize the watchlist (URLs -> owner/repo#num), dedupe, drop finished PRs.
  keys=""
  if [ -f "$LIST" ]; then
    keys=$(sed -E 's|https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+).*|\1/\2#\3|' "$LIST" \
      | grep -E '^[^/ ]+/[^# ]+#[0-9]+$' | sort -u | grep -vxF -f "$DONE" || true)
  fi
  if [ -z "$keys" ]; then
    [ "$MAX_CYCLES" != 0 ] && [ "$cycle" -ge "$MAX_CYCLES" ] && exit 0
    continue
  fi

  : > "$CUR"
  for key in $keys; do
    repo=${key%#*}
    num=${key##*#}
    gh pr view "$num" --repo "$repo" --json state,title,statusCheckRollup 2>/dev/null </dev/null \
      | jq -r --arg key "$key" "$PR_FILTER" >> "$CUR" \
      || awk -F'\t' -v k="$key" '$1 == k' "$PREV" >> "$CUR"   # transient fetch failure: carry forward
  done
  sort -o "$CUR" "$CUR"

  if [ -s "$PREV" ]; then
    JOINED="$STATE_DIR/joined.tsv"   # key, prev-state, prev-ci, prev-title, cur-state, cur-ci, cur-title
    join -t "$TAB" -j 1 "$PREV" "$CUR" 2>/dev/null > "$JOINED"

    # Newly watched PRs (in cur, not prev)
    join -t "$TAB" -j 1 -v 2 "$PREV" "$CUR" 2>/dev/null \
      | awk -F'\t' '{printf "WATCHING: %s — %s (%s, CI: %s)\n", $1, $4, tolower($2), $3}'

    # State transitions and CI changes
    awk -F'\t' '$2 == "OPEN" && $5 == "MERGED" {printf "MERGED: %s — %s\n", $1, $7}
                $2 == "OPEN" && $5 == "CLOSED" {printf "CLOSED without merge: %s — %s\n", $1, $7}
                $2 == "OPEN" && $5 == "OPEN" && $3 != $6 {printf "CI: %s — now %s (was %s) — %s\n", $1, $6, $3, $7}' "$JOINED"

    # New comments, per repo, only on still-open PRs — collected first, then
    # emitted as ONE event line per PR so a burst of review comments can't
    # split across notifications.
    COLLECTED="$STATE_DIR/comments.tsv"
    : > "$COLLECTED"
    for repo in $(printf '%s\n' $keys | sed 's|#.*||' | sort -u); do
      nums=$(awk -F'\t' -v r="$repo" '$2 == "OPEN" {split($1, a, "#"); if (a[1] == r) print a[2]}' "$CUR" | paste -sd, -)
      [ -z "$nums" ] && continue
      for kind in issues pulls; do
        gh api "repos/$repo/$kind/comments?since=$last&per_page=100" 2>/dev/null </dev/null \
          | jq -r --arg numlist "$nums" --arg repo "$repo" --arg last "$last" "$COMMENT_FILTER" >> "$COLLECTED" \
          || true
      done
    done
    awk -F'\t' '
      { c[$1]++; if (t[$1] != "") t[$1] = t[$1] " ¦ "; t[$1] = t[$1] $2 ": " $3 }
      END { for (k in c) printf "COMMENTS %s — %d new: %s\n", k, c[k], substr(t[k], 1, 500) }
    ' "$COLLECTED"
  fi

  # Anything not OPEN is finished: skip it on all later cycles.
  awk -F'\t' '$2 != "OPEN" {print $1}' "$CUR" >> "$DONE"
  sort -u -o "$DONE" "$DONE"

  cp "$CUR" "$PREV"
  last=$now
  [ "$MAX_CYCLES" != 0 ] && [ "$cycle" -ge "$MAX_CYCLES" ] && exit 0
done
