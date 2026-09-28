#!/usr/bin/env bash
# wiki/ 아래 .md의 frontmatter를 검증하는 wrapper. 위반 때만 stderr + exit 2.
set -u

# resolver 실패(python3 부재 포함)는 통과. 막으면 볼트 밖까지 막히고, 고지는 session-start가 한다.
RESOLVED="$(bash "$HOME/.llm-wiki/scripts/resolve-vault.sh" 2>/dev/null)" || exit 0
VAULT_PATH="$(printf '%s\n' "$RESOLVED" | sed -n 's/^VAULT_PATH=//p')"
WIKI_DIR="$(printf '%s\n' "$RESOLVED" | sed -n 's/^WIKI_DIR=//p')"
[ -n "$VAULT_PATH" ] && [ -n "$WIKI_DIR" ] || exit 0

# 필드 탐색은 wiki-protect-raw.sh와 같다. Delete File은 빼고, wiki/ 판정은 python에서 경로를 맞춘다.
TARGET="$(printf '%s' "$(cat)" | BASE_FALLBACK="$PWD" WIKI_ABS="$VAULT_PATH/$WIKI_DIR" PYTHONUTF8=1 python3 -c '
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

target = pick("file_path", "path", "filePath", "file")

# apply_patch는 file_path가 없다. 패치 본문에서 경로를 뽑는다. Delete File은 제외.
if not target and tool == "apply_patch":
    m = re.search(r"^\*\*\* (?:Add File|Update File|Move to): (.+)$", pick("command", "cmd"), re.M)
    if m:
        target = m.group(1).strip()

# 상대경로는 base 기준으로 절대화한다.
if target:
    if not os.path.isabs(target):
        target = os.path.join(base, target)
    # 비교 전 슬래시를 맞춘다. 안 맞추면 Windows에서 검증이 통과한다. _norm은 wiki-protect-raw.sh와 같다.
    def _norm(p):
        return os.path.normcase(os.path.normpath(p)).replace("\\", "/")
    wiki_abs = _norm(os.environ["WIKI_ABS"])
    if not (_norm(target).startswith(wiki_abs + "/") and target.lower().endswith(".md")):
        print(""); sys.exit(0)
    target = os.path.normpath(target).replace("\\", "/")

print(target)
')"

# 볼트 wiki/ 하위 .md가 아니면 통과 — 판정은 위 python 블록이 했다(빈 문자열 = 대상 아님)
[ -n "$TARGET" ] || exit 0

# 클래스 판정과 검증은 validator가 한다. 원장 파일 예외를 여기서 다시 두지 않는다.
bash "$HOME/.llm-wiki/scripts/validate-frontmatter.sh" "$TARGET" >&2 || exit 2
exit 0
