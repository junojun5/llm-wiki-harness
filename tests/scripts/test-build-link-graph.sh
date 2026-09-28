#!/usr/bin/env bash
# 링크 그래프 출력: ORPHAN / BROKEN / REL_BROKEN / REL_SELF / SUMMARY.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GRAPH="$REPO_ROOT/scripts/build-link-graph.sh"
PASS=0; FAIL=0
TAB=$'\t'

new_sandbox() { SANDBOX="$(mktemp -d)"; WIKI="$SANDBOX/wiki"; mkdir -p "$WIKI"; }
cleanup() { [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"; }
trap cleanup EXIT

page() { local rel="$1"; shift; local f="$WIKI/$rel"; mkdir -p "$(dirname "$f")"; printf '%s' "$*" > "$f"; }

assert_contains() { local d="$1" n="$2" h="$3"; if printf '%s' "$h" | grep -qF -- "$n"; then PASS=$((PASS+1)); echo "  ok: $d"; else FAIL=$((FAIL+1)); echo "  FAIL: $d (want [$n])"; fi; }
assert_absent()   { local d="$1" n="$2" h="$3"; if printf '%s' "$h" | grep -qF -- "$n"; then FAIL=$((FAIL+1)); echo "  FAIL: $d (should NOT contain [$n])"; else PASS=$((PASS+1)); echo "  ok: $d"; fi; }

new_sandbox
# 허브 → leaf 링크 (leaf는 인바운드 있음 → 고아 아님)
page "knowledge/hub.md" '---
title: "허브"
---
[[concepts/leaf]] 참조.
'
page "concepts/leaf.md" '---
title: "리프"
---
내용.
'
# 고아: 인바운드 0, 아웃바운드 0
page "concepts/lonely.md" '---
title: "외톨이"
---
혼자.
'
# 깨진 본문 링크
page "knowledge/broken.md" '---
title: "깨짐"
---
[[does-not-exist]] 그리고 [[concepts/leaf]].
'
# relationships: 깨진 target + 자기참조
page "knowledge/rel.md" '---
title: "관계"
relationships:
  - target: "[[ghost-target]]"
    type: uses
  - target: "[[knowledge/rel]]"
    type: related_to
---
본문.
'
# 특수 파일 — 스캔·인바운드 제외 (index가 링크해도 leaf 고아여부에 영향 없음)
page "index.md" '# 목차
[[concepts/lonely]]
'
page "log.md" '로그'

OUT="$(bash "$GRAPH" "$WIKI" 2>"$SANDBOX/err")"
CODE=$?
ERR="$(cat "$SANDBOX/err")"

echo "test: build-link-graph 출력 검증"
assert_contains "exit 0" "0" "$CODE"
assert_contains "외톨이는 고아"            "ORPHAN${TAB}concepts/lonely.md" "$OUT"
assert_absent   "leaf는 고아 아님"          "ORPHAN${TAB}concepts/leaf.md"   "$OUT"
assert_contains "깨진 본문 링크 보고"        "BROKEN${TAB}knowledge/broken.md${TAB}does-not-exist" "$OUT"
assert_absent   "유효 링크는 BROKEN 아님"    "BROKEN${TAB}knowledge/broken.md${TAB}concepts/leaf" "$OUT"
assert_contains "관계 깨진 target 보고"      "REL_BROKEN${TAB}knowledge/rel.md${TAB}ghost-target" "$OUT"
assert_contains "관계 자기참조 보고"          "REL_SELF${TAB}knowledge/rel.md" "$OUT"
# 자기참조는 인바운드로 세지 않으므로, 다른 페이지가 링크하지 않는 rel.md는 고아
assert_contains "자기참조 페이지도 고아 판정"   "ORPHAN${TAB}knowledge/rel.md" "$OUT"
assert_contains "SUMMARY 라인 존재"          "SUMMARY" "$OUT"
# index.md가 lonely를 링크해도 인바운드로 세지 않으므로 lonely는 여전히 고아
cleanup

# 코드 블록·인라인 스팬 안의 [[링크]]는 링크가 아니다.
new_sandbox
page "concepts/target.md" '---
title: "대상"
---
내용.
'
page "concepts/mentions.md" '---
title: "언급만"
---
일반 개념은 `[[knowledge]]` 링크로 둔다.

```
[[fenced-not-a-link]]
```

실제 링크: [[concepts/target]]
'
OUT2="$(bash "$GRAPH" "$WIKI" 2>/dev/null)"

echo "test: 코드 스팬·코드 블록 안의 [[링크]] 제외"
assert_absent   "인라인 코드 스팬은 BROKEN 아님"  "BROKEN${TAB}concepts/mentions.md${TAB}knowledge" "$OUT2"
assert_absent   "코드 블록 안도 BROKEN 아님"      "BROKEN${TAB}concepts/mentions.md${TAB}fenced-not-a-link" "$OUT2"
assert_absent   "코드 밖 실제 링크는 계수됨"       "ORPHAN${TAB}concepts/target.md" "$OUT2"
assert_contains "broken 총계 0"                  "broken=0" "$OUT2"
cleanup

# 한글 파일명은 비UTF-8 locale에서도 출력에 남아야 한다.
echo "test: ASCII locale + 한글 파일명도 링크 그래프에 잡힌다"
new_sandbox
page "knowledge/한글허브.md" '---
title: "한글 허브"
---
[[concepts/없는페이지]] 참조.
'
OUT="$(LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 bash "$GRAPH" "$WIKI" 2>/dev/null)"
assert_contains "한글 파일명이 출력에 온전" "한글허브" "$OUT"
assert_contains "한글 대상의 깨진 링크 감지" "없는페이지" "$OUT"
cleanup

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
