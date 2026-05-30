#!/usr/bin/env bash
# claude-code-p10k-statusline installer (macOS / Linux / Windows Git-bash).
#
# Installs: the statusline script -> ~/.claude/statusline.sh, the Claude Code
# settings.json wiring, the MesloLGS NF Nerd Font, and best-effort terminal font
# config (VS Code / Cursor). On Windows, font + terminal config are better handled by
# install.ps1 — this script wires up the script + settings and points you there.
#
# Safe: every modified file is backed up to "<file>.bak-<timestamp>" first, JSON is only
# rewritten when jq parses it cleanly, and --dry-run shows actions without changing anything.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/beregcamlost/claude-code-p10k-statusline/main/install.sh | bash
#   ./install.sh [--no-font] [--no-terminal-config] [--dry-run] [--ref BRANCH]
set -eu

REF="main"; NO_FONT=0; NO_TERM=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-font) NO_FONT=1 ;;
    --no-terminal-config) NO_TERM=1 ;;
    --dry-run) DRY=1 ;;
    --ref) shift; REF="${1:-main}" ;;
    -h|--help) if [ -f "$0" ]; then sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; else printf '%s\n' "Usage: install.sh [--no-font] [--no-terminal-config] [--dry-run] [--ref BRANCH]"; fi; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  [ $# -gt 0 ] && shift || true
done

REPO_RAW="https://raw.githubusercontent.com/beregcamlost/claude-code-p10k-statusline/$REF"
FONT_BASE="https://github.com/romkatv/powerlevel10k-media/raw/master"
FONT_FAMILY="MesloLGS NF"
FONTS=("MesloLGS NF Regular.ttf" "MesloLGS NF Bold.ttf" "MesloLGS NF Italic.ttf" "MesloLGS NF Bold Italic.ttf")

if [ -t 1 ]; then C='\033[36m'; G='\033[32m'; Y='\033[33m'; W='\033[37m'; Z='\033[0m'; else C=''; G=''; Y=''; W=''; Z=''; fi
step(){ printf "\n${W}==> %s${Z}\n" "$1"; }
info(){ printf "${C}  %s${Z}\n" "$1"; }
ok(){   printf "${G}  [ok] %s${Z}\n" "$1"; }
warn(){ printf "${Y}  [!]  %s${Z}\n" "$1"; }
have(){ command -v "$1" >/dev/null 2>&1; }

backup(){ # $1 = file
  [ -f "$1" ] || return 0
  local bak="$1.bak-$(date +%Y%m%d-%H%M%S)"
  if [ "$DRY" = 1 ]; then info "would back up $1 -> $bak"; else cp "$1" "$bak"; info "backed up -> $bak"; fi
}

fetch(){ # $1 = url, $2 = out
  if have curl; then curl -fsSL "$1" -o "$2"
  elif have wget; then wget -qO "$2" "$1"
  else warn "need curl or wget to download $1"; return 1; fi
}

# Merge a jq filter into a JSON file, but ONLY if the existing file parses cleanly.
# Never corrupts a file with comments (JSONC): on parse failure it returns 1.
json_merge(){ # $1 = file, $2 = jq filter
  local file="$1" filter="$2" tmp src
  if [ "$DRY" = 1 ]; then info "would update $file"; return 0; fi
  src="$file"
  if [ ! -f "$file" ]; then printf '{}\n' > "$file.seed.$$"; src="$file.seed.$$"; fi
  tmp="$(mktemp)"
  if jq "$filter" "$src" > "$tmp" 2>/dev/null; then
    mkdir -p "$(dirname "$file")"; mv "$tmp" "$file"; rm -f "$file.seed.$$"; return 0
  else
    rm -f "$tmp" "$file.seed.$$"; return 1
  fi
}

OS="$(uname -s 2>/dev/null || echo unknown)"
WINDOWS=0; case "$OS" in MINGW*|MSYS*|CYGWIN*) WINDOWS=1 ;; esac

printf "${W}claude-code-p10k-statusline installer${Z}  (OS: %s, ref: %s)\n" "$OS" "$REF"
[ "$DRY" = 1 ] && warn "DRY RUN — no changes will be made"

# -------------------------------------------------------------------------------------
step "1/5  Install statusline.sh -> ~/.claude/statusline.sh"
CLAUDE_DIR="$HOME/.claude"; DEST="$CLAUDE_DIR/statusline.sh"
[ "$DRY" = 1 ] || mkdir -p "$CLAUDE_DIR"
backup "$DEST"
# Use a sibling statusline.sh ONLY when invoked as a real path (./install.sh from a clone).
# Under 'curl | bash', $0 is 'bash' (no '/'), so we download instead of grabbing a stray
# statusline.sh from the user's current directory.
LOCAL=""
case "$0" in
  */*) SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"; [ -n "$SELF_DIR" ] && LOCAL="$SELF_DIR/statusline.sh" ;;
esac
if [ "$DRY" = 1 ]; then
  info "would install statusline.sh"
elif [ -n "$LOCAL" ] && [ -f "$LOCAL" ] && [ "$LOCAL" != "$DEST" ]; then
  cp "$LOCAL" "$DEST"; info "copied local $LOCAL"
elif fetch "$REPO_RAW/statusline.sh" "$DEST"; then
  info "downloaded from $REPO_RAW"
else
  warn "failed to download statusline.sh from $REPO_RAW (check --ref / network)"; exit 1
fi
[ "$DRY" = 1 ] || chmod +x "$DEST"
[ "$DRY" = 1 ] || ok "installed $DEST"

# -------------------------------------------------------------------------------------
step "2/5  Wire up ~/.claude/settings.json (statusLine block)"
SETTINGS="$CLAUDE_DIR/settings.json"
if have jq; then
  backup "$SETTINGS"
  if json_merge "$SETTINGS" '. + {statusLine:{type:"command",command:"~/.claude/statusline.sh",padding:0,refreshInterval:10}}'; then
    ok "statusLine configured in settings.json"
  else
    warn "settings.json did not parse as strict JSON — add this block manually:"
    printf '%s\n' '    "statusLine": { "type": "command", "command": "~/.claude/statusline.sh", "padding": 0, "refreshInterval": 10 }'
  fi
else
  warn "jq not found — add this to ~/.claude/settings.json manually:"
  printf '%s\n' '    "statusLine": { "type": "command", "command": "~/.claude/statusline.sh", "padding": 0, "refreshInterval": 10 }'
fi

# -------------------------------------------------------------------------------------
step "3/5  Check runtime deps"
case "$(bash --version 2>/dev/null | head -1)" in
  *version\ [5-9].*|*version\ 4.[2-9]*|*version\ 4.[1-9][0-9]*) ok "bash $(bash -c 'echo $BASH_VERSION')" ;;
  *) warn "bash 4.2+ recommended (uses mapfile + printf %()T). macOS ships 3.2 — 'brew install bash'." ;;
esac
if have jq; then ok "jq $(jq --version 2>/dev/null)"; else warn "jq not found — required at runtime. macOS: 'brew install jq'; Debian: 'sudo apt install jq'."; fi

# -------------------------------------------------------------------------------------
step "4/5  Install $FONT_FAMILY"
if [ "$NO_FONT" = 1 ]; then info "skipped (--no-font)"
elif [ "$WINDOWS" = 1 ]; then
  warn "On Windows, run install.ps1 (PowerShell) for a proper per-user font install + registry."
  info "  iwr -useb https://raw.githubusercontent.com/beregcamlost/claude-code-p10k-statusline/$REF/install.ps1 | iex"
else
  case "$OS" in
    Darwin) FONT_DIR="$HOME/Library/Fonts" ;;
    *)      FONT_DIR="$HOME/.local/share/fonts" ;;
  esac
  [ "$DRY" = 1 ] || mkdir -p "$FONT_DIR"
  for f in "${FONTS[@]}"; do
    target="$FONT_DIR/$f"
    if [ -f "$target" ]; then info "$f already present"; continue; fi
    enc="$(printf '%s' "$f" | sed 's/ /%20/g')"
    if [ "$DRY" = 1 ]; then info "would download $f"; continue; fi
    if fetch "$FONT_BASE/$enc" "$target"; then ok "installed $f"; else warn "failed: $f"; fi
  done
  if [ "$OS" != "Darwin" ] && have fc-cache && [ "$DRY" != 1 ]; then fc-cache -f "$FONT_DIR" >/dev/null 2>&1 && info "fc-cache refreshed"; fi
  info "Then select '$FONT_FAMILY' as your terminal font (most terminals: Preferences > Profile > Font)."
fi

# -------------------------------------------------------------------------------------
step "5/5  Point editors at $FONT_FAMILY (best-effort, backed up)"
if [ "$NO_TERM" = 1 ]; then info "skipped (--no-terminal-config)"
elif ! have jq; then info "jq required to edit editor settings — skipping (font is set in the terminal directly)."
else
  case "$OS" in
    Darwin) CODE_BASE="$HOME/Library/Application Support" ;;
    *)      CODE_BASE="${XDG_CONFIG_HOME:-$HOME/.config}" ;;
  esac
  [ "$WINDOWS" = 1 ] && CODE_BASE="${APPDATA:-$HOME/AppData/Roaming}"
  for app in "Code/User" "Code - Insiders/User" "Cursor/User"; do
    cfg="$CODE_BASE/$app/settings.json"
    [ -f "$cfg" ] || continue
    backup "$cfg"
    if json_merge "$cfg" ".[\"terminal.integrated.fontFamily\"] = \"$FONT_FAMILY, monospace\""; then
      ok "set terminal font in $cfg"
    else
      warn "couldn't parse $cfg (has comments?) — add manually: \"terminal.integrated.fontFamily\": \"$FONT_FAMILY, monospace\""
    fi
  done
  [ "$WINDOWS" = 1 ] && info "Windows Terminal font: run install.ps1, or set Profiles > Defaults > Font face = '$FONT_FAMILY'."
fi

printf "\n${W}Done.${Z} Open a new Claude Code session (or wait one refresh tick) to see the statusline.\n"
info "IDE terminal without a Nerd Font? set CC_STATUSLINE_GLYPHS=emoji (or auto) in that terminal's env."
