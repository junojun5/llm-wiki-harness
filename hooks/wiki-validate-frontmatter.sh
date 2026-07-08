#!/usr/bin/env bash
# wiki-validate-frontmatter.sh — wiki/ 하위 .md 쓰기마다 frontmatter 기계 검증. 하네스 스펙 §5-3.
# PostToolUse 가드. 클래스 판정·검증은 validate-frontmatter.sh 단일 출처 — 이 훅은 얇은 wrapper.
# 위반 시에만 stderr 출력 + exit 2 (에이전트가 피드백 받아 즉시 수정). 위반 0 → 노이즈 0.
set -u

# --- vault resolution: §3-2 resolver 재사용 ---
RESOLVED="$(bash "$HOME/.llm-wiki/scripts/resolve-vault.sh" 2>/dev/null)" || exit 0
VAULT_PATH="$(printf '%s\n' "$RESOLVED" | sed -n 's/^VAULT_PATH=//p')"
WIKI_DIR="$(printf '%s\n' "$RESOLVED" | sed -n 's/^WIKI_DIR=//p')"
[ -n "$VAULT_PATH" ] && [ -n "$WIKI_DIR" ] || exit 0

INPUT="$(cat)"
TARGET="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
ti = d.get("tool_input") or d.get("input") or {}
print(ti.get("file_path") or ti.get("path") or ti.get("filePath") or "" if isinstance(ti, dict) else "")
')"

# 볼트 wiki/ 하위 .md가 아니면 통과
case "$TARGET" in
  "$VAULT_PATH/$WIKI_DIR"/*.md) ;;
  *) exit 0 ;;
esac

# 클래스 판정(①②③)·검증은 validator 단일 출처 — 클래스 ③(index/log/hot·decisions·backlog)은
# validator가 통과 처리하므로 훅에서 파일명 예외를 따로 두지 않는다 (§3-3, drift 방지).
bash "$HOME/.llm-wiki/scripts/validate-frontmatter.sh" "$TARGET" >&2 || exit 2
exit 0
