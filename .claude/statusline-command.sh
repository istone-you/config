#!/bin/bash

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
effort=$(echo "$input" | jq -r '.effort.level // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

render_bar() {
  local pct="$1"
  local total=15
  local rounded
  printf -v rounded "%.0f" "$pct"
  local filled=$(( rounded * total / 100 ))
  [ "$filled" -gt "$total" ] && filled=$total
  local empty=$(( total - filled ))
  local bar=""
  for (( i=0; i<filled; i++ )); do bar="${bar}█"; done
  for (( i=0; i<empty; i++ )); do bar="${bar}░"; done
  printf '%s' "$bar"
}

# カレントディレクトリ（ホームディレクトリを ~ に短縮）
short_cwd="${cwd/#$HOME/~}"

# Gitブランチ名（ロックファイルを避けるため GIT_OPTIONAL_LOCKS=0 を使用）
branch=""
if git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null); then
  branch="$git_branch"
elif git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-parse --short HEAD 2>/dev/null); then
  branch="${git_branch}(detached)"
fi

# git 行数差分（+追加行数 -削除行数）
git_changes=""
if [ -n "$branch" ]; then
  diff_stat=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" diff --numstat 2>/dev/null)
  diff_cached=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" diff --cached --numstat 2>/dev/null)
  combined=$(printf '%s\n%s' "$diff_stat" "$diff_cached")

  ins=0
  del=0
  while IFS=$'\t' read -r a d _; do
    [[ "$a" =~ ^[0-9]+$ ]] && ins=$(( ins + a ))
    [[ "$d" =~ ^[0-9]+$ ]] && del=$(( del + d ))
  done <<< "$combined"

  parts_git=()
  [ "$ins" -gt 0 ] && parts_git+=("+${ins}")
  [ "$del" -gt 0 ] && parts_git+=("-${del}")
  if [ ${#parts_git[@]} -gt 0 ]; then
    git_changes=" $(IFS=' '; echo "${parts_git[*]}")"
  fi
fi

# コンテキストプログレスバー（15マス）
ctx_bar=""
ctx_pct_label=""
if [ -n "$used_pct" ]; then
  printf -v used_rounded "%.0f" "$used_pct"
  ctx_bar=$(render_bar "$used_pct")
  ctx_pct_label="${used_rounded}%"
fi

# Line 1: <cwd> <branch><changes> <model>（スペース区切り）
line1="${short_cwd}"
if [ -n "$branch" ]; then
  line1="${line1} ${branch}${git_changes}"
fi
if [ -n "$model" ]; then
  model_label="$model"
  [ -n "$effort" ] && model_label="${model_label} (${effort})"
  line1="${line1} ${model_label}"
fi

# Line 2: Context: <bar> <pct> │ 5h: <bar> <pct> │ 7d: <bar> <pct>
if [ -n "$ctx_bar" ]; then
  line2="Context: ${ctx_bar} ${ctx_pct_label}"
else
  line2="Context: ░░░░░░░░░░░░░░░ -"
fi
if [ -n "$five_hour_pct" ]; then
  printf -v five_hour_rounded "%.0f" "$five_hour_pct"
  line2="${line2} │ 5h: $(render_bar "$five_hour_pct") ${five_hour_rounded}%"
else
  line2="${line2} │ 5h: ░░░░░░░░░░░░░░░ -"
fi
if [ -n "$seven_day_pct" ]; then
  printf -v seven_day_rounded "%.0f" "$seven_day_pct"
  line2="${line2} │ 7d: $(render_bar "$seven_day_pct") ${seven_day_rounded}%"
else
  line2="${line2} │ 7d: ░░░░░░░░░░░░░░░ -"
fi

printf '%s\n%s' "$line1" "$line2"
