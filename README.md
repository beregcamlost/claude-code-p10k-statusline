# claude-code-p10k-statusline

A [Claude Code](https://claude.com/claude-code) statusline that mirrors the look of your [Powerlevel10k](https://github.com/romkatv/powerlevel10k) prompt — same palette, same icons, same powerline block aesthetic.

```
  ~/proj   main @abc1234 +2 ?1   ✦ Opus 4.7 · ◔ ██████░░░░ 67% (134k/200k) · ⏳ 2h 15m left  28% ·  4d 2h left  46%   ⏱ 12m  +803 -319   23:09 
```

The whole line sits inside a `bg=234` block (matching `POWERLEVEL9K_BACKGROUND=234`), separated by powerline thin chevrons (``), and closed with a solid right chevron (``) — exactly like a p10k segment.

## Features

| Segment | What it shows |
|---|---|
|  | macOS apple icon (white on dark block) |
| `~/path` | p10k anchor-style path: parents in cyan, last segment bold blue, `~` collapse |
|  `branch @sha` | Branch + short HEAD hash. Falls back to short SHA when detached. |
| `REBASE` / `MERGE` / `CHERRY-PICK` / `REVERT` / `BISECT` | Bold red, only mid-operation |
| `⇡⇣` `+` `!` `?` `*` `~` | Ahead / behind / staged / unstaged / untracked / stashed / conflicted — same colors and ordering as p10k's `my_git_formatter` |
| ` worktree` | Worktree name when active |
| `✦ Opus 4.7` | Model name with `⚡1M` badge for the 1M-context variant (auto-hides if display name already says "1M") |
| `✻` thinking, `· high` effort, `· concise` output style | Auto-hide when default |
| `◆ explorer (2m 15s)` | Active subagent + elapsed duration (tracked via per-session state file) |
| `◔ ██████░░░░ 67% (134k/200k)` | Context: gauge icon + 10-cell `█/░` bar + auto-compact-buffer % + `used/max` tokens. Color: green <50%, yellow 50–80%, red ≥80%. Percentage is rescaled `raw / 0.92` so 92% (auto-compact threshold) reads as 100% |
| `⏳ 2h 15m left  28%` | 5h block: time remaining + always-on usage % (red <30 min) |
| ` 4d 2h left  46%` | 7d block: time remaining + always-on usage % |
| `⏱ 12m` | Wall-clock session duration |
| `+803 -319` | Lines added / removed across the session |
| `23:09` | Realtime clock (HH:MM) |

All segments auto-hide when their data is empty/zero.

## Requirements

- **bash 4+** (uses `$'\uXXXX'` ANSI-C quoting). macOS ships bash 3.2; install bash 5 via Homebrew: `brew install bash`.
- **jq** — JSON parsing. `brew install jq`.
- **A Nerd Font v3** terminal — required for the apple, git branch, calendar, and worktree glyphs. ([https://www.nerdfonts.com/](https://www.nerdfonts.com/))
- **A 256-color terminal** (any modern one).

## Install

```bash
mkdir -p ~/.claude
curl -fsSL https://raw.githubusercontent.com/beregcamlost/claude-code-p10k-statusline/main/statusline.sh \
  -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Then merge this into `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0,
    "refreshInterval": 10
  }
}
```

- `padding: 0` keeps the colored block flush with your prompt's left edge.
- `refreshInterval: 10` makes the realtime clock and rate-limit timers tick every 10 seconds without burning CPU.

Open a new Claude Code session (or wait one refresh tick) and the new statusline appears.

## Customization

Everything lives in one ~280-line bash script. The interesting knobs sit at the top:

- `BG=$'\033[48;5;234m'` — change the block background color (256-color index)
- `DIR / ANCHOR / CLEAN / MODIFIED / UNTRACKED / CONFLICT` — segment foreground colors. Defaults match p10k's defaults.
- `bar_w=10` (in the context-window section) — change bar width
- `for ((i=0; i<filled; i++)); do bar+="█"; done` — swap `█/░` for `▰/▱`, `■/□`, `●/○`, etc.
- Drop a section by deleting (or commenting out) its block.

The icons sit in the `# ---------------- icons` block — every icon is encoded as `$'\uXXXX'` so codepoints survive any file save without depending on UTF-8 encoding hazards.

## How it works

Claude Code pipes a JSON event to your `statusLine.command` on stdin. The script reads:

- `model.id` / `model.display_name`
- `workspace.current_dir` / `cwd` / `worktree.*`
- `context_window.used_percentage` / `context_window_size`
- `cost.total_duration_ms` / `total_lines_added` / `total_lines_removed`
- `agent.name`, `effort.level`, `thinking.enabled`, `output_style.name`, `vim.mode`
- `rate_limits.five_hour.{used_percentage,resets_at}`
- `rate_limits.seven_day.{used_percentage,resets_at}`

Git data (branch, SHA, ahead/behind, dirty state, mid-operation flags) is computed fresh per render via `git status --porcelain=v2 --branch`. Render time is ~110 ms even in repos with thousands of changed files.

Subagent durations are tracked via a tiny state file at `${TMPDIR}/claude-statusline-${USER}/<session>.agent` — written on first sighting of an agent name, read on subsequent renders, removed when the agent ends. Files older than 1 day are auto-cleaned at the top of every render.

## Acknowledgements

- Color palette and segment ordering modeled after [Powerlevel10k](https://github.com/romkatv/powerlevel10k) (specifically `my_git_formatter` and `POWERLEVEL9K_DIR_*`).
- Context bar style aligned with the dominant choice across [ccstatusline](https://github.com/sirmalloc/ccstatusline), [claude-powerline](https://github.com/Owloops/claude-powerline), and [claude-hud](https://github.com/jarrodwatts/claude-hud).

## License

MIT — see [LICENSE](./LICENSE).
