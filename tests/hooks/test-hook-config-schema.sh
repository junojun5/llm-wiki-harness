#!/usr/bin/env bash
# 단위 테스트: 플랫폼별 훅 등록 JSON의 최상위 스키마.
#
# 왜 필요한가 (2026-08-01 Phase 3 실측):
#   Codex 0.146.0은 훅 설정을 **strict**하게 역직렬화한다 — 최상위에 `description`·`hooks`
#   외의 키가 있으면 파일 전체 파싱이 실패하고 경고 한 줄만 남긴 뒤 **훅 0개로 진행**한다:
#     warning: failed to parse plugin hooks config .../hooks-codex.json:
#              unknown field `_comment`, expected `description` or `hooks`
#   설치는 성공하고 `codex plugin list`도 "installed, enabled"로 보이므로 조용히 무방비가 된다.
#   Claude·Cursor는 `_comment`를 관용하므로(실측) 이 제약은 Codex 파일에만 적용한다.
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
import json
d = json.load(open("'"$REPO_ROOT"'/hooks/hooks-codex.json"))
print(",".join(sorted((d.get("hooks") or {}).keys())))
')"
assert_eq "이벤트 3종" "PostToolUse,PreToolUse,SessionStart" "$EVENTS"

echo "test: hooks-codex.json command 는 PLUGIN_ROOT 절대참조 (훅 cwd는 세션 cwd)"
BAD="$(PYTHONUTF8=1 python3 -c '
import json
d = json.load(open("'"$REPO_ROOT"'/hooks/hooks-codex.json"))
bad = []
for ev, entries in (d.get("hooks") or {}).items():
    for e in entries:
        for h in e.get("hooks", []):
            c = h.get("command", "")
            if "PLUGIN_ROOT" not in c:
                bad.append("%s:%s" % (ev, c))
print(";".join(bad))
')"
assert_eq "PLUGIN_ROOT 미참조 없음" "" "$BAD"

# Claude·Cursor는 _comment를 관용한다(실측). 여기서는 "파싱 가능 + hooks 존재"만 보장한다 —
# 관용 여부가 바뀌면 위 Codex 케이스와 같은 방식으로 제약을 추가한다.
echo "test: hooks.json(Claude)·hooks-cursor.json(Cursor)에 hooks 키 존재"
for f in hooks/hooks.json hooks/hooks-cursor.json; do
  HAS="$(PYTHONUTF8=1 python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print("yes" if isinstance(d.get("hooks"), dict) and d["hooks"] else "no")
' "$REPO_ROOT/$f")"
  assert_eq "$f hooks 존재" "yes" "$HAS"
done

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
