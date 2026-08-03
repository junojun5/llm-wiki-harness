#!/usr/bin/env bash
# wiki-validate-frontmatter.sh — wiki/ 하위 .md 쓰기마다 frontmatter 기계 검증. 하네스 스펙 §5-3.
# PostToolUse 가드. 클래스 판정·검증은 validate-frontmatter.sh 단일 출처 — 이 훅은 얇은 wrapper.
# 위반 시에만 stderr 출력 + exit 2 (에이전트가 피드백 받아 즉시 수정). 위반 0 → 노이즈 0.
set -u

# --- vault resolution: §3-2 resolver 재사용 ---
# resolver 실패 → 조용히 통과. **exit 7(E_NO_RUNTIME, python3 부재)도 포함하며 의도된 것이다**
# — 근거는 §5-2·hooks/wiki-protect-raw.sh와 동일하다(관할: 글로벌 훅이라 무관 프로젝트를
# 막게 된다 / 판정 불능: 아래 경로 추출과 validator 본체가 python3라 검증 자체가 불가능하다).
# python3 부재 고지는 hooks/session-start가 세션당 1회 담당한다. 여기서 다시 발견하지 말 것.
RESOLVED="$(bash "$HOME/.llm-wiki/scripts/resolve-vault.sh" 2>/dev/null)" || exit 0
VAULT_PATH="$(printf '%s\n' "$RESOLVED" | sed -n 's/^VAULT_PATH=//p')"
WIKI_DIR="$(printf '%s\n' "$RESOLVED" | sed -n 's/^WIKI_DIR=//p')"
[ -n "$VAULT_PATH" ] && [ -n "$WIKI_DIR" ] || exit 0

# 타깃 후보 — hooks/wiki-protect-raw.sh(§5-2)와 **동일한 추출 규칙**을 쓴다.
# 두 훅의 필드 탐색 범위가 갈리면 한쪽만 조용히 죽는다 — 실제로 Codex apply_patch에서
# raw 가드는 살고 이 검증만 죽는 사고가 났다(§5-3). 한쪽을 고치면 반대쪽도 함께 고친다.
# 유일한 의도적 차이: Delete File은 추출하지 않는다 — 삭제된 파일은 검증 대상이 아니다
# (없는 파일에 validator를 걸면 정상 삭제가 exit 2로 오보고된다).
# PYTHONUTF8=1은 §3-9 계약 — 페이로드 경로에 한글이 올 수 있고, 비UTF-8 locale에서는
# 디코딩이 어긋나 검증 대상 판정이 조용히 빗나간다.
TARGET="$(printf '%s' "$(cat)" | BASE_FALLBACK="$PWD" PYTHONUTF8=1 python3 -c '
import json, os, re, sys

try:
    d = json.load(sys.stdin)
except Exception:
    print(""); sys.exit(0)
if not isinstance(d, dict):
    print(""); sys.exit(0)

tool = str(d.get("tool_name") or "")
ti = d.get("tool_input") or d.get("input") or d.get("arguments") or {}
if not isinstance(ti, dict):
    ti = {}

# 기준 디렉토리 — Cursor는 cwd 대신 workspace_roots[]를 준다 (§5-4)
roots = d.get("workspace_roots")
root0 = roots[0] if isinstance(roots, list) and roots else ""
base = d.get("cwd") or ti.get("cwd") or root0 or os.environ["BASE_FALLBACK"]

def pick(*keys):
    for k in keys:
        v = ti.get(k)
        if v:
            return str(v)
    return ""

target = pick("file_path", "path", "filePath", "file")

# apply_patch(Codex)는 file_path가 없다 — 패치 본문에서 대상 경로를 뽑는다 (§5-4)
if not target and tool == "apply_patch":
    m = re.search(r"^\*\*\* (?:Add File|Update File|Move to): (.+)$", pick("command", "cmd"), re.M)
    if m:
        target = m.group(1).strip()

# 상대경로 → 절대경로 (에이전트는 대부분 cwd 상대경로를 쓴다 — §5-4)
if target:
    if not os.path.isabs(target):
        target = os.path.join(base, target)
    target = os.path.normpath(target)

print(target)
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
