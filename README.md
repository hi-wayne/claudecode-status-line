# claudecode-status-line

A 3-line status bar for [Claude Code](https://claude.ai/code) showing model info, context usage, rate limits, cost, and token details.

## Preview

```
claude-sonnet-4-6 200K | my-project git:(main*) | ⏱ 5s
context ██░░░░░░░░ 15% │ usage ███░░░░░░░ 30% │ weekly ████░░░░░░ 45%
$0.0500 | cache 36% | in: 45.0K  out: 3.2K | api wait 2s (40%) | cur 1.2K in  800 read  200 write
```

### Line 1 — Session info
| Field | Description |
|---|---|
| Model name | e.g. `claude-sonnet-4-6` |
| Context size | `200K` or `1M` |
| Version | Claude Code version |
| Repo + branch | clickable link if remote exists, `git:(branch*)` |
| Duration | total session wall time |
| Lines changed | `+N / -N` when files are edited |
| Agent | subagent name when running in agent mode |
| Vim mode | `NOR` / `INS` when vim mode is active |

### Line 2 — Usage bars
| Bar | Description | Colors |
|---|---|---|
| `context` | context window used % | green < 70%, yellow 70–84%, red ≥ 85% |
| `usage` | 5-hour rate limit % | blue < 75%, magenta 75–89%, red ≥ 90% |
| `weekly` | 7-day rate limit % | same thresholds as above |

Rate limit bars include a reset countdown when data is available.

### Line 3 — Cost & tokens
| Field | Description |
|---|---|
| `$0.0000` | cumulative session cost |
| `cache N%` | cache hit rate for current turn |
| `in: X  out: Y` | cumulative session token counts |
| `api wait Ns (N%)` | API latency and share of total time |
| `cur … in … read … write` | current-turn token breakdown |

## Requirements

- macOS or Linux
- [Claude Code](https://claude.ai/code) ≥ 1.x
- `jq` — `brew install jq` (macOS) or `apt install jq` (Linux)

## Install

```bash
git clone git@github.com:hi-wayne/claudecode-status-line.git
cd claudecode-status-line
bash install.sh
```

Then **restart Claude Code**.

## Uninstall

Remove the `statusLine` entry from `~/.claude/settings.json`:

```bash
jq 'del(.statusLine)' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```
