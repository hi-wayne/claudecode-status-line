#!/bin/bash
# Unified statusline: statusline.sh layout + claude-hud bar/usage style
input=$(cat)

# ── Parse JSON ────────────────────────────────────────────────
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
VERSION=$(echo "$input" | jq -r '.version // empty')
DIR=$(echo "$input" | jq -r '.workspace.current_dir // empty')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
API_DURATION_MS=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
LINES_ADD=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
LINES_DEL=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')
VIM_MODE=$(echo "$input" | jq -r '.vim.mode // empty')
AGENT=$(echo "$input" | jq -r '.agent.name // empty')
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null | cut -d. -f1)
PCT=${PCT:-0}
CACHE_READ=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
CACHE_CREATE=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
CUR_INPUT=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
TOTAL_IN=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
TOTAL_OUT=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty')
RATE_5H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
RATE_7D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
RESET_5H=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
RESET_7D=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# ── Colors ────────────────────────────────────────────────────
RESET='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'
RED='\033[31m'; MAGENTA='\033[35m'; BLUE='\033[34m'
WHITE='\033[37m'
BRIGHT_BLUE='\033[94m'     # claude-hud quota color (normal)
BRIGHT_MAGENTA='\033[95m'  # claude-hud quota color (warning)
ORANGE='\033[38;5;208m'    # claude-hud label color

SEP="${DIM} | ${RESET}"
VSEP="${DIM} │ ${RESET}"   # vertical separator (between context and usage)

# ── Helper: context bar color (claude-hud thresholds) ─────────
# green < 70%, yellow 70-84%, red >= 85%
ctx_color() {
  local val=${1:-0}
  if [ "$val" -ge 85 ]; then echo "$RED"
  elif [ "$val" -ge 70 ]; then echo "$YELLOW"
  else echo "$GREEN"; fi
}

# ── Helper: quota bar color (claude-hud thresholds) ───────────
# brightBlue < 75%, brightMagenta 75-89%, red >= 90%
quota_color() {
  local val=${1:-0}
  if [ "$val" -ge 90 ]; then echo "$RED"
  elif [ "$val" -ge 75 ]; then echo "$BRIGHT_MAGENTA"
  else echo "$BRIGHT_BLUE"; fi
}

# ── Helper: render bar with █ / ░ (claude-hud style) ──────────
# $1=pct $2=width $3=color
render_bar() {
  local pct=$1 width=$2 color=$3
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar=""
  local i
  for i in $(seq 1 $filled); do bar="${bar}${color}█${RESET}"; done
  for i in $(seq 1 $empty);  do bar="${bar}${DIM}░${RESET}"; done
  echo "$bar"
}

# ── Helper: format duration from ms ───────────────────────────
fmt_dur() {
  local ms=$1
  local s=$(( ms / 1000 ))
  local h=$(( s / 3600 )) m=$(( (s % 3600) / 60 )) sec=$(( s % 60 ))
  if   [ "$h" -gt 0 ]; then printf "%dh %02dm" "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf "%dm %02ds" "$m" "$sec"
  else printf "%ds" "$sec"; fi
}

# ── Helper: countdown from epoch seconds ──────────────────────
fmt_reset() {
  local epoch=$1
  [ -z "$epoch" ] || [ "$epoch" = "null" ] && return
  local now diff
  now=$(date +%s)
  diff=$(( epoch - now ))
  [ "$diff" -le 0 ] && echo "now" && return
  local mins=$(( diff / 60 ))
  if [ "$mins" -lt 60 ]; then
    printf "%dm" "$mins"
  else
    local h=$(( mins / 60 )) m=$(( mins % 60 ))
    if [ "$h" -ge 24 ]; then
      local d=$(( h / 24 )) rh=$(( h % 24 ))
      [ "$rh" -gt 0 ] && printf "%dd %dh" "$d" "$rh" || printf "%dd" "$d"
    else
      [ "$m" -gt 0 ] && printf "%dh %dm" "$h" "$m" || printf "%dh" "$h"
    fi
  fi
}

# ── Helper: format token count ────────────────────────────────
fmt_tok() {
  local t=$1
  [ -z "$t" ] || [ "$t" = "null" ] || [ "$t" = "0" ] && echo "0" && return
  if [ "$t" -ge 1000000 ]; then
    printf "%.1fM" "$(echo "scale=1; $t / 1000000" | bc)"
  elif [ "$t" -ge 1000 ]; then
    printf "%.1fK" "$(echo "scale=1; $t / 1000" | bc)"
  else
    echo "$t"
  fi
}

# ── Git info ──────────────────────────────────────────────────
BRANCH=""
GIT_DIRTY=""
git rev-parse --git-dir > /dev/null 2>&1 && {
  BRANCH="$(git branch --show-current 2>/dev/null)"
  [ -n "$(git status --porcelain 2>/dev/null)" ] && GIT_DIRTY="*"
}

DIR_DISPLAY="${DIR/#$HOME/~}"
REMOTE=$(git remote get-url origin 2>/dev/null \
  | sed 's/git@github.com:/https:\/\/github.com\//' \
  | sed 's/\.git$//')
if [ -n "$REMOTE" ]; then
  REPO_LINK=$(printf '%b' "\e]8;;${REMOTE}\a${DIR_DISPLAY}\e]8;;\a")
else
  REPO_LINK="$DIR_DISPLAY"
fi

# ── Context size label ────────────────────────────────────────
CTX_LABEL=""
if [ -n "$CTX_SIZE" ] && [ "$CTX_SIZE" != "null" ]; then
  [ "$CTX_SIZE" -ge 1000000 ] && CTX_LABEL="${DIM}1M${RESET}" || CTX_LABEL="${DIM}200K${RESET}"
fi

# ══════════════════════════════════════════════════════════════
# LINE 1: Model + version + repo + git + duration + lines + agent + vim
# ══════════════════════════════════════════════════════════════
DUR=$(fmt_dur "$DURATION_MS")

L1="${CYAN}${BOLD}${MODEL}${RESET}"
[ -n "$CTX_LABEL" ] && L1="${L1} ${CTX_LABEL}"
[ -n "$VERSION" ]   && L1="${L1} ${DIM}v${VERSION}${RESET}"

# Repo + git (claude-hud style: project git:(branch*))
if [ -n "$BRANCH" ]; then
  L1="${L1}${SEP}${YELLOW}${REPO_LINK}${RESET} ${MAGENTA}git:(${RESET}${CYAN}${BRANCH}${BRIGHT_MAGENTA}${GIT_DIRTY}${RESET}${MAGENTA})${RESET}"
else
  L1="${L1}${SEP}${YELLOW}${REPO_LINK}${RESET}"
fi

# Duration
L1="${L1}${SEP}${DIM}⏱ ${DUR}${RESET}"

# Lines added/removed
if [ -n "$LINES_ADD" ] && [ "$LINES_ADD" != "0" ] && [ "$LINES_ADD" != "null" ]; then
  L1="${L1}${SEP}${GREEN}+${LINES_ADD}${RESET}"
  if [ -n "$LINES_DEL" ] && [ "$LINES_DEL" != "0" ] && [ "$LINES_DEL" != "null" ]; then
    L1="${L1} ${RED}-${LINES_DEL}${RESET}"
  fi
elif [ -n "$LINES_DEL" ] && [ "$LINES_DEL" != "0" ] && [ "$LINES_DEL" != "null" ]; then
  L1="${L1}${SEP}${RED}-${LINES_DEL}${RESET}"
fi

[ -n "$AGENT" ] && L1="${L1}${SEP}${MAGENTA}${AGENT}${RESET}"
[ -n "$VIM_MODE" ] && {
  [ "$VIM_MODE" = "NORMAL" ] \
    && L1="${L1}${SEP}${BLUE}${BOLD}NOR${RESET}" \
    || L1="${L1}${SEP}${GREEN}${BOLD}INS${RESET}"
}

# ══════════════════════════════════════════════════════════════
# LINE 2: context bar │ usage quota bar(s)  — claude-hud style
# ══════════════════════════════════════════════════════════════
BAR_W=10

# Context bar
CTX_C=$(ctx_color "$PCT")
CTX_BAR=$(render_bar "$PCT" "$BAR_W" "$CTX_C")
L2="${DIM}context${RESET} ${CTX_BAR} ${CTX_C}${PCT}%${RESET}"

# Rate limit bars (5h always; weekly only when >= 80%)
if [ -n "$RATE_5H" ] && [ "$RATE_5H" != "null" ]; then
  R5=$(printf "%.0f" "$RATE_5H")
  R5_C=$(quota_color "$R5")
  R5_BAR=$(render_bar "$R5" "$BAR_W" "$R5_C")
  R5_RESET=$(fmt_reset "$RESET_5H")
  USAGE_PART="${R5_BAR} ${R5_C}${R5}%${RESET}"
  [ -n "$R5_RESET" ] && USAGE_PART="${USAGE_PART} ${DIM}(${R5_RESET} / 5h)${RESET}"
  L2="${L2}${VSEP}${DIM}usage${RESET} ${USAGE_PART}"
fi

if [ -n "$RATE_7D" ] && [ "$RATE_7D" != "null" ]; then
  R7=$(printf "%.0f" "$RATE_7D")
  R7_C=$(quota_color "$R7")
  R7_BAR=$(render_bar "$R7" "$BAR_W" "$R7_C")
  R7_RESET=$(fmt_reset "$RESET_7D")
  WEEKLY_PART="${R7_BAR} ${R7_C}${R7}%${RESET}"
  [ -n "$R7_RESET" ] && WEEKLY_PART="${WEEKLY_PART} ${DIM}(${R7_RESET} / weekly)${RESET}"
  L2="${L2}${VSEP}${DIM}weekly${RESET} ${WEEKLY_PART}"
fi

# ══════════════════════════════════════════════════════════════
# LINE 3: Cost + cache hit rate + API wait + cur token detail
# ══════════════════════════════════════════════════════════════
COST_FMT=$(printf '$%.4f' "$COST")
L3="${YELLOW}${COST_FMT}${RESET}"

# Cache hit rate
if [ "$CUR_INPUT" != "0" ] && [ "$CUR_INPUT" != "null" ]; then
  CACHE_TOTAL=$(( CACHE_READ + CUR_INPUT + CACHE_CREATE ))
  if [ "$CACHE_TOTAL" -gt 0 ]; then
    CACHE_PCT=$(( CACHE_READ * 100 / CACHE_TOTAL ))
    # Higher cache = better → invert color
    CACHE_C=$(quota_color "$(( 100 - CACHE_PCT ))")
    L3="${L3}${SEP}${DIM}cache${RESET} ${CACHE_C}${CACHE_PCT}%${RESET}"
  fi
fi

# Total session tokens
IN_FMT=$(fmt_tok "$TOTAL_IN")
OUT_FMT=$(fmt_tok "$TOTAL_OUT")
L3="${L3}${SEP}${DIM}in:${RESET} ${CYAN}${IN_FMT}${RESET} ${DIM}out:${RESET} ${MAGENTA}${OUT_FMT}${RESET}"

# API wait time (always shown)
API_DUR=$(fmt_dur "$API_DURATION_MS")
if [ "${DURATION_MS:-0}" -gt 0 ] && [ "${API_DURATION_MS:-0}" -gt 0 ]; then
  API_PCT=$(( API_DURATION_MS * 100 / DURATION_MS ))
  L3="${L3}${SEP}${DIM}api wait${RESET} ${CYAN}${API_DUR}${RESET} ${DIM}(${API_PCT}%)${RESET}"
else
  L3="${L3}${SEP}${DIM}api wait${RESET} ${CYAN}${API_DUR}${RESET}"
fi

# Current token detail
CUR_FMT=$(fmt_tok "$CUR_INPUT")
CR_FMT=$(fmt_tok "$CACHE_READ")
CW_FMT=$(fmt_tok "$CACHE_CREATE")
L3="${L3}${SEP}${DIM}cur${RESET} ${CUR_FMT} ${DIM}in${RESET}  ${CR_FMT} ${DIM}read${RESET}  ${CW_FMT} ${DIM}write${RESET}"

# ══════════════════════════════════════════════════════════════
# LINE 4: Auth info (cached 5 min)
# ══════════════════════════════════════════════════════════════
AUTH_CACHE="/tmp/.claude-auth-cache"
AUTH_JSON=""
if [ -f "$AUTH_CACHE" ] && [ $(( $(date +%s) - $(stat -f %m "$AUTH_CACHE" 2>/dev/null || echo 0) )) -lt 300 ]; then
  AUTH_JSON=$(cat "$AUTH_CACHE")
else
  AUTH_JSON=$(claude auth status 2>/dev/null) && echo "$AUTH_JSON" > "$AUTH_CACHE"
fi

L4=""
if [ -n "$AUTH_JSON" ]; then
  AUTH_EMAIL=$(echo "$AUTH_JSON" | jq -r '.email // empty')
  AUTH_METHOD=$(echo "$AUTH_JSON" | jq -r '.authMethod // empty')
  AUTH_SUB=$(echo "$AUTH_JSON" | jq -r '.subscriptionType // empty')
  AUTH_PROVIDER=$(echo "$AUTH_JSON" | jq -r '.apiProvider // empty')

  if [ -n "$AUTH_EMAIL" ]; then
    L4="${CYAN}${AUTH_EMAIL}${RESET}"
    [ -n "$AUTH_SUB" ] && L4="${L4}${SEP}${GREEN}${AUTH_SUB}${RESET}"
    [ -n "$AUTH_METHOD" ] && L4="${L4}${SEP}${DIM}${AUTH_METHOD}${RESET}"
  elif [ "$AUTH_PROVIDER" = "apiKey" ] || [ "$AUTH_METHOD" = "apiKey" ]; then
    API_URL=$(echo "$AUTH_JSON" | jq -r '.apiUrl // "https://api.anthropic.com"')
    L4="${DIM}api key${RESET}${SEP}${CYAN}${API_URL}${RESET}"
  fi
fi

# ── Output ────────────────────────────────────────────────────
echo -e "$L1"
echo -e "$L2"
echo -e "$L3"
[ -n "$L4" ] && echo -e "$L4"
