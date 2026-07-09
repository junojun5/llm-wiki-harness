#!/usr/bin/env bash
# 단위 테스트: scripts/build-link-graph.sh (하네스 스펙 §4-6 링크 그래프 single-pass)
# 출력(라인 단위, 탭 구분): ORPHAN / BROKEN / REL_BROKEN / REL_SELF / SUMMARY
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

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
