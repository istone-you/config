#!/usr/bin/env bash
# 自作の最小テストランナー(プラグイン不使用)。tests/*_spec.luaをnvim -lで
# 個別プロセスとして順に実行し、exit codeで合否判定する。
# 使い方: nvim/tests/run.sh [パターン]  例: nvim/tests/run.sh explorer
set -uo pipefail
cd "$(dirname "$0")/.."   # -> nvim/
NVIM_DIR="$(pwd)"
TESTS_DIR="$NVIM_DIR/tests"
PATTERN="${1:-}"

# 端末に出す時だけ色を付ける(パイプ/リダイレクト先がファイル等の時は無効化)
if [ -t 1 ]; then
  C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'; C_CYAN=$'\033[0;36m'
  C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_RED=''; C_GREEN=''; C_CYAN=''; C_BOLD=''; C_RESET=''
fi

# ok/FAILの行と各ファイルの集計行に色を付ける(自作ハーネスのprint出力をそのまま
# 色付けするだけで、パース対象の数値自体はBASH_REMATCHで色付け前の$outから取るので
# 集計ロジックには影響しない)
colorize() {
  sed \
    -e "s/^  ok   - /  ${C_GREEN}ok${C_RESET}   - /" \
    -e "s/^  FAIL - /  ${C_RED}${C_BOLD}FAIL${C_RESET} - /" \
    -e "s/^\([0-9]* total, \)\([0-9]* passed\)\(, \)\([0-9]* failed\)$/\1${C_GREEN}\2${C_RESET}\3${C_RED}\4${C_RESET}/"
}

pass=0
fail=0
failed_files=()
total_cases=0
passed_cases=0
failed_cases=0

for f in "$TESTS_DIR"/*_spec.lua; do
  base="$(basename "$f")"
  if [ -n "$PATTERN" ] && [[ "$base" != *"$PATTERN"* ]]; then
    continue
  fi
  echo "${C_CYAN}${C_BOLD}── $base ──${C_RESET}"
  # 出力を捕まえつつそのまま表示する(ファイルごとの"N total, N passed, N failed"を
  # 集計してスイート全体の合計もまとめて出すため)
  out="$(nvim -u NONE --cmd "set rtp+=$NVIM_DIR" --cmd "lua TESTS_DIR = '$TESTS_DIR'" -l "$f" 2>&1)"
  code=$?
  echo "$out" | colorize
  if [[ "$out" =~ ([0-9]+)\ total,\ ([0-9]+)\ passed,\ ([0-9]+)\ failed ]]; then
    total_cases=$((total_cases + ${BASH_REMATCH[1]}))
    passed_cases=$((passed_cases + ${BASH_REMATCH[2]}))
    failed_cases=$((failed_cases + ${BASH_REMATCH[3]}))
  fi
  if [ "$code" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed_files+=("$base")
  fi
  echo
  sleep 0.2 # 前specの非同期処理(gitサブプロセス等)が完全に片付く猶予を少し置く
done

echo "======================================"
file_color="$C_GREEN"; [ "$fail" -gt 0 ] && file_color="$C_RED"
case_color="$C_GREEN"; [ "$failed_cases" -gt 0 ] && case_color="$C_RED"
echo "files: $((pass + fail))  ${C_GREEN}passed: $pass${C_RESET}  ${file_color}failed: $fail${C_RESET}"
echo "cases: $total_cases  ${C_GREEN}passed: $passed_cases${C_RESET}  ${case_color}failed: $failed_cases${C_RESET}"
if [ ${#failed_files[@]} -gt 0 ]; then
  echo "${C_RED}${C_BOLD}failed files:${C_RESET}"
  for f in "${failed_files[@]}"; do echo "  ${C_RED}- $f${C_RESET}"; done
  exit 1
fi
