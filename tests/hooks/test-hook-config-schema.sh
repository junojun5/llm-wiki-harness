#!/usr/bin/env bash
# Codex 훅 JSON 최상위는 description과 hooks만 허용한다. 다른 키가 있으면 훅이 0개가 된다.
# python에 넘기는 경로는 소스 문자열이 아니라 argv다. MSYS는 argv만 변환한다.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0

assert_eq() { local d="$1" e="$2" a="$3"; if [ "$e" = "$a" ]; then PASS=$((PASS+1)); echo "  ok: $d"; else FAIL=$((FAIL+1)); echo "  FAIL: $d (expected [$e] got [$a])"; fi; }

# 최상위 키가 허용 집합을 벗어나면 그 키들을 출력, 아니면 빈 문자열
extra_keys() { # extra_keys <file> <allowed,comma,separated>
  PYTHONUTF8=1 python3 -c '
import json, sys
allowed = set(sys.argv[2].split(","))
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as e:
    print("PARSE_ERROR:%s" % e); sys.exit(0)
print(",".join(sorted(k for k in d if k not in allowed)))
' "$1" "$2"
}

echo "test: 모든 훅 등록 JSON이 유효한 JSON"
for f in hooks/hooks.json hooks/hooks-codex.json hooks/hooks-cursor.json; do
  PYTHONUTF8=1 python3 -m json.tool "$REPO_ROOT/$f" >/dev/null 2>&1
  assert_eq "$f 파싱" "0" "$?"
done

echo "test: hooks-codex.json 최상위는 description|hooks 만 (Codex strict 역직렬화)"
assert_eq "허용 밖 키 없음" "" "$(extra_keys "$REPO_ROOT/hooks/hooks-codex.json" "description,hooks")"

echo "test: hooks-codex.json 에 hooks 키가 존재하고 3개 이벤트를 등록"
EVENTS="$(PYTHONUTF8=1 python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(",".join(sorted((d.get("hooks") or {}).keys())))
' "$REPO_ROOT/hooks/hooks-codex.json")"
assert_eq "이벤트 3종" "PostToolUse,PreToolUse,SessionStart" "$EVENTS"

echo "test: hooks-codex.json command 는 PLUGIN_ROOT 절대참조 (훅 cwd는 세션 cwd)"
BAD="$(PYTHONUTF8=1 python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
bad = []
for ev, entries in (d.get("hooks") or {}).items():
    for e in entries:
        for h in e.get("hooks", []):
            c = h.get("command", "")
            if "PLUGIN_ROOT" not in c:
                bad.append("%s:%s" % (ev, c))
print(";".join(bad))
' "$REPO_ROOT/hooks/hooks-codex.json")"
assert_eq "PLUGIN_ROOT 미참조 없음" "" "$BAD"

# Claude·Cursor는 파싱과 hooks 존재만 본다.
echo "test: hooks.json(Claude)·hooks-cursor.json(Cursor)에 hooks 키 존재"
for f in hooks/hooks.json hooks/hooks-cursor.json; do
  HAS="$(PYTHONUTF8=1 python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print("yes" if isinstance(d.get("hooks"), dict) and d["hooks"] else "no")
' "$REPO_ROOT/$f")"
  assert_eq "$f hooks 존재" "yes" "$HAS"
done

# 런처 경로는 인용한다. 공백이 있으면 인자 경계가 깨진다.
echo "test: 세 등록 JSON 모두 런처 경로를 큰따옴표로 감싼다"
UNQUOTED="$(PYTHONUTF8=1 python3 -c '
import json, sys
bad = []
for path in sys.argv[1:]:
    d = json.load(open(path, encoding="utf-8"))
    for ev, entries in (d.get("hooks") or {}).items():
        for e in entries:
            # Claude·Codex는 entry 안에 hooks 배열, Cursor는 entry 자체가 훅이다
            for h in (e.get("hooks") or [e]):
                c = h.get("command", "")
                if not c:
                    continue
                if not (c.startswith("\"") and "run-hook.cmd\"" in c):
                    bad.append("%s:%s:%s" % (path.rsplit("/", 1)[-1], ev, c))
print(";".join(bad))
' "$REPO_ROOT/hooks/hooks.json" "$REPO_ROOT/hooks/hooks-codex.json" "$REPO_ROOT/hooks/hooks-cursor.json")"
assert_eq "미인용 command 없음" "" "$UNQUOTED"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
