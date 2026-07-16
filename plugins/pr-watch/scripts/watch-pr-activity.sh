#!/bin/bash
# Watch your open GitHub PRs and emit one line per event on stdout
# (consumed by a Claude Code Monitor):
#   COMMENT  — any new issue/inline comment (unfiltered; the consuming
#              Claude session decides what deserves a response)
#   NEW PR   — a PR you authored appeared (created after the monitor started)
#   CI       — a PR's check rollup changed (passing/failing/pending/no-checks)
#   MERGED / CLOSED — a PR left the open set (verified via gh pr view)
#
# Env overrides (for testing): WATCH_INTERVAL, WATCH_MAX_CYCLES (0 = forever),
# WATCH_STATE_DIR (pre-seeded state diffs on the first cycle), WATCH_START
# (ISO timestamp; PRs created before it never announce as NEW).
set -u

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

PREV="$STATE_DIR/prev.tsv"   # lines: owner/repo#num <TAB> ci-status <TAB> title
CUR="$STATE_DIR/cur.tsv"
TAB=$(printf '\t')

COMMENT_FILTER='
  .[]
  | ((.issue_url // .pull_request_url) | capture("/(?<n>[0-9]+)$").n) as $n
  | select(($numlist | split(",")) | index($n))
  | select(.created_at > $last)
  | "COMMENT \($repo)#\($n) — \(.user.login)\(if .path then " on \(.path)" else "" end): \(.body | gsub("[\\r\\n\\t]+"; " ") | .[0:160])"
'

# TSV columns: key, ci-status, title, createdAt
ROLLUP_FILTER='
  .[]
  | ([.statusCheckRollup[]? | (.conclusion // .state // .status // "PENDING") | ascii_upcase]) as $s
  | (if ($s | length) == 0 then "no-checks"
     elif ($s | any(. == "FAILURE" or . == "ERROR" or . == "TIMED_OUT" or . == "CANCELLED" or . == "STARTUP_FAILURE")) then "failing"
     elif ($s | any(. == "PENDING" or . == "IN_PROGRESS" or . == "QUEUED" or . == "EXPECTED" or . == "WAITING" or . == "ACTION_REQUIRED" or . == "REQUESTED")) then "pending"
     else "passing" end) as $ci
  | "\($repo)#\(.number)\t\($ci)\t\(.title | gsub("[\\r\\n\\t]+"; " "))\t\(.createdAt)"
'

cycle=0
last=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# NEW PR events require createdAt >= START: a PR that "appears" but predates the
# monitor is a GitHub search-index flake resurfacing an old PR, not a new one.
START="${WATCH_START:-$last}"

while true; do
  [ "$cycle" -gt 0 ] && sleep "$INTERVAL"
  cycle=$((cycle + 1))
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  repos=$(gh search prs --author=@me --state=open --limit 100 --json repository \
    --jq '[.[].repository.nameWithOwner] | unique | .[]' 2>/dev/null </dev/null)
  if [ -z "$repos" ]; then
    # Search hiccup or no open PRs: skip diffing so a flaky API can't fake merge events.
    [ "$MAX_CYCLES" != 0 ] && [ "$cycle" -ge "$MAX_CYCLES" ] && exit 0
    continue
  fi

  : > "$CUR"
  ok=1
  for repo in $repos; do
    gh pr list --repo "$repo" --author "@me" --state open --limit 100 \
      --json number,title,statusCheckRollup,createdAt 2>/dev/null </dev/null \
      | jq -r --arg repo "$repo" "$ROLLUP_FILTER" >> "$CUR" || ok=0
  done
  if [ "$ok" = 0 ]; then
    [ "$MAX_CYCLES" != 0 ] && [ "$cycle" -ge "$MAX_CYCLES" ] && exit 0
    continue
  fi
  sort -o "$CUR" "$CUR"

  if [ -s "$PREV" ]; then
    cut -f1 "$PREV" > "$STATE_DIR/prev.keys"
    cut -f1 "$CUR"  > "$STATE_DIR/cur.keys"

    # New PRs (createdAt >= START filters out search-index flakes resurfacing old PRs)
    comm -13 "$STATE_DIR/prev.keys" "$STATE_DIR/cur.keys" | while IFS= read -r key; do
      awk -F'\t' -v k="$key" -v start="$START" \
        '$1 == k && $4 >= start {printf "NEW PR: %s — %s (CI: %s)\n", $1, $3, $2}' "$CUR"
    done

    # Gone PRs — verify state so a transient API miss can't fake a merge
    comm -23 "$STATE_DIR/prev.keys" "$STATE_DIR/cur.keys" | while IFS= read -r key; do
      repo=${key%#*}
      num=${key##*#}
      info=$(gh pr view "$num" --repo "$repo" --json state,title \
        --jq '"\(.state)\t\(.title)"' 2>/dev/null </dev/null) || continue
      state=$(printf '%s' "$info" | cut -f1)
      title=$(printf '%s' "$info" | cut -f2-)
      case "$state" in
        MERGED) echo "MERGED: $key — $title" ;;
        CLOSED) echo "CLOSED without merge: $key — $title" ;;
        *) awk -F'\t' -v k="$key" '$1 == k' "$PREV" >> "$CUR" ;;  # still open: carry forward
      esac
    done
    sort -o "$CUR" "$CUR"

    # CI transitions (join fields: key, prev-ci, prev-title, prev-created, cur-ci, cur-title, cur-created)
    join -t "$TAB" -j 1 "$PREV" "$CUR" 2>/dev/null \
      | awk -F'\t' '$2 != $5 {printf "CI: %s — now %s (was %s) — %s\n", $1, $5, $2, $6}'

    # New comments
    for repo in $repos; do
      nums=$(awk -F'\t' -v r="$repo" '{split($1, a, "#"); if (a[1] == r) print a[2]}' "$CUR" | paste -sd, -)
      [ -z "$nums" ] && continue
      for kind in issues pulls; do
        gh api "repos/$repo/$kind/comments?since=$last&per_page=100" 2>/dev/null </dev/null \
          | jq -r --arg numlist "$nums" --arg repo "$repo" --arg last "$last" "$COMMENT_FILTER" \
          || true
      done
    done
  fi

  cp "$CUR" "$PREV"
  last=$now
  [ "$MAX_CYCLES" != 0 ] && [ "$cycle" -ge "$MAX_CYCLES" ] && exit 0
done
