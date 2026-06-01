# claude-code-p10k-statusline

A [Claude Code](https://claude.com/claude-code) statusline that mirrors the look of your [Powerlevel10k](https://github.com/romkatv/powerlevel10k) prompt — same palette, same icons, same powerline block aesthetic. **Responsive** (adapts to terminal width), **cross-platform** (macOS/Linux/Windows), and works in IDE terminals (VS Code, Zed, JetBrains) via an emoji glyph mode.

```
   ~/proj   main @abc1234   ✦ Opus 4.8 · ◔ ██████░░░░ 67% (134k/200k) · ⏳ 2h 15m left · 28% used ·  4d 2h left · 46% used   ⏱ 12m    23:09 
```

The whole line sits inside a `bg=234` block (matching `POWERLEVEL9K_BACKGROUND=234`), separated by powerline thin chevrons (``), and closed with a solid right chevron (``) — exactly like a p10k segment.

## Features

| Segment | What it shows |
|---|---|
|  /  /  | OS icon — apple on macOS, Tux on Linux, Windows logo on Windows. **Always shown.** |
|  `~/path` /  `/path` | p10k anchor-style path with a contextual icon: **home glyph** under `$HOME` (just the icon at exactly `$HOME`), **folder glyph** elsewhere. Parents in cyan, last segment bold blue. |
|  `branch @sha` | Branch + short HEAD hash (`@sha` only at WIDE). Falls back to short SHA when detached. |
| `REBASE` / `MERGE` / `CHERRY-PICK` / `REVERT` / `BISECT` | Bold red, only mid-operation. (Dirty/ahead/behind/stash *counts* are intentionally not shown.) |
| ` worktree` | Worktree name when active |
| `✦ Opus 4.7` | Model name with `⚡1M` badge for the 1M-context variant (auto-hides if display name already says "1M") |
| `✻` thinking, `· high` effort, `· concise` output style | Auto-hide when default |
| `◆ explorer (2m 15s)` | Active subagent + elapsed duration (tracked via per-session state file) |
| `◔ ██████░░░░ 67% (134k/200k)` | Context: gauge icon + 10-cell `█/░` bar + auto-compact-buffer % + `used/max` tokens. Color: green <50%, yellow 50–80%, red ≥80%. Percentage is rescaled `raw / 0.92` so 92% (auto-compact threshold) reads as 100% |
| `⏳ 2h 15m left  28%` | 5h block: time remaining + always-on usage % (red <30 min) |
| ` 4d 2h left  46%` | 7d block: time remaining + always-on usage % |
| `⏱ 12m` | Wall-clock session duration |
| `23:09` | Realtime clock (HH:MM) |

All segments auto-hide when their data is empty/zero.

## Responsive layout

The line **adapts to your terminal width** so it never overflows on a laptop screen or a split pane. It reads the width from `$COLUMNS` (which Claude Code exports, v2.1.153+), falling back to `tput cols </dev/tty`, then `stty size`, then `120`. Three tiers collapse the line from the least-important segments inward, and a final width clip guarantees it never wraps:

```
WIDE   (≥120)     ~/dev/proj  main @abc1234   ✦ Opus 4.8 ⚡1M · high ✻ · ◔ ██████░░░░ 66% (610k/1M) · ⏳ 2h 15m left · 28% used ·  4d 2h left · 46% used  ⏱ 12m  23:09
MEDIUM (80–119)   ~/dev/proj  main  ✦ Opus 4.8 ⚡1M · ◔ 66% · ⏳2h15m 28% · 7d 46%
NARROW (<80)    proj  main  ✦ Opus 4.8 66% 28%/46%
```

What changes per tier:

| | WIDE | MEDIUM | NARROW |
|---|---|---|---|
| **OS icon** | shown | shown | shown |
| **Path** (+ home/folder icon) | full | parents → initials | basename only |
| **Git** | branch + `@sha` + op-flag | branch + op-flag | branch + op-flag |
| **Model** | name + `⚡1M` + effort + `✻` + style | name + `⚡1M` | name |
| **Context** | `◔ bar 66% (used/max)` | `◔ 66%` | `66%` (color kept) |
| **5h / 7d** | `⏳ 2h 15m left · 28% used` | `⏳2h15m 28%` / `7d 46%` | combined `28%/46%` |
| **worktree · vim · agent-time · telemetry · clock** | shown | hidden | hidden |

Priority is tuned for a power user: **context fill %, model, and rate-limit budget survive longest**; retrospective data (telemetry, clock) goes first. Colors (green/yellow/red thresholds) are preserved at every tier, so even when the gauge and labels are stripped, the `66%` still turns red as you approach auto-compact. When a WIDE line still overflows, the clock and telemetry are dropped (in that order) before any hard clip.

Override anything per-machine via env vars (e.g. pin your laptop to MEDIUM): `CC_STATUSLINE_TIER` (`1`/`2`/`3`), `CC_STATUSLINE_COLS`, `CC_STATUSLINE_WIDE` / `CC_STATUSLINE_MEDIUM` (tier thresholds), `CC_PATH_MED` / `CC_PATH_NARROW` (path char budgets).

### Custom / IDE terminals & cross-platform

Works on **macOS, Linux, and Windows** (Git-bash/MSYS/WSL) — the OS icon auto-selects apple/Tux/Windows. For embedded IDE terminals that often lack a Nerd Font (**VS Code, Zed, JetBrains, Android Studio**), switch the icon set so glyphs don't render as tofu:

```bash
export CC_STATUSLINE_GLYPHS=emoji   # 🍎/🐧/🪟, 🏠/📁, 🌿, 📅 — drawn by the system emoji font
# or
export CC_STATUSLINE_GLYPHS=auto    # emoji when an IDE terminal is detected, nerd otherwise
```

Modes: `nerd` (default), `emoji`, `ascii` (plain text, zero special glyphs), `auto`. **`auto`** uses emoji in terminals that usually ship *without* a Nerd Font — VS Code, Zed, JetBrains, and a default **Windows Terminal / PowerShell** (detected via `WT_SESSION`) — and `nerd` everywhere else, including **Warp** (which bundles MesloLGS NF). If you install a Nerd Font in Windows Terminal (the installer does), force the crisp glyphs there with `CC_STATUSLINE_GLYPHS=nerd`. Set it in that terminal's profile/env (e.g. VS Code `terminal.integrated.env`, or your shell rc).

## Requirements

- **bash 4+ available** (uses `mapfile`). macOS ships bash 3.2 by default; install bash 5 with `brew install bash`. It need **not** be your default shell — when launched under an older bash, the script auto-re-execs under a newer one (`/opt/homebrew/bin/bash`, `/usr/local/bin/bash`, or `/usr/bin/bash`).
- **jq** — JSON parsing. `brew install jq`.
- **A 256-color terminal** (any modern one).
- **A Nerd Font v3** is recommended (apple, git branch, calendar, home/folder, powerline glyphs). Without one, set `CC_STATUSLINE_GLYPHS=emoji` (or `auto`). ([https://www.nerdfonts.com/](https://www.nerdfonts.com/))

## Install

### Quick (script)

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/beregcamlost/claude-code-p10k-statusline/main/install.sh | bash
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/beregcamlost/claude-code-p10k-statusline/main/install.ps1 | iex
```

The installer copies `statusline.sh` to `~/.claude/`, wires up the `statusLine` block in `settings.json`, installs the **MesloLGS NF** Nerd Font, and points Windows Terminal / VS Code / Cursor at it. Every file it touches is backed up first; it supports `--dry-run` (`-DryRun` on Windows), `--no-font`, and `--no-terminal-config`, and it never rewrites a JSON config that contains comments — it prints a manual snippet instead. Flags accept `--ref <branch>` (`-Ref` on Windows) to install from a specific revision.

### Manual

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

Everything lives in one bash script. The interesting knobs sit at the top:

- **Responsive breakpoints / tier** — see [Responsive layout](#responsive-layout): `CC_STATUSLINE_TIER`, `CC_STATUSLINE_WIDE`, `CC_STATUSLINE_MEDIUM`, `CC_PATH_MED`, `CC_PATH_NARROW` (set in your shell profile or per-project).
- `BG=$'\033[48;5;234m'` — change the block background color (256-color index)
- `DIR / ANCHOR / CLEAN / MODIFIED / UNTRACKED / CONFLICT` — segment foreground colors. Defaults match p10k's defaults. (Each is also precomputed into a `C*` escape var for a fork-free hot path.)
- `bar_w=10` (in the context-window section) — change bar width
- `for ((i=0; i<filled; i++)); do bar+="█"; done` — swap `█/░` for `▰/▱`, `■/□`, `●/○`, etc.
- To drop a segment entirely, comment out its block; to drop it only on narrow screens, gate it behind a higher `(( tier >= N ))`.

The icons sit in the `# ---------------- icons` block. The Nerd Font Private-Use glyphs (apple, git branch, calendar, worktree, powerline chevrons) are byte-escaped as `$'\xHH'` UTF-8 so they survive any editor/encoding round-trip; standard Unicode symbols are left as literals.

## How it works

Claude Code pipes a JSON event to your `statusLine.command` on stdin. The script reads:

- `model.id` / `model.display_name`
- `workspace.current_dir` / `cwd` / `worktree.*`
- `context_window.used_percentage` / `context_window_size`
- `cost.total_duration_ms`
- `agent.name`, `effort.level`, `thinking.enabled`, `output_style.name`, `vim.mode`
- `rate_limits.five_hour.{used_percentage,resets_at}`
- `rate_limits.seven_day.{used_percentage,resets_at}`

All JSON fields are read in a **single `jq` pass** (the values are emitted one-per-line and slurped with `mapfile`), and numeric fields that may arrive as JSON floats (`total_duration_ms`, `resets_at`) are normalized to integers before any `$(( ))` arithmetic. Git data is kept deliberately lightweight: a **pure-bash walk** up the directory tree first looks for a `.git` entry, so outside a repository the script forks no `git` at all; inside one, a **single `git rev-parse`** returns is-inside / git-dir / short SHA, and `git symbolic-ref` resolves the branch (falling back to the SHA when detached). Mid-operation flags (rebase / merge / cherry-pick / revert / bisect) come from cheap file checks in the git dir. Change counts (ahead/behind/staged/dirty/stash) are intentionally omitted, so render stays fast even in huge repos. The clock and timestamps use bash's `printf '%()T'` (no `date` fork on bash 4.2+).

Externally-derived strings (branch, agent, worktree, output-style names) are stripped of control/ESC bytes before rendering, so a crafted name can't inject ANSI sequences into your terminal.

Subagent durations are tracked via a tiny state file at `${TMPDIR}/claude-statusline-${USER}/<session>.agent` — created with mode `0700` (private), written on first sighting of an agent name, read on subsequent renders. Files older than 1 day are auto-cleaned.

## Acknowledgements

- Color palette and segment ordering modeled after [Powerlevel10k](https://github.com/romkatv/powerlevel10k) (specifically `my_git_formatter` and `POWERLEVEL9K_DIR_*`).
- Context bar style aligned with the dominant choice across [ccstatusline](https://github.com/sirmalloc/ccstatusline), [claude-powerline](https://github.com/Owloops/claude-powerline), and [claude-hud](https://github.com/jarrodwatts/claude-hud).

## License

MIT — see [LICENSE](./LICENSE).
