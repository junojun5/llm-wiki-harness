#!/usr/bin/env bash
# wiki-protect-raw.sh [platform] — raw/ 수정 차단(삭제는 허용). 하네스 스펙 §5-2.
# PreToolUse 가드. 글로벌 배치 — 실제 볼트를 §3-2 resolver로 resolve (별도 구현 금지).
# resolver 실패(볼트 없음/무효) → 조용히 통과(무관 프로젝트 오탐 방지).
# 차단 신호는 플랫폼별: claude|codex → stderr + exit 2 ; cursor → stdout {"permission":"deny"} + exit 0.
# ⚠️ accident-prevention 수준: rm 복합 우회·파이프 간접 쓰기·COMMAND 문자열 안의 상대경로는
#    비목표(§5-2 알려진 한계). 페이로드 계약은 §5-4 실측 표 + tests/fixtures/ 골든 픽스처.
set -u
PLATFORM="${1:-claude}"
MSG="raw/는 읽기 전용입니다 (수정 금지). 삭제는 wiki-lint --fix를 경유하세요."

# --- vault resolution: §3-2 resolver 재사용 ---
# resolver 실패 → 조용히 통과. **exit 7(E_NO_RUNTIME, python3 부재)도 포함하며 의도된 것이다**
# (§5-2). ① 관할: 이 훅은 글로벌이라 볼트를 안 쓰는 프로젝트에서 resolver가 항상 실패하므로,
# 실패를 차단으로 해석하면 무관한 모든 작업의 쓰기가 막힌다 — 게다가 지킬 대상인
# RAW_ABS 자체가 resolve 없이는 정의되지 않는다. ② 판정 불능: 아래 경로 판정 블록이 python3라
# python3가 없으면 "이 쓰기가 raw/를 향하는가"를 가릴 수 없고, 차단으로 돌리면 raw/만 골라
# 막는 게 아니라 볼트 안 전체를 막는 것이 된다. 셸로 JSON 판정을 재구현하는 길도 기각
# (두 훅의 추출 규칙 동일성 유지 부담 — 아래 주석 참조).
# 대신 python3 부재 고지는 hooks/session-start가 세션당 1회 담당한다 —
# **강등 지점과 고지 지점을 분리**하는 것이 이 설계의 요지다. 여기서 다시 발견하지 말 것.
RESOLVED="$(bash "$HOME/.llm-wiki/scripts/resolve-vault.sh" 2>/dev/null)" || exit 0
VAULT_ROOT="$(printf '%s\n' "$RESOLVED" | sed -n 's/^VAULT_PATH=//p')"
RAW_DIR="$(printf '%s\n' "$RESOLVED" | sed -n 's/^RAW_DIR=//p')"
[ -n "$VAULT_ROOT" ] && [ -n "$RAW_DIR" ] || exit 0
RAW_ABS="$VAULT_ROOT/$RAW_DIR"

# 판정은 python3 단일 블록에서 수행한다(jq 비의존). 추출 규칙은 §5-2·§5-3 공통 —
# hooks/wiki-validate-frontmatter.sh의 대응 블록과 **반드시 동일**하게 유지한다.
# 한쪽 탐색 범위만 좁으면 그쪽 검증이 조용히 죽는다(Codex apply_patch에서 실제 발생).
# 다중 라인 command(apply_patch 패치 본문)를 bash 변수로 실어 나르지 않기 위해
# allow/block 결정만 한 줄로 돌려받는다.
# PYTHONUTF8=1은 §3-9 계약 — env(RAW_ABS)와 stdin(페이로드 경로) 양쪽에 한글이 올 수 있고,
# 비UTF-8 locale에서는 두 디코딩 방식이 섞여 **경로 비교가 어긋난다**(raw/를 못 알아본다).
DECISION="$(printf '%s' "$(cat)" | RAW_ABS="$RAW_ABS" BASE_FALLBACK="$PWD" PYTHONUTF8=1 python3 -c '
import json, os, re, sys

raw_abs = os.environ["RAW_ABS"]
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

# 기준 디렉토리 — 상대경로 해석 기준. Cursor는 cwd 대신 workspace_roots[]를 준다 (§5-4).
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

# apply_patch(Codex)는 file_path가 없다 — 패치 본문에서 대상 경로를 뽑는다 (§5-4)
if not target and tool == "apply_patch":
    m = re.search(r"^\*\*\* (?:Add File|Update File|Delete File|Move to): (.+)$", command, re.M)
    if m:
        target = m.group(1).strip()

# 상대경로 → 절대경로 (에이전트는 대부분 cwd 상대경로를 쓴다 — §5-4)
if target:
    if not os.path.isabs(target):
        target = os.path.join(base, target)
    target = os.path.normpath(target)

# raw/ 를 건드리지 않으면 통과. COMMAND는 절대경로 부분문자열만 본다
# (셸 문법 전면 해석은 비목표 — §5-2 알려진 한계).
hit = target == raw_abs or target.startswith(raw_abs + os.sep) or (raw_abs in command)
if not hit:
    print("allow"); sys.exit(0)

# 삭제(cleanup 정책)는 허용 — 안전 판단은 wiki-lint --fix가 수행
if re.search(r"(?:^|[\s:;&|])rm\s", command):
    print("allow"); sys.exit(0)

print("block")
')"

[ "$DECISION" = "block" ] || exit 0

# 차단 신호 (2026-07-31 실측 확정 — §5-2)
case "$PLATFORM" in
  cursor)
    # PYTHONUTF8=1 없으면 한국어 MSG 직렬화가 비UTF-8 locale의 stdout에서 UnicodeEncodeError로
    # 죽어 **deny가 조용히 사라진다**(§3-9. 2026-08-04 Windows CI 실측: cp1252에서 빈 출력).
    PYTHONUTF8=1 python3 -c 'import json,sys; print(json.dumps({"permission":"deny","user_message":sys.argv[1]}, ensure_ascii=False))' "$MSG"
    exit 0 ;;
  *)  # claude | codex
    printf '%s\n' "$MSG" >&2
    exit 2 ;;
esac
