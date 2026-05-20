#!/bin/bash
# Unified statusline: model + git + cost + context + tools + agent + todo + sys + config + perf
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
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // empty')
SESSION_ID_JSON=$(echo "$input" | jq -r '.session_id // empty')

# ── Colors ────────────────────────────────────────────────────
RESET='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'
RED='\033[31m'; MAGENTA='\033[35m'; BLUE='\033[34m'
WHITE='\033[37m'
BRIGHT_BLUE='\033[94m'
BRIGHT_MAGENTA='\033[95m'
ORANGE='\033[38;5;208m'

SEP="${DIM} | ${RESET}"
VSEP="${DIM} │ ${RESET}"

# ── Helper: context bar color ─────────────────────────────────
ctx_color() {
  local val=${1:-0}
  if [ "$val" -ge 85 ]; then echo "$RED"
  elif [ "$val" -ge 70 ]; then echo "$YELLOW"
  else echo "$GREEN"; fi
}

# ── Helper: quota bar color ───────────────────────────────────
quota_color() {
  local val=${1:-0}
  if [ "$val" -ge 90 ]; then echo "$RED"
  elif [ "$val" -ge 75 ]; then echo "$BRIGHT_MAGENTA"
  else echo "$BRIGHT_BLUE"; fi
}

# ── Helper: render bar ────────────────────────────────────────
render_bar() {
  local pct=$1 width=$2 color=$3
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar="" i
  for i in $(seq 1 $filled); do bar="${bar}${color}█${RESET}"; done
  for i in $(seq 1 $empty);  do bar="${bar}${DIM}░${RESET}"; done
  echo "$bar"
}

# ── Helper: format duration from ms ──────────────────────────
fmt_dur() {
  local ms=$1
  local s=$(( ms / 1000 ))
  local h=$(( s / 3600 )) m=$(( (s % 3600) / 60 )) sec=$(( s % 60 ))
  if   [ "$h" -gt 0 ]; then printf "%dh %02dm" "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf "%dm %02ds" "$m" "$sec"
  else printf "%ds" "$sec"; fi
}

# ── Helper: countdown from epoch seconds ─────────────────────
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

# ── Wall-clock session duration ───────────────────────────────
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-${SESSION_ID_JSON:-default}}"
SESSION_START_FILE="/tmp/.claude-session-${SESSION_ID}"
if [ ! -f "$SESSION_START_FILE" ]; then
  date +%s > "$SESSION_START_FILE"
fi
SESSION_START=$(cat "$SESSION_START_FILE")
ELAPSED_S=$(( $(date +%s) - SESSION_START ))

# ── Auth info (cached 5 min) ──────────────────────────────────
AUTH_CACHE="/tmp/.claude-auth-cache"
AUTH_JSON=""
if [ -f "$AUTH_CACHE" ] && [ $(( $(date +%s) - $(stat -f %m "$AUTH_CACHE" 2>/dev/null || echo 0) )) -lt 300 ]; then
  AUTH_JSON=$(cat "$AUTH_CACHE")
else
  AUTH_JSON=$(claude auth status 2>/dev/null) && echo "$AUTH_JSON" > "$AUTH_CACHE"
fi
AUTH_EMAIL=$(echo "$AUTH_JSON" | jq -r '.email // empty')
AUTH_METHOD=$(echo "$AUTH_JSON" | jq -r '.authMethod // empty')
AUTH_SUB=$(echo "$AUTH_JSON" | jq -r '.subscriptionType // empty')
AUTH_BASE_URL=$(echo "$AUTH_JSON" | jq -r '.baseUrl // .apiUrl // empty')

# ── Transcript parsing (tool activity + agent, cached on mtime) ──
TOOL_ACTIVITY=""
AGENT_LAST=""

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  TC="/tmp/.claude-trans-${SESSION_ID}"
  TRANS_MTIME=$(stat -f %m "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)
  CACHE_MTIME=$(cat "${TC}.mtime" 2>/dev/null || echo -1)

  if [ "$TRANS_MTIME" != "$CACHE_MTIME" ]; then
    TOOLS_RAW=$(tail -150 "$TRANSCRIPT_PATH" | \
      jq -r 'try (select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name)' 2>/dev/null)

    TOOL_PARTS=()
    while read -r count name; do
      [ -n "$name" ] && TOOL_PARTS+=("${name}×${count}")
    done < <(printf '%s\n' "$TOOLS_RAW" | grep -v '^$' | sort | uniq -c | sort -rn | head -7)
    TOOL_ACTIVITY=$(IFS=" | "; echo "${TOOL_PARTS[*]}")

    AGENT_LAST=$(tail -150 "$TRANSCRIPT_PATH" | \
      jq -r 'try (select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Agent") | "\(.input.subagent_type // "agent"): \(.input.description // "")")' 2>/dev/null | \
      tail -1 | cut -c1-70)

    printf '%s\n' "$TOOL_ACTIVITY" > "${TC}.tools"
    printf '%s\n' "$AGENT_LAST"    > "${TC}.agent"
    printf '%s\n' "$TRANS_MTIME"  > "${TC}.mtime"
  else
    TOOL_ACTIVITY=$(cat "${TC}.tools" 2>/dev/null)
    AGENT_LAST=$(cat "${TC}.agent" 2>/dev/null)
  fi
fi

# ── Todo (current session) ────────────────────────────────────
TODO_FILE="$HOME/.claude/todos/${SESSION_ID}-agent-${SESSION_ID}.json"
TODO_INFO=""
if [ -f "$TODO_FILE" ]; then
  TODO_TOTAL=$(jq 'length' "$TODO_FILE" 2>/dev/null || echo 0)
  TODO_DONE=$(jq '[.[] | select(.status=="completed")] | length' "$TODO_FILE" 2>/dev/null || echo 0)
  if [ "${TODO_TOTAL:-0}" -gt 0 ]; then
    TODO_NEXT=$(jq -r 'map(select(.status!="completed")) | first | .activeForm // .content // empty' "$TODO_FILE" 2>/dev/null)
    TODO_INFO="${TODO_DONE}/${TODO_TOTAL}"
    [ -n "$TODO_NEXT" ] && TODO_INFO="${TODO_INFO} ▸ $(echo "$TODO_NEXT" | cut -c1-40)"
  fi
fi

# ── System memory (macOS) ─────────────────────────────────────
MEM_USED_GB=$(vm_stat | awk '
  /page size of ([0-9]+)/        { ps = $8+0 }
  /^Pages active:/               { a = $3+0 }
  /^Pages wired down:/           { w = $4+0 }
  /^Pages occupied by compressor:/ { c = $5+0 }
  END { printf "%.1f", (a+w+c)*ps/1073741824 }
')
MEM_TOTAL_GB=$(echo "scale=0; $(sysctl -n hw.memsize) / 1073741824" | bc)

# ── Config counts ─────────────────────────────────────────────
CLAUDE_MD_COUNT=$(find "${DIR:-.}" -maxdepth 3 -name "CLAUDE.md" 2>/dev/null | wc -l | tr -d ' ')
MCP_COUNT=$(jq '(.mcpServers // {}) | keys | length' "$HOME/.claude/settings.json" 2>/dev/null || echo 0)
HOOKS_COUNT=$(jq '(.hooks // {}) | keys | length' "$HOME/.claude/settings.json" 2>/dev/null || echo 0)

# ── Performance: tokens/s ─────────────────────────────────────
TOK_PER_S=""
if [ "${ELAPSED_S:-0}" -gt 5 ] && [ -n "$TOTAL_OUT" ] && [ "$TOTAL_OUT" != "null" ] && [ "$TOTAL_OUT" != "0" ]; then
  TOK_PER_S=$(echo "scale=0; $TOTAL_OUT / $ELAPSED_S" | bc 2>/dev/null)
fi

# ══════════════════════════════════════════════════════════════
# LINE 1: Auth + Model + Dir + Git + Lines diff + Vim
# ══════════════════════════════════════════════════════════════
L1=""

# Auth
if [ -n "$ANTHROPIC_BASE_URL" ]; then
  L1="${DIM}api key${RESET}${SEP}${CYAN}${ANTHROPIC_BASE_URL}${RESET}"
elif [ -n "$AUTH_BASE_URL" ]; then
  L1="${DIM}api key${RESET}${SEP}${CYAN}${AUTH_BASE_URL}${RESET}"
elif [ -n "$AUTH_EMAIL" ]; then
  L1="${DIM}claude.ai${RESET}${SEP}${CYAN}${AUTH_EMAIL}${RESET}"
  [ -n "$AUTH_SUB" ] && L1="${L1}${SEP}${GREEN}${AUTH_SUB}${RESET}"
fi

# Model + context size + version
MODEL_PART="${CYAN}${BOLD}${MODEL}${RESET}"
[ -n "$CTX_LABEL" ] && MODEL_PART="${MODEL_PART} ${CTX_LABEL}"
[ -n "$VERSION" ]   && MODEL_PART="${MODEL_PART} ${DIM}v${VERSION}${RESET}"
[ -n "$L1" ] && L1="${L1}${SEP}${MODEL_PART}" || L1="$MODEL_PART"

# Dir + Git
if [ -n "$BRANCH" ]; then
  L1="${L1}${SEP}${YELLOW}${REPO_LINK}${RESET} ${MAGENTA}git:(${RESET}${CYAN}${BRANCH}${BRIGHT_MAGENTA}${GIT_DIRTY}${RESET}${MAGENTA})${RESET}"
else
  L1="${L1}${SEP}${YELLOW}${REPO_LINK}${RESET}"
fi

# Lines added/removed
if [ -n "$LINES_ADD" ] && [ "$LINES_ADD" != "0" ] && [ "$LINES_ADD" != "null" ]; then
  L1="${L1}${SEP}${GREEN}+${LINES_ADD}${RESET}"
  if [ -n "$LINES_DEL" ] && [ "$LINES_DEL" != "0" ] && [ "$LINES_DEL" != "null" ]; then
    L1="${L1} ${RED}-${LINES_DEL}${RESET}"
  fi
elif [ -n "$LINES_DEL" ] && [ "$LINES_DEL" != "0" ] && [ "$LINES_DEL" != "null" ]; then
  L1="${L1}${SEP}${RED}-${LINES_DEL}${RESET}"
fi

# Vim mode
[ -n "$VIM_MODE" ] && {
  [ "$VIM_MODE" = "NORMAL" ] \
    && L1="${L1}${SEP}${BLUE}${BOLD}NOR${RESET}" \
    || L1="${L1}${SEP}${GREEN}${BOLD}INS${RESET}"
}

# ══════════════════════════════════════════════════════════════
# LINE 2: Cost + Cache + Context bar + Usage quota
# ══════════════════════════════════════════════════════════════
BAR_W=10
COST_FMT=$(printf '$%.4f' "$COST")
L2="${YELLOW}${COST_FMT}${RESET}"

# Cache hit %
if [ "$CUR_INPUT" != "0" ] && [ "$CUR_INPUT" != "null" ]; then
  CACHE_TOTAL=$(( CACHE_READ + CUR_INPUT + CACHE_CREATE ))
  if [ "$CACHE_TOTAL" -gt 0 ]; then
    CACHE_PCT=$(( CACHE_READ * 100 / CACHE_TOTAL ))
    CACHE_C=$(quota_color "$(( 100 - CACHE_PCT ))")
    L2="${L2}${SEP}${DIM}cache${RESET} ${CACHE_C}${CACHE_PCT}%${RESET}"
  fi
fi

# Context bar
CTX_C=$(ctx_color "$PCT")
CTX_BAR=$(render_bar "$PCT" "$BAR_W" "$CTX_C")
L2="${L2}${SEP}${DIM}context${RESET} ${CTX_BAR} ${CTX_C}${PCT}%${RESET}"

# 5h usage quota
if [ -n "$RATE_5H" ] && [ "$RATE_5H" != "null" ]; then
  R5=$(printf "%.0f" "$RATE_5H")
  R5_C=$(quota_color "$R5")
  R5_BAR=$(render_bar "$R5" "$BAR_W" "$R5_C")
  R5_RESET=$(fmt_reset "$RESET_5H")
  USAGE_PART="${R5_BAR} ${R5_C}${R5}%${RESET}"
  [ -n "$R5_RESET" ] && USAGE_PART="${USAGE_PART} ${DIM}(${R5_RESET} / 5h)${RESET}"
  L2="${L2}${VSEP}${DIM}usage${RESET} ${USAGE_PART}"
fi

# 7d usage quota
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
# LINE 3: tok/s + input breakdown + output + api wait
# ══════════════════════════════════════════════════════════════
CUR_FMT=$(fmt_tok "$CUR_INPUT")
CR_FMT=$(fmt_tok "$CACHE_READ")
CW_FMT=$(fmt_tok "$CACHE_CREATE")
IN_FMT=$(fmt_tok "$TOTAL_IN")
OUT_FMT=$(fmt_tok "$TOTAL_OUT")

TOTAL_CUR_IN=$(( CUR_INPUT + CACHE_READ + CACHE_CREATE ))
TOTAL_CUR_FMT=$(fmt_tok "$TOTAL_CUR_IN")

# ── Estimate current turn output via delta ────────────────────
OUT_DELTA_FILE="/tmp/.claude-out-prev-${SESSION_ID}"
PREV_OUT=$(cat "$OUT_DELTA_FILE" 2>/dev/null || echo 0)
CUR_OUT_DELTA=0
if [ -n "$TOTAL_OUT" ] && [ "$TOTAL_OUT" != "null" ] && [ "$TOTAL_OUT" -ge "$PREV_OUT" ]; then
  CUR_OUT_DELTA=$(( TOTAL_OUT - PREV_OUT ))
  echo "$TOTAL_OUT" > "$OUT_DELTA_FILE"
fi
CUR_OUT_FMT=$(fmt_tok "$CUR_OUT_DELTA")

L3=""
[ -n "$TOK_PER_S" ] && L3="${CYAN}${TOK_PER_S}${RESET} ${DIM}tok/s${RESET}${SEP}"

L3="${L3}${DIM}session:${RESET} ${CYAN}${IN_FMT}${RESET} ${DIM}in / ${RESET}${MAGENTA}${OUT_FMT}${RESET} ${DIM}out${RESET}"
L3="${L3}${SEP}${DIM}this turn:${RESET} ${CYAN}${TOTAL_CUR_FMT}${RESET} ${DIM}input:${RESET} ${CUR_FMT}${DIM}(new)${RESET}+${CR_FMT}${DIM}(cached)${RESET}+${CW_FMT}${DIM}(stored)${RESET}  ${MAGENTA}${CUR_OUT_FMT}${RESET} ${DIM}output${RESET}"

API_DUR=$(fmt_dur "$API_DURATION_MS")
if [ "${DURATION_MS:-0}" -gt 0 ] && [ "${API_DURATION_MS:-0}" -gt 0 ]; then
  API_PCT=$(( API_DURATION_MS * 100 / DURATION_MS ))
  L3="${L3}${SEP}${DIM}api wait${RESET} ${CYAN}${API_DUR}${RESET} ${DIM}(${API_PCT}%)${RESET}"
else
  L3="${L3}${SEP}${DIM}api wait${RESET} ${CYAN}${API_DUR}${RESET}"
fi

# ══════════════════════════════════════════════════════════════
# LINE 4: Tool activity
# ══════════════════════════════════════════════════════════════
L4=""
[ -n "$TOOL_ACTIVITY" ] && L4="${DIM}tools${RESET}${SEP}${CYAN}${TOOL_ACTIVITY}${RESET}"

# ══════════════════════════════════════════════════════════════
# LINE 5: Agent info
# ══════════════════════════════════════════════════════════════
L5=""
[ -n "$AGENT" ] && L5="${DIM}agent${RESET}${SEP}${MAGENTA}${AGENT}${RESET}"
if [ -n "$AGENT_LAST" ]; then
  AGENT_LAST_PART="${DIM}last${RESET}${SEP}${MAGENTA}${AGENT_LAST}${RESET}"
  [ -n "$L5" ] && L5="${L5}${VSEP}${AGENT_LAST_PART}" || L5="$AGENT_LAST_PART"
fi

# ══════════════════════════════════════════════════════════════
# LINE 6: Todo
# ══════════════════════════════════════════════════════════════
L6=""
[ -n "$TODO_INFO" ] && L6="${DIM}todo${RESET}${SEP}${YELLOW}${TODO_INFO}${RESET}"

# ══════════════════════════════════════════════════════════════
# LINE 7 (last): Session duration + mem + config
# ══════════════════════════════════════════════════════════════
DUR=$(fmt_dur "$(( ELAPSED_S * 1000 ))")
L7="${DIM}⏱ ${DUR}${RESET}"
L7="${L7}${VSEP}${DIM}mem${RESET} ${GREEN}${MEM_USED_GB}${RESET}${DIM}/${MEM_TOTAL_GB}G${RESET}"
L7="${L7}${VSEP}${DIM}CLAUDE.md${RESET}×${CLAUDE_MD_COUNT} ${DIM}hooks${RESET}×${HOOKS_COUNT} ${DIM}mcps${RESET}×${MCP_COUNT}"

# ── Output ────────────────────────────────────────────────────
echo -e "$L1"
echo -e "$L2"
echo -e "$L3"
[ -n "$L4" ] && echo -e "$L4"
[ -n "$L5" ] && echo -e "$L5"
[ -n "$L6" ] && echo -e "$L6"
echo -e "$L7"
