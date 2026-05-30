#!/usr/bin/env bash
# Claude Code statusline — Powerlevel10k aesthetic, RESPONSIVE to terminal width.
# Renders a single-line, p10k-styled segment block (bg=234, powerline chevron close)
# matching the user's ~/.p10k.zsh palette and nerdfont-v3 icons.
#
# Responsive design: the line collapses to fit the terminal width via 3 tiers.
# The OS icon (apple/tux/windows) and the path (with a home/folder icon) show at
# EVERY tier; git shows branch + mid-operation flag only (no change counts).
#   tier 3 WIDE   (cols >= 120): everything — @sha, context bar+tokens, both rate
#                                blocks with labels, model flags, telemetry, clock.
#   tier 2 MEDIUM (80..119):     model + ctx% + rate% kept; bar/tokens/sha/flags/
#                                clock/telemetry/worktree/vim dropped; path->initials.
#   tier 1 NARROW (< 80):        essentials — OS+path, branch, model, ctx%, 5h%/7d%.
# Width source (in order): $CC_STATUSLINE_COLS, $COLUMNS (Claude Code sets it,
#   v2.1.153+), `tput cols </dev/tty`, `stty size </dev/tty`, then 120.
#
# Env knobs (override anything per-machine / per-terminal):
#   CC_STATUSLINE_GLYPHS=nerd|emoji|ascii|auto   icon set (default nerd). Use 'emoji'
#                              or 'auto' for IDE terminals without a Nerd Font
#                              (VS Code, Zed, JetBrains/Android Studio).
#   CC_STATUSLINE_TIER=1|2|3   force a tier (skip auto-detect)
#   CC_STATUSLINE_COLS=N       force a column count
#   CC_STATUSLINE_WIDE=120     >= this -> tier 3
#   CC_STATUSLINE_MEDIUM=80    >= this -> tier 2 (else tier 1)
#   CC_PATH_MED=28             path char budget at tier 2
#   CC_PATH_NARROW=16          path char budget at tier 1
#
# Works on macOS, Linux, and Windows (Git-bash/MSYS/WSL).
# Requirements: bash 4+ (mapfile), jq, a 256-color terminal. A Nerd Font v3 is
# recommended; without one set CC_STATUSLINE_GLYPHS=emoji (or auto).

set +e
input=$(cat)

# ---------------- one-pass JSON parse (single jq fork; was ~20) ----------------
# Each field on its own line so empty values survive as empty lines (mapfile keeps them).
mapfile -t _F < <(printf '%s' "$input" | jq -r '
  [ (.model.id // "")
  , (.model.display_name // "")
  , (.workspace.current_dir // .cwd // "")
  , (.session_id // "")
  , (.output_style.name // "")
  , ((.exceeds_200k_tokens // false) | tostring)
  , (.context_window.used_percentage // "" | tostring)
  , (.context_window.context_window_size // "" | tostring)
  , (.cost.total_duration_ms // "" | tostring)
  , (.cost.total_lines_added // "" | tostring)
  , (.cost.total_lines_removed // "" | tostring)
  , (.effort.level // "")
  , ((.thinking.enabled // false) | tostring)
  , (.agent.name // "")
  , (.worktree.name // "")
  , (.rate_limits.five_hour.used_percentage // "" | tostring)
  , (.rate_limits.five_hour.resets_at // "" | tostring)
  , (.rate_limits.seven_day.used_percentage // "" | tostring)
  , (.rate_limits.seven_day.resets_at // "" | tostring)
  , (.vim.mode // "")
  ] | .[]' 2>/dev/null)

# Strip CR from every field: a Windows/Git-bash jq build emits CRLF line endings, so
# mapfile leaves a trailing \r on each value (breaks is_num/arithmetic). No-op on macOS.
for _i in "${!_F[@]}"; do _F[$_i]=${_F[$_i]//$'\r'/}; done

model_id=${_F[0]}
model_name=${_F[1]}
cwd=${_F[2]}
session_id=${_F[3]}
output_style=${_F[4]}
exceeds=${_F[5]}
ctx_pct=${_F[6]}
ctx_size=${_F[7]}
wall_ms=${_F[8]}
lines_added=${_F[9]}
lines_removed=${_F[10]}
effort=${_F[11]}
thinking=${_F[12]}
agent_name=${_F[13]}
worktree_name=${_F[14]}
rate_5h=${_F[15]}
rate_5h_reset=${_F[16]}
rate_7d=${_F[17]}
rate_7d_reset=${_F[18]}
vim_mode=${_F[19]}

is_num() { [[ $1 =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; }

# Normalize fields used in bash $(( )) arithmetic to integers. Claude Code can emit
# these as JSON floats (e.g. total_duration_ms=60000.5, resets_at=1735500000.0); a
# fractional part makes $(( )) abort with "invalid arithmetic operator". Strip it once.
for _v in wall_ms ctx_size lines_added lines_removed rate_5h_reset rate_7d_reset; do
  _t=${!_v}; printf -v "$_v" '%s' "${_t%.*}"
done

# Strip control/ESC bytes from externally-derived display strings so a crafted
# branch/agent/worktree/style name can't inject ANSI escapes into the terminal.
strip_ctl() {
  local s=${!1}
  s=${s//$'\033'/}; s=${s//$'\r'/}; s=${s//$'\n'/}; s=${s//$'\t'/}
  s=${s//$'\a'/};   s=${s//$'\b'/}; s=${s//$'\f'/}; s=${s//$'\v'/}
  printf -v "$1" '%s' "$s"
}
for _v in model_name agent_name worktree_name output_style vim_mode effort; do strip_ctl "$_v"; done
cwd=${cwd//$'\r'/}   # defensive: a stray CR (e.g. CRLF-edited config) breaks git -C and path display

# ---------------- ANSI ----------------
e=$'\033'
F() { printf '%s[38;5;%sm' "$e" "$1"; }
B=$'\033[1m'
R=$'\033[22;39m'      # reset bold + fg only (preserves bg)
RST=$'\033[0m'         # full reset
BG=$'\033[48;5;234m'   # p10k POWERLEVEL9K_BACKGROUND=234
DEFBG=$'\033[49m'      # default bg

# ---------------- p10k palette (matches ~/.p10k.zsh) ----------------
DIR=31; ANCHOR=39
CLEAN=76; MODIFIED=178; UNTRACKED=39; CONFLICT=196
META=242; ACCENT=39; COST=178; OS=255; DIM=244; SUBSEP=242

# Precomputed SGR escapes — avoids a subshell fork per color in the hot path
# (the original called $(F "$X") ~30x/render; these build the same strings fork-free).
CDIR="${e}[38;5;${DIR}m";       CANCHOR="${e}[38;5;${ANCHOR}m"
CCLEAN="${e}[38;5;${CLEAN}m";   CMOD="${e}[38;5;${MODIFIED}m";  CUNTRACK="${e}[38;5;${UNTRACKED}m"
CCONF="${e}[38;5;${CONFLICT}m"; CACCENT="${e}[38;5;${ACCENT}m"; CCOST="${e}[38;5;${COST}m"
COS="${e}[38;5;${OS}m";         CDIM="${e}[38;5;${DIM}m";       CSUBSEP="${e}[38;5;${SUBSEP}m"
C234="${e}[38;5;234m"

# ---------------- glyph set: nerd | emoji | ascii | auto ----------------
# Custom IDE terminals (VS Code, Zed, JetBrains / Android Studio) frequently run
# WITHOUT a Nerd Font, so Private-Use glyphs render as tofu boxes. 'emoji' swaps
# them for system emoji (drawn by the OS emoji font — no special terminal font
# needed); 'ascii' uses plain text; 'auto' detects known IDE terminals and uses
# emoji there, nerd elsewhere. Nerd-mode PUA glyphs are byte-escaped (\xHH UTF-8)
# so they survive any editor/encoding round-trip.
glyphs=${CC_STATUSLINE_GLYPHS:-nerd}
if [[ $glyphs == auto ]]; then
  if [[ ${TERM_PROGRAM:-} == vscode || ${TERM_PROGRAM:-} == zed \
     || ${TERMINAL_EMULATOR:-} == *JetBrains* \
     || -n ${ZED_TERM:-} || -n ${__INTELLIJ_COMMAND_HISTFILE__:-} ]]; then
    glyphs=emoji
  else
    glyphs=nerd
  fi
fi

# Shared (non-PUA) symbols — render fine in any of the modes below.
ICN_MODEL='✦'; ICN_AGENT='◆'; ICN_BRAIN='✻'; ICN_GAUGE='◔'
ICN_HOURGLASS='⏳'; ICN_CLOCK='⏱'; ICN_BOLT='⚡'; ICN_AT='@'
BAR_FULL='█'; BAR_EMPTY='░'

case $glyphs in
  emoji)
    ICN_OS_MAC='🍎'; ICN_OS_LINUX='🐧'; ICN_OS_WIN='🪟'
    ICN_HOME='🏠'; ICN_FOLDER='📁'; ICN_GIT='🌿'; ICN_TREE='🌲'; ICN_CAL='📅'
    PSEP_THIN='│'; PSEP_END=''
    WIDE_GLYPHS='⏳⚡⏱🍎🐧🪟🏠📁🌿🌲📅'   # double-width glyphs for the width clip
    ;;
  ascii)
    ICN_OS_MAC='mac'; ICN_OS_LINUX='lnx'; ICN_OS_WIN='win'
    ICN_HOME='~'; ICN_FOLDER=''; ICN_GIT=''; ICN_TREE='wt:'; ICN_CAL=''
    ICN_MODEL='*'; ICN_AGENT='>'; ICN_BRAIN='*'; ICN_GAUGE=''
    ICN_HOURGLASS=''; ICN_CLOCK=''; ICN_BOLT=''
    BAR_FULL='#'; BAR_EMPTY='-'
    PSEP_THIN='|'; PSEP_END=''
    WIDE_GLYPHS=''
    ;;
  *)  # nerd (default)
    ICN_OS_MAC=$'\xef\x85\xb9'      # U+F179 apple
    ICN_OS_LINUX=$'\xef\x85\xbc'    # U+F17C tux
    ICN_OS_WIN=$'\xef\x85\xba'      # U+F17A windows
    ICN_HOME=$'\xef\x80\x95'        # U+F015 home
    ICN_FOLDER=$'\xef\x81\xbb'      # U+F07B folder
    ICN_GIT=$'\xef\x84\xa6'         # U+F126 git branch
    ICN_TREE=$'\xee\x9c\xa5'        # U+E725 devicons git_branch (worktree)
    ICN_CAL=$'\xef\x81\xb3'         # U+F073 calendar (7d)
    PSEP_THIN=$'\xee\x82\xb1'       # U+E0B1 powerline thin separator (same-bg)
    PSEP_END=$'\xee\x82\xb0'        # U+E0B0 powerline solid right chevron
    WIDE_GLYPHS='⏳⚡⏱'
    ;;
esac

# OS icon (shown at every tier), chosen by platform — works on macOS, Linux, Windows.
case "${OSTYPE:-}" in
  darwin*)          ICN_OS=$ICN_OS_MAC ;;
  linux*)           ICN_OS=$ICN_OS_LINUX ;;
  msys|cygwin|win*) ICN_OS=$ICN_OS_WIN ;;
  *) case "$(uname -s 2>/dev/null)" in
       Darwin*)              ICN_OS=$ICN_OS_MAC ;;
       MINGW*|MSYS*|CYGWIN*) ICN_OS=$ICN_OS_WIN ;;
       Linux*)               ICN_OS=$ICN_OS_LINUX ;;
       *)                    ICN_OS=$ICN_OS_MAC ;;
     esac ;;
esac

# ---------------- responsive: detect terminal width, pick a tier ----------------
cols=${CC_STATUSLINE_COLS:-}
[[ $cols =~ ^[0-9]+$ ]] || cols=${COLUMNS:-}
[[ $cols =~ ^[0-9]+$ ]] || cols=$( { tput cols; } 2>/dev/null </dev/tty )
[[ $cols =~ ^[0-9]+$ ]] || cols=$( stty size 2>/dev/null </dev/tty | { read -r _ c; printf '%s' "$c"; } )
{ [[ $cols =~ ^[0-9]+$ ]] && (( cols > 0 )); } || cols=120

WIDE_AT=${CC_STATUSLINE_WIDE:-120}
MED_AT=${CC_STATUSLINE_MEDIUM:-80}
tier=${CC_STATUSLINE_TIER:-}
if [[ ! $tier =~ ^[123]$ ]]; then
  if   (( cols >= WIDE_AT )); then tier=3
  elif (( cols >= MED_AT  )); then tier=2
  else                             tier=1
  fi
fi

# Separators scale with the tier: full powerline chevrons when wide, spaces when narrow.
if (( tier >= 2 )); then
  SEP=" ${CSUBSEP}${PSEP_THIN}$R "   # major section break
  DOT=" ${CDIM}·$R "                 # minor in-section break
else
  SEP="  "                               # narrow: plain spaces, no glyphs
  DOT=" "
fi

# ---------------- helpers ----------------
fmt_tok() {
  awk -v n="$1" 'BEGIN{
    if (n >= 1000000) { v = n/1000000; if (v == int(v)) printf "%dM", v; else printf "%.1fM", v }
    else if (n >= 1000) { printf "%.0fk", n/1000 }
    else { printf "%d", n }
  }'
}

fmt_dur_short() {
  local s=$1
  if   (( s < 60   )); then printf '%ds' "$s"
  elif (( s < 3600 )); then printf '%dm' "$((s/60))"
  else printf '%dh %dm' "$((s/3600))" "$(( (s%3600)/60 ))"
  fi
}

# Progressively shrink a path to a char budget: full -> parents as initials -> middle-ellipsis leaf.
shrink_path() {
  local p="$1" budget="$2"
  (( ${#p} <= budget )) && { printf '%s' "$p"; return; }
  local IFS=/ ; local parts last out="" i n seg
  read -ra parts <<< "$p"
  n=${#parts[@]}; last="${parts[n-1]}"
  for ((i=0; i<n-1; i++)); do
    seg="${parts[i]}"
    if   [[ -z $seg   ]]; then out+="/"
    elif [[ $seg == "~" ]]; then out+="~/"
    else out+="${seg:0:1}/"; fi
  done
  out+="$last"
  (( ${#out} <= budget )) && { printf '%s' "$out"; return; }
  if (( budget >= 4 )); then
    local keep=$(( budget - 1 )); (( keep > ${#last} )) && keep=${#last}
    printf '…%s' "${last: -keep}"
  else
    printf '%s' "${last: -budget}"
  fi
}

# Visible column width of a rendered string (ANSI escapes are zero-width; ⏳⚡⏱ = 2).
vis_w() {
  local s=$1
  local i=0 c w=0 n=${#s}
  while (( i < n )); do
    c=${s:i:1}
    if [[ $c == $'\033' ]]; then ((i++)); while (( i < n )); do c=${s:i:1}; ((i++)); [[ $c == [A-Za-z] ]] && break; done; continue; fi
    if [[ -n $WIDE_GLYPHS && $WIDE_GLYPHS == *"$c"* ]]; then ((w+=2)); else ((w++)); fi
    ((i++))
  done
  printf '%s' "$w"
}

# Clip a rendered string to a VISIBLE column budget. ANSI SGR escapes are copied
# through (zero width); ⏳⚡⏱ count as 2 columns, everything else as 1. This is the
# final guarantee that the line never overflows the terminal, regardless of tier.
clip_visible() {
  local s=$1 budget=$2
  local i=0 c cw w=0 n=${#s}            # n on its own line: ${#s} needs s already assigned
  # pass 1: total visible width (ANSI escapes are zero-width).
  while (( i < n )); do
    c=${s:i:1}
    if [[ $c == $'\033' ]]; then ((i++)); while (( i < n )); do c=${s:i:1}; ((i++)); [[ $c == [A-Za-z] ]] && break; done; continue; fi
    if [[ -n $WIDE_GLYPHS && $WIDE_GLYPHS == *"$c"* ]]; then ((w+=2)); else ((w++)); fi
    ((i++))
  done
  (( w <= budget )) && { printf '%s' "$s"; return; }
  # pass 2: clip to budget-1 (reserve 1 col for the ellipsis), append "…".
  local out="" lim=$(( budget - 1 )); w=0; i=0
  while (( i < n )); do
    c=${s:i:1}
    if [[ $c == $'\033' ]]; then          # copy a full escape sequence verbatim
      out+=$c; ((i++))
      while (( i < n )); do c=${s:i:1}; out+=$c; ((i++)); [[ $c == [A-Za-z] ]] && break; done
      continue
    fi
    cw=1; [[ -n $WIDE_GLYPHS && $WIDE_GLYPHS == *"$c"* ]] && cw=2
    (( w + cw > lim )) && break
    out+=$c; ((w+=cw)); ((i++))
  done
  printf '%s…' "$out"
}

now_ts=$(date +%s)

# ==================================================================
# Segments are built into four groups joined by SEP:
#   gA = OS + path + git + worktree    gB = model/flags/agent/vim/ctx/rate
#   gC = session telemetry             gD = clock
# Building into groups (instead of appending live) avoids dangling separators
# when a tier drops a whole group.
# ==================================================================
gA=""; gB=""; gC=""; gD=""
bdot() { [[ -n $gB ]] && gB+="$DOT"; }   # in-group separator for gB

# ---------------- OS icon (always shown — apple / tux / windows) ----------------
gA+="${COS}$B${ICN_OS}$R"

# ---------------- path (p10k anchor style + contextual home/folder icon) ----------------
# Home glyph when under $HOME (just the icon at exactly $HOME), folder glyph elsewhere.
if [[ $cwd == "$HOME" ]]; then
  pcontext=home; ppath=""
elif [[ $cwd == "$HOME"/* ]]; then
  pcontext=home; ppath="${cwd#"$HOME"/}"
elif [[ -n $cwd ]]; then
  pcontext=folder; ppath="$cwd"
else
  pcontext=none; ppath=""
fi
case $tier in
  1) [[ -n $ppath ]] && ppath="${ppath##*/}"; ppath=$(shrink_path "$ppath" "${CC_PATH_NARROW:-16}") ;;
  2) ppath=$(shrink_path "$ppath" "${CC_PATH_MED:-28}") ;;
esac
if [[ $pcontext != none ]]; then
  if [[ $pcontext == home ]]; then picon=$ICN_HOME; picolor=$CANCHOR; else picon=$ICN_FOLDER; picolor=$CDIR; fi
  psep=""; [[ -n $gA ]] && psep="  "
  seg="$psep"
  [[ -n $picon ]] && seg+="${picolor}${picon}$R "
  if [[ -n $ppath ]]; then
    if [[ $ppath == */* ]]; then
      parent="${ppath%/*}"; last="${ppath##*/}"
      seg+="${CDIR}${parent}/$R${CANCHOR}$B${last}$R"
    else
      seg+="${CANCHOR}$B${ppath}$R"
    fi
  else
    seg="${seg% }"            # exact $HOME: just the home icon, no trailing space
  fi
  gA+="$seg"
fi

# ---------------- git: branch + mid-operation flag (+ @sha at WIDE) ----------------
# Change counts (ahead/behind/staged/unstaged/untracked/stash) intentionally omitted.
in_repo=0; branch=""; sha=""; git_op=""; git_dir=""
if [[ -n $cwd ]]; then
  mapfile -t _g < <(git -C "$cwd" rev-parse --is-inside-work-tree --git-dir 2>/dev/null)
  if [[ ${_g[0]} == "true" ]]; then
    in_repo=1
    git_dir=${_g[1]}; [[ -n $git_dir && $git_dir != /* ]] && git_dir="$cwd/$git_dir"
    branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null)
    sha=$(git -C "$cwd" rev-parse --short=7 HEAD 2>/dev/null)
    [[ -z $branch ]] && branch=$sha          # detached HEAD -> short sha
    strip_ctl branch
    if [[ -n $git_dir ]]; then
      if   [[ -d $git_dir/rebase-merge || -d $git_dir/rebase-apply ]]; then git_op="REBASE"
      elif [[ -f $git_dir/MERGE_HEAD ]];        then git_op="MERGE"
      elif [[ -f $git_dir/CHERRY_PICK_HEAD ]];  then git_op="CHERRY-PICK"
      elif [[ -f $git_dir/REVERT_HEAD ]];       then git_op="REVERT"
      elif [[ -f $git_dir/BISECT_LOG ]];        then git_op="BISECT"
      fi
    fi
  fi
fi

if (( in_repo )); then
  gsp=""; [[ -n $gA ]] && gsp="  "
  gA+="${gsp}${CCLEAN}${ICN_GIT}${ICN_GIT:+ }${branch}$R"
  (( tier >= 3 )) && [[ -n $sha && $sha != "$branch" ]] && gA+=" ${CDIM}${ICN_AT}${sha}$R"
  [[ -n $git_op ]] && gA+=" ${CCONF}$B${git_op}$R"        # mid-operation: shown at all tiers
fi

# ---------------- worktree (tier 3 only) ----------------
(( tier >= 3 )) && [[ -n $worktree_name ]] && gA+=" ${CDIM}${ICN_TREE} ${worktree_name}$R"

# ---------------- model + flags ----------------
if [[ -n $model_name ]]; then
  gB+="${CACCENT}${ICN_MODEL} $B${model_name}$R"
  if (( tier >= 2 )) && { [[ $model_id == *"[1m]"* ]] || [[ $model_id == *"-1m"* ]]; } && \
     [[ $model_name != *"1M"* && $model_name != *"1m"* ]]; then
    gB+=" ${CCOST}${ICN_BOLT}1M$R"
  fi
  if (( tier >= 3 )); then
    [[ -n $effort && $effort != "medium" && $effort != "default" ]] && gB+="${DOT}${CDIM}${effort}$R"
    [[ $thinking == "true" ]] && gB+=" ${CDIM}${ICN_BRAIN}$R"
    [[ -n $output_style && $output_style != "default" ]] && gB+="${DOT}${CDIM}${output_style}$R"
  fi
fi

# ---------------- agent (+ duration via per-session state file) ----------------
if [[ -n $agent_name ]] && (( tier >= 2 )); then
  state_dir="${TMPDIR:-/tmp}/claude-statusline-${USER:-$(id -u 2>/dev/null)}"
  (umask 077; mkdir -p "$state_dir" 2>/dev/null)        # private: 0700, not world-readable
  find "$state_dir" -type f -mtime +1 -delete 2>/dev/null
  agent_state_file="$state_dir/${session_id:-default}.agent"
  start_ts=$now_ts
  if [[ -r $agent_state_file ]]; then
    IFS=: read -r prev_name prev_ts < "$agent_state_file"
    if [[ $prev_name == "$agent_name" ]] && is_num "$prev_ts"; then
      start_ts=$prev_ts
    else
      printf '%s:%s\n' "$agent_name" "$start_ts" > "$agent_state_file"
    fi
  else
    printf '%s:%s\n' "$agent_name" "$start_ts" > "$agent_state_file"
  fi
  if (( tier >= 3 )); then
    agent_dur=$(fmt_dur_short "$(( now_ts - start_ts ))")
    gB+=" ${CMOD}${ICN_AGENT} ${agent_name}$R ${CDIM}(${agent_dur})$R"
  else
    gB+=" ${CMOD}${ICN_AGENT} ${agent_name}$R"
  fi
fi

# ---------------- vim mode (tier 3 only; skip insert) ----------------
(( tier >= 3 )) && [[ -n $vim_mode && $vim_mode != "INSERT" ]] && gB+=" ${CDIM}[${vim_mode}]$R"

# ---------------- context window (priority #1 — shown at every tier) ----------------
# Percentage is rescaled raw/0.92 so 92% (auto-compact threshold) reads as 100%.
# Token count uses the RAW used% against context_window_size (i.e. real tokens),
# while the % is the auto-compact-adjusted "usable window" figure — two distinct
# but intentional numbers. Color: green <50, yellow 50-79, red >=80 (on the gauge %).
if is_num "$ctx_pct"; then
  ci=${ctx_pct%.*}; is_num "$ci" || ci=0
  ac_pct=$(( ci * 100 / 92 )); (( ac_pct > 100 )) && ac_pct=100; (( ac_pct < 0 )) && ac_pct=0
  ctx_color=$CCLEAN
  (( ac_pct >= 50 )) && ctx_color=$CMOD
  (( ac_pct >= 80 )) && ctx_color=$CCONF
  if (( tier >= 3 )); then
    bar_w=10; filled=$(( ac_pct * bar_w / 100 ))
    (( filled > bar_w )) && filled=$bar_w; (( filled < 0 )) && filled=0
    bar=""
    for ((i=0; i<filled;       i++)); do bar+="$BAR_FULL"; done
    for ((i=0; i<bar_w-filled; i++)); do bar+="$BAR_EMPTY"; done
    tok_str=""
    if is_num "$ctx_size" && (( ctx_size > 0 )); then
      used_tok=$(( ci * ctx_size / 100 ))
      tok_str=" ${CDIM}($(fmt_tok "$used_tok")/$(fmt_tok "$ctx_size"))$R"
    fi
    bdot; gB+="${ctx_color}${ICN_GAUGE} ${bar} ${ac_pct}%$R${tok_str}"
  elif (( tier == 2 )); then
    bdot; gB+="${ctx_color}${ICN_GAUGE} ${ac_pct}%$R"
  else
    bdot; gB+="${ctx_color}${ac_pct}%$R"
  fi
elif [[ $exceeds == "true" ]]; then
  bdot; gB+="${CCONF}$B${ICN_GAUGE} 200K+$R"
fi

# ---------------- rate limits (5h + 7d) ----------------
r5=${rate_5h%.*}; is_num "$r5" || r5=""
r7=${rate_7d%.*}; is_num "$r7" || r7=""
r5_left=""; rem5=0
if is_num "$rate_5h_reset"; then rem5=$(( rate_5h_reset - now_ts )); (( rem5 > 0 )) && r5_left=$(fmt_dur_short "$rem5"); fi
r7_left=""
if is_num "$rate_7d_reset"; then
  rem7=$(( rate_7d_reset - now_ts ))
  if (( rem7 > 0 )); then
    d7=$(( rem7/86400 )); h7=$(( (rem7%86400)/3600 ))
    if (( d7 > 0 )); then r7_left="${d7}d ${h7}h"; else r7_left=$(fmt_dur_short "$rem7"); fi
  fi
fi
rc5=$CDIM; [[ -n $r5 ]] && { (( r5 >= 50 )) && rc5=$CMOD; (( r5 >= 80 )) && rc5=$CCONF; }
rc7=$CDIM; [[ -n $r7 ]] && { (( r7 >= 50 )) && rc7=$CMOD; (( r7 >= 80 )) && rc7=$CCONF; }

if (( tier >= 3 )); then
  # 5h: time-left + always-on usage %
  p5=""; [[ -n $r5 ]] && p5="${DOT}${rc5}${r5}% used$R"
  if [[ -n $r5_left ]]; then
    lc5=$CDIM; (( rem5 < 1800 )) && lc5=$CCONF
    bdot; gB+="${lc5}${ICN_HOURGLASS} ${r5_left} left$R${p5}"
  elif [[ -n $r5 ]]; then
    bdot; gB+="${CDIM}5h$R${p5}"
  fi
  # 7d: time-left + always-on usage %
  p7=""; [[ -n $r7 ]] && p7="${DOT}${rc7}${r7}% used$R"
  if [[ -n $r7_left ]]; then
    bdot; gB+="${CDIM}${ICN_CAL} ${r7_left} left$R${p7}"
  elif [[ -n $r7 ]]; then
    bdot; gB+="${CDIM}${ICN_CAL} 7d$R${p7}"
  fi
elif (( tier == 2 )); then
  # compact: "⏳2h15m 28%"  /  "7d 46%"
  if [[ -n $r5_left || -n $r5 ]]; then
    bdot; o5=""
    [[ -n $r5_left ]] && o5+="${CDIM}${ICN_HOURGLASS}${r5_left}$R"
    [[ -n $r5 ]] && { [[ -n $o5 ]] && o5+=" "; o5+="${rc5}${r5}%$R"; }
    gB+="$o5"
  fi
  [[ -n $r7 ]] && { bdot; gB+="${CDIM}7d ${rc7}${r7}%$R"; }
else
  # narrow: combined "28%/46%"
  combo=""
  [[ -n $r5 ]] && combo+="${rc5}${r5}%$R"
  if [[ -n $r7 ]]; then [[ -n $combo ]] && combo+="${CDIM}/$R"; combo+="${rc7}${r7}%$R"; fi
  [[ -n $combo ]] && { bdot; gB+="$combo"; }
fi

# ---------------- session telemetry: wall-clock + lines diff (tier 3 only) ----------------
if (( tier >= 3 )); then
  have_wall=0
  if is_num "$wall_ms" && (( wall_ms >= 60000 )); then have_wall=1; fi
  have_diff=0
  { is_num "$lines_added"   && (( lines_added   > 0 )); } && have_diff=1
  { is_num "$lines_removed" && (( lines_removed > 0 )); } && have_diff=1
  if (( have_wall || have_diff )); then
    if (( have_wall )); then
      gC+="${CDIM}${ICN_CLOCK} $(fmt_dur_short "$(( wall_ms/1000 ))")$R"
    fi
    if (( have_diff )); then
      (( have_wall )) && gC+=" "
      if is_num "$lines_added" && (( lines_added > 0 )); then gC+="${CCLEAN}+${lines_added}$R"; fi
      if is_num "$lines_removed" && (( lines_removed > 0 )); then
        { is_num "$lines_added" && (( lines_added > 0 )); } && gC+=" "
        gC+="${CCONF}-${lines_removed}$R"
      fi
    fi
  fi
fi

# ---------------- realtime clock (tier 3 only) ----------------
(( tier >= 3 )) && gD="${CDIM}$(date +%H:%M)$R"

# ---------------- assemble + clip to terminal width ----------------
budget=$(( cols - 2 )); (( budget < 10 )) && budget=10   # reserve trailing space + chevron

out=""
join() { local g="$1"; [[ -z $g ]] && return; [[ -n $out ]] && out+="$SEP"; out+="$g"; }
join "$gA"; join "$gB"; join "$gC"; join "$gD"

# Graceful degradation (tier 3 only — narrower tiers have no gC/gD): if the rich line
# overflows, drop the lowest-priority groups (clock, then telemetry) before a hard clip.
if (( tier >= 3 )) && (( $(vis_w "$out") > budget )); then
  out=""; join "$gA"; join "$gB"; join "$gC"            # drop clock
  if (( $(vis_w "$out") > budget )); then
    out=""; join "$gA"; join "$gB"                       # drop telemetry too
  fi
fi
out=$(clip_visible "$out" "$budget")

# Wrap content in bg=234, close with a fg=234 chevron on default bg (p10k segment look).
# When the glyph mode has no powerline chevron (emoji/ascii), just end the block cleanly.
if [[ -n $PSEP_END ]]; then
  printf '%s' "${BG}${out} ${R}${DEFBG}${C234}${PSEP_END}${RST}"
else
  printf '%s' "${BG}${out} ${RST}"
fi
