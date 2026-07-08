#!/usr/bin/env bash
# wiki-protect-raw.sh [platform] — raw/ 수정 차단(삭제는 허용). 하네스 스펙 §5-2.
# PreToolUse 가드. 글로벌 배치 — 실제 볼트를 §3-2 resolver로 resolve (별도 구현 금지).
# resolver 실패(볼트 없음/무효) → 조용히 통과(무관 프로젝트 오탐 방지).
# 차단 신호는 플랫폼별: claude|codex → stderr + exit 2 ; cursor → stdout {"permission":"deny"} + exit 0.
# ⚠️ accident-prevention 수준: rm 복합 우회·파이프 간접 쓰기는 비목표(§5-2). codex/cursor stdin
#    스키마는 §9-6 probe fixture로 최종 검증 대상 — 아래 다중 키 탐색으로 보수적 커버.
set -u
PLATFORM="${1:-claude}"
MSG="raw/는 읽기 전용입니다 (수정 금지). 삭제는 wiki-lint --fix를 경유하세요."

# --- vault resolution: §3-2 resolver 재사용 ---
RESOLVED="$(bash "$HOME/.llm-wiki/scripts/resolve-vault.sh" 2>/dev/null)" || exit 0
VAULT_ROOT="$(printf '%s\n' "$RESOLVED" | sed -n 's/^VAULT_PATH=//p')"
RAW_DIR="$(printf '%s\n' "$RESOLVED" | sed -n 's/^RAW_DIR=//p')"
[ -n "$VAULT_ROOT" ] && [ -n "$RAW_DIR" ] || exit 0
RAW_ABS="$VAULT_ROOT/$RAW_DIR"

INPUT="$(cat)"
# stdin JSON에서 대상 경로·명령 추출 (jq 비의존 — python3). 플랫폼별 필드명 차이를 다중 키로 흡수.
read -r TARGET COMMAND <<EOF
$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: print(" "); sys.exit(0)
ti = d.get("tool_input") or d.get("input") or d.get("arguments") or {}
def first(*ks):
    for k in ks:
        v = ti.get(k) if isinstance(ti, dict) else None
        if v: return str(v).replace(" ", "\\u0020")
    return ""
target = first("file_path", "path", "filePath", "file")
command = first("command", "cmd")
print((target or "_") + " " + (command or "_"))
')
EOF
# placeholder 복원
[ "$TARGET" = "_" ] && TARGET=""
[ "$COMMAND" = "_" ] && COMMAND=""
TARGET="${TARGET//\\u0020/ }"; COMMAND="${COMMAND//\\u0020/ }"

# raw/ 를 건드리지 않으면 통과
if [[ "$TARGET" != "$RAW_ABS"* ]] && [[ "$COMMAND" != *"$RAW_ABS"* ]]; then
  exit 0
fi

# 삭제(cleanup 정책)는 허용 — 안전 판단은 wiki-lint --fix
if [[ "$COMMAND" =~ (^|[[:space:]:\;\&\|])rm[[:space:]] ]]; then
  exit 0
fi

# 차단
case "$PLATFORM" in
  cursor)
    python3 -c 'import json,sys; print(json.dumps({"permission":"deny","user_message":sys.argv[1]}, ensure_ascii=False))' "$MSG"
    exit 0 ;;
  *)  # claude | codex
    printf '%s\n' "$MSG" >&2
    exit 2 ;;
esac
