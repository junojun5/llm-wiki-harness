#!/usr/bin/env bash
# raw/ 수정 차단(삭제는 허용). resolver 실패는 통과. claude|codex는 stderr+exit 2, cursor는 deny JSON+exit 0.
# COMMAND 안 상대경로·파이프 간접 쓰기는 보지 않는다.
set -u
PLATFORM="${1:-claude}"
MSG="raw/는 읽기 전용입니다 (수정 금지). 삭제는 wiki-lint --fix를 경유하세요."

# resolver 실패(python3 부재 포함)는 통과. 막으면 볼트 밖 작업까지 막히고, 고지는 session-start가 한다.
RESOLVED="$(bash "$HOME/.llm-wiki/scripts/resolve-vault.sh" 2>/dev/null)" || exit 0
VAULT_ROOT="$(printf '%s\n' "$RESOLVED" | sed -n 's/^VAULT_PATH=//p')"
RAW_DIR="$(printf '%s\n' "$RESOLVED" | sed -n 's/^RAW_DIR=//p')"
[ -n "$VAULT_ROOT" ] && [ -n "$RAW_DIR" ] || exit 0
RAW_ABS="$VAULT_ROOT/$RAW_DIR"

# 판정만 한 줄로 받는다. 필드 탐색은 wiki-validate-frontmatter.sh와 같게 유지한다. 경로는 UTF-8.
DECISION="$(printf '%s' "$(cat)" | RAW_ABS="$RAW_ABS" BASE_FALLBACK="$PWD" PYTHONUTF8=1 python3 -c '
import json, os, re, sys

# 비교 전 슬래시·대소문자를 맞춘다. 안 맞추면 Windows에서 raw/ 쓰기가 통과한다.
def _norm(p):
    return os.path.normcase(os.path.normpath(p)).replace("\\", "/")

raw_abs_literal = os.environ["RAW_ABS"]   # COMMAND 부분문자열 검사는 **원문**으로 한다
raw_abs = _norm(raw_abs_literal)
try:
    d = json.load(sys.stdin)
except Exception:
    print("allow"); sys.exit(0)
if not isinstance(d, dict):
    print("allow"); sys.exit(0)

tool = str(d.get("tool_name") or "")
ti = d.get("tool_input") or d.get("input") or d.get("arguments") or {}
if not isinstance(ti, dict):
    ti = {}

# Cursor는 cwd 대신 workspace_roots[0]을 준다.
roots = d.get("workspace_roots")
root0 = roots[0] if isinstance(roots, list) and roots else ""
base = d.get("cwd") or ti.get("cwd") or root0 or os.environ["BASE_FALLBACK"]

def pick(*keys):
    for k in keys:
        v = ti.get(k)
        if v:
            return str(v)
    return ""

# 타깃 후보 — 도구·플랫폼별 필드명 차이를 모두 흡수
target = pick("file_path", "path", "filePath", "file")
command = pick("command", "cmd")

# apply_patch는 file_path가 없다. 패치 본문에서 경로를 뽑는다.
if not target and tool == "apply_patch":
    m = re.search(r"^\*\*\* (?:Add File|Update File|Delete File|Move to): (.+)$", command, re.M)
    if m:
        target = m.group(1).strip()

# 상대경로는 base 기준으로 절대화한다.
if target:
    if not os.path.isabs(target):
        target = os.path.join(base, target)
    target = _norm(target)

# COMMAND는 절대경로 부분문자열만 본다. 구분자는 _norm이 맞춘 "/"다.
hit = target == raw_abs or target.startswith(raw_abs + "/") or (raw_abs_literal in command)
if not hit:
    print("allow"); sys.exit(0)

# 삭제(cleanup 정책)는 허용 — 안전 판단은 wiki-lint --fix가 수행
if re.search(r"(?:^|[\s:;&|])rm\s", command):
    print("allow"); sys.exit(0)

print("block")
')"

[ "$DECISION" = "block" ] || exit 0

case "$PLATFORM" in
  cursor)
    # 한국어 deny JSON은 UTF-8이 아니면 빈 출력이 된다.
    PYTHONUTF8=1 python3 -c 'import json,sys; print(json.dumps({"permission":"deny","user_message":sys.argv[1]}, ensure_ascii=False))' "$MSG"
    exit 0 ;;
  *)  # claude | codex
    printf '%s\n' "$MSG" >&2
    exit 2 ;;
esac
