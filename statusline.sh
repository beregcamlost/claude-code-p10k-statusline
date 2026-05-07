#!/usr/bin/env bash
# Claude Code statusline — Powerlevel10k aesthetic.
# Renders a single-line, p10k-styled segment block (bg=234, powerline chevron close)
# matching the user's ~/.p10k.zsh palette and nerdfont-v3 icons.

set +e
input=$(cat)

J() { jq -r "$1 // empty" 2>/dev/null <<<"$input"; }

# ---------------- JSON fields ----------------
model_id=$(J '.model.id')
model_name=$(J '.model.display_name')
cwd=$(J '.workspace.current_dir'); [[ -z $cwd ]] && cwd=$(J '.cwd')
session_id=$(J '.session_id')
output_style=$(J '.output_style.name')
exceeds=$(J '.exceeds_200k_tokens')
ctx_pct=$(J '.context_window.used_percentage')
ctx_size=$(J '.context_window.context_window_size')
wall_ms=$(J '.cost.total_duration_ms')
lines_added=$(J '.cost.total_lines_added')
lines_removed=$(J '.cost.total_lines_removed')
effort=$(J '.effort.level')
thinking=$(J '.thinking.enabled')
agent_name=$(J '.agent.name')
worktree_name=$(J '.worktree.name')
rate_5h=$(J '.rate_limits.five_hour.used_percentage')
rate_5h_reset=$(J '.rate_limits.five_hour.resets_at')
rate_7d=$(J '.rate_limits.seven_day.used_percentage')
rate_7d_reset=$(J '.rate_limits.seven_day.resets_at')
vim_mode=$(J '.vim.mode')

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

# ---------------- icons (Nerd Font v3, codepoint-encoded so they survive any write) ----------------
ICN_OS=$''                # apple (fa-apple)
ICN_GIT=$''                # git branch (matches POWERLEVEL9K_VCS_BRANCH_ICON)
ICN_MODEL='✦'                    # sparkle (universal)
ICN_TREE=$''               # devicons git_branch (worktree)
ICN_AGENT='◆'                    # diamond (universal)
ICN_BRAIN='✻'                    # 8-pointed star (thinking, universal)
ICN_GAUGE='◔'                    # quarter circle (universal)
ICN_HOURGLASS='⏳'                # 5h block
ICN_CAL=$''                # calendar (7d)
ICN_CLOCK='⏱'                     # api/session duration
ICN_BOLT='⚡'                     # 1M variant
ICN_AT='@'                       # git SHA
PSEP_THIN=$''              # powerline thin separator (same-bg)
PSEP_END=$''                # powerline solid right chevron

# ---------------- helpers ----------------
out=""
SEP=" $(F $SUBSEP)${PSEP_THIN}$R "          # major section break
DOT=" $(F $DIM)·$R "                        # minor in-section break
add() { out+="$1"; }
add_sep() { [[ -n $out ]] && out+="$SEP"; }
is_num() { [[ $1 =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; }

fmt_tok() {
  awk -v n="$1" 'BEGIN{
    if (n >= 1000000) {
      v = n/1000000
      if (v == int(v)) printf "%dM", v
      else printf "%.1fM", v
    } else if (n >= 1000) {
      printf "%.0fk", n/1000
    } else {
      printf "%d", n
    }
  }'
}

fmt_dur_short() {
  local s=$1
  if   (( s < 60   )); then printf '%ds' "$s"
  elif (( s < 3600 )); then printf '%dm' "$((s/60))"
  else printf '%dh %dm' "$((s/3600))" "$(( (s%3600)/60 ))"
  fi
}

# ==================================================================
# Segments
# ==================================================================

# ---------------- OS icon ----------------
add "$(F $OS)$B${ICN_OS}$R"

# ---------------- path (p10k anchor style) ----------------
if [[ $cwd == "$HOME" ]]; then
  display_path="~"
elif [[ $cwd == "$HOME"/* ]]; then
  display_path="~${cwd#"$HOME"}"
else
  display_path="$cwd"
fi
if [[ -n $display_path ]]; then
  if [[ $display_path == */* ]]; then
    parent="${display_path%/*}"
    last="${display_path##*/}"
    add "  $(F $DIR)${parent}/$R$(F $ANCHOR)$B${last}$R"
  else
    add "  $(F $ANCHOR)$B${display_path}$R"
  fi
fi

# ---------------- git ----------------
if [[ -n $cwd ]] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  [[ -z $branch ]] && branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  sha=$(git -C "$cwd" rev-parse --short=7 HEAD 2>/dev/null)

  git_dir=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)
  git_op=""
  if [[ -n $git_dir ]]; then
    [[ ! $git_dir = /* ]] && git_dir="$cwd/$git_dir"
    if   [[ -d $git_dir/rebase-merge || -d $git_dir/rebase-apply ]]; then git_op="REBASE"
    elif [[ -f $git_dir/MERGE_HEAD ]];        then git_op="MERGE"
    elif [[ -f $git_dir/CHERRY_PICK_HEAD ]];  then git_op="CHERRY-PICK"
    elif [[ -f $git_dir/REVERT_HEAD ]];       then git_op="REVERT"
    elif [[ -f $git_dir/BISECT_LOG ]];        then git_op="BISECT"
    fi
  fi

  ahead=0; behind=0
  staged=0; unstaged=0; untracked=0; conflicts=0; stashes=0
  while IFS= read -r line; do
    case "$line" in
      "# branch.ab "*)
        rest="${line#\# branch.ab }"
        a="${rest%% *}"; b="${rest##* }"
        ahead="${a#+}"; behind="${b#-}"
        is_num "$ahead"  || ahead=0
        is_num "$behind" || behind=0
        ;;
      "1 "*|"2 "*)
        xy="${line:2:2}"
        [[ ${xy:0:1} != "." ]] && ((staged++))
        [[ ${xy:1:1} != "." ]] && ((unstaged++))
        ;;
      "u "*) ((conflicts++)) ;;
      "? "*) ((untracked++)) ;;
    esac
  done < <(git -C "$cwd" status --porcelain=v2 --branch 2>/dev/null)
  stashes=$(git -C "$cwd" stash list 2>/dev/null | wc -l | tr -d ' ')

  add "  $(F $CLEAN)${ICN_GIT} ${branch}$R"
  [[ -n $sha ]] && add " $(F $DIM)${ICN_AT}${sha}$R"
  [[ -n $git_op ]] && add " $(F $CONFLICT)$B${git_op}$R"
  ((behind))    && add " $(F $CLEAN)⇣${behind}$R"
  ((ahead))     && add " $(F $CLEAN)⇡${ahead}$R"
  ((stashes))   && add " $(F $CLEAN)*${stashes}$R"
  ((conflicts)) && add " $(F $CONFLICT)~${conflicts}$R"
  ((staged))    && add " $(F $MODIFIED)+${staged}$R"
  ((unstaged))  && add " $(F $MODIFIED)!${unstaged}$R"
  ((untracked)) && add " $(F $UNTRACKED)?${untracked}$R"
fi

# ---------------- worktree ----------------
[[ -n $worktree_name ]] && add " $(F $DIM)${ICN_TREE} ${worktree_name}$R"

# ---------------- separator: path/git → model ----------------
add_sep

# ---------------- model + flags ----------------
if [[ -n $model_name ]]; then
  add "$(F $ACCENT)${ICN_MODEL} $B${model_name}$R"
  # Only add the ⚡1M badge if display_name doesn't already mention 1M.
  if { [[ $model_id == *"[1m]"* ]] || [[ $model_id == *"-1m"* ]]; } && \
     [[ $model_name != *"1M"* && $model_name != *"1m"* ]]; then
    add " $(F $COST)${ICN_BOLT}1M$R"
  fi
fi
if [[ -n $effort && $effort != "medium" && $effort != "default" ]]; then
  add "${DOT}$(F $DIM)${effort}$R"
fi
[[ $thinking == "true" ]] && add " $(F $DIM)${ICN_BRAIN}$R"
if [[ -n $output_style && $output_style != "default" ]]; then
  add "${DOT}$(F $DIM)${output_style}$R"
fi

# ---------------- agent (with duration tracking) ----------------
state_dir="${TMPDIR:-/tmp}/claude-statusline-${USER}"
mkdir -p "$state_dir" 2>/dev/null
agent_state_file="$state_dir/${session_id:-default}.agent"
now_ts=$(date +%s)
find "$state_dir" -type f -mtime +1 -delete 2>/dev/null

if [[ -n $agent_name ]]; then
  start_ts=$now_ts
  if [[ -r $agent_state_file ]]; then
    IFS=: read -r prev_name prev_ts < "$agent_state_file"
    [[ $prev_name == "$agent_name" ]] && is_num "$prev_ts" && start_ts=$prev_ts
  fi
  if [[ ! -r $agent_state_file ]] || [[ "$(<"$agent_state_file")" != "${agent_name}:${start_ts}" ]]; then
    printf '%s:%s\n' "$agent_name" "$start_ts" > "$agent_state_file"
  fi
  agent_elapsed=$((now_ts - start_ts))
  agent_dur=$(fmt_dur_short "$agent_elapsed")
  add " $(F $MODIFIED)${ICN_AGENT} ${agent_name}$R $(F $DIM)(${agent_dur})$R"
elif [[ -f $agent_state_file ]]; then
  rm -f "$agent_state_file"
fi

# ---------------- vim mode (skip insert) ----------------
[[ -n $vim_mode && $vim_mode != "INSERT" ]] && add " $(F $DIM)[${vim_mode}]$R"

# ---------------- context window: bar + % + tokens ----------------
if is_num "$ctx_pct"; then
  ac_pct=$(awk -v p="$ctx_pct" 'BEGIN{v=p/0.92; if(v>100)v=100; printf "%d", v}')
  ctx_color=$CLEAN
  (( ac_pct >= 50 )) && ctx_color=$MODIFIED
  (( ac_pct >= 80 )) && ctx_color=$CONFLICT

  bar_w=10
  filled=$(( ac_pct * bar_w / 100 ))
  (( filled > bar_w )) && filled=$bar_w
  (( filled < 0 )) && filled=0
  bar=""
  for ((i=0; i<filled;        i++)); do bar+="█"; done
  for ((i=0; i<bar_w-filled;  i++)); do bar+="░"; done

  tok_str=""
  if is_num "$ctx_size" && (( ctx_size > 0 )); then
    used_tok=$(awk -v p="$ctx_pct" -v s="$ctx_size" 'BEGIN{printf "%d", p*s/100}')
    tok_str=" $(F $DIM)($(fmt_tok "$used_tok")/$(fmt_tok "$ctx_size"))$R"
  fi
  add "${DOT}$(F $ctx_color)${ICN_GAUGE} ${bar} ${ac_pct}%$R${tok_str}"
elif [[ $exceeds == "true" ]]; then
  add "${DOT}$(F $CONFLICT)$B${ICN_GAUGE} 200K+$R"
fi

# ---------------- 5h block: time-left + always-on usage % ----------------
add_5h() {
  local pct_str=""
  if is_num "$rate_5h"; then
    local color=$DIM
    awk -v p="$rate_5h" 'BEGIN{exit !(p>=50)}' && color=$MODIFIED
    awk -v p="$rate_5h" 'BEGIN{exit !(p>=80)}' && color=$CONFLICT
    local pi
    pi=$(awk -v p="$rate_5h" 'BEGIN{printf "%d", p}')
    pct_str="${DOT}$(F $color)${pi}% used$R"
  fi
  if is_num "$rate_5h_reset"; then
    local remain=$(( rate_5h_reset - now_ts ))
    if (( remain > 0 )); then
      local left
      left=$(fmt_dur_short "$remain")
      local color=$DIM
      (( remain < 1800 )) && color=$CONFLICT
      add "${DOT}$(F $color)${ICN_HOURGLASS} ${left} left$R${pct_str}"
      return
    fi
  fi
  [[ -n $pct_str ]] && add "${DOT}$(F $DIM)5h$R${pct_str}"
}
add_5h

# ---------------- 7d block: always show ----------------
add_7d() {
  local pct_str=""
  if is_num "$rate_7d"; then
    local color=$DIM
    awk -v p="$rate_7d" 'BEGIN{exit !(p>=50)}' && color=$MODIFIED
    awk -v p="$rate_7d" 'BEGIN{exit !(p>=80)}' && color=$CONFLICT
    local pi
    pi=$(awk -v p="$rate_7d" 'BEGIN{printf "%d", p}')
    pct_str="${DOT}$(F $color)${pi}% used$R"
  fi
  if is_num "$rate_7d_reset"; then
    local remain=$(( rate_7d_reset - now_ts ))
    if (( remain > 0 )); then
      local days hrs
      days=$(( remain / 86400 ))
      hrs=$(( (remain % 86400) / 3600 ))
      local left
      if (( days > 0 )); then left="${days}d ${hrs}h"
      else                    left=$(fmt_dur_short "$remain")
      fi
      add "${DOT}$(F $DIM)${ICN_CAL} ${left} left$R${pct_str}"
      return
    fi
  fi
  [[ -n $pct_str ]] && add "${DOT}$(F $DIM)${ICN_CAL} 7d$R${pct_str}"
}
add_7d

# ---------------- session telemetry: wall-clock time + lines diff ----------------
have_wall=0
if is_num "$wall_ms" && (( ${wall_ms%.*} >= 60000 )) 2>/dev/null; then
  have_wall=1
fi
have_diff=0
if { is_num "$lines_added" && (( lines_added > 0 )); } || \
   { is_num "$lines_removed" && (( lines_removed > 0 )); }; then
  have_diff=1
fi

if (( have_wall || have_diff )); then
  add_sep
  if (( have_wall )); then
    sec=$((wall_ms/1000))
    dur=$(fmt_dur_short "$sec")
    add "$(F $DIM)${ICN_CLOCK} ${dur}$R"
  fi
  if (( have_diff )); then
    (( have_wall )) && add " "
    if is_num "$lines_added" && (( lines_added > 0 )); then
      add "$(F $CLEAN)+${lines_added}$R"
    fi
    if is_num "$lines_removed" && (( lines_removed > 0 )); then
      is_num "$lines_added" && (( lines_added > 0 )) && add " "
      add "$(F $CONFLICT)-${lines_removed}$R"
    fi
  fi
fi

# ---------------- realtime clock ----------------
add_sep
add "$(F $DIM)$(date +%H:%M)$R"

# ---------------- assemble final p10k-style block ----------------
# Wrap content in bg=234, close with a fg=234 chevron on default bg.
# No leading padding — apple sits flush at the left edge.
printf '%s' "${BG}${out} ${R}${DEFBG}$(F 234)${PSEP_END}${RST}"
