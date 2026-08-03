#!/usr/bin/env bash
# 단위 테스트: scripts/validate-frontmatter.sh (하네스 스펙 §3-3 문서 클래스·기계 검증)
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/validate-frontmatter.sh"
PASS=0; FAIL=0

new_sandbox() { SANDBOX="$(mktemp -d)"; }
cleanup() { [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"; }
trap cleanup EXIT

# 파일을 만들고 validator 실행 → OUT/ERR/CODE
run_validate() {
  local relpath="$1" content="$2"
  local f="$SANDBOX/$relpath"
  mkdir -p "$(dirname "$f")"
  printf '%s' "$content" > "$f"
  OUT="$(bash "$VALIDATOR" "$f" 2>"$SANDBOX/err")"; CODE=$?
  ERR="$(cat "$SANDBOX/err")"
}

assert_eq() { local d="$1" e="$2" a="$3"; if [ "$e" = "$a" ]; then PASS=$((PASS+1)); echo "  ok: $d"; else FAIL=$((FAIL+1)); echo "  FAIL: $d (expected [$e] got [$a])"; fi; }
assert_contains() { local d="$1" n="$2" h="$3"; if printf '%s' "$h" | grep -qF -- "$n"; then PASS=$((PASS+1)); echo "  ok: $d"; else FAIL=$((FAIL+1)); echo "  FAIL: $d (want substr [$n] in [$h])"; fi; }

# 유효한 클래스① 풀세트 페이지 본문
VALID_PAGE='---
title: "머신러닝"
category: knowledge
tags: [ml, ai]
sources: ["raw/papers/x.pdf"]
created: 2026-06-25
updated: 2026-06-25
summary: "짧은 요약"
status: verified
base_confidence: 0.9
---

본문.
'

echo "test: 유효한 클래스① 페이지 → exit 0"
new_sandbox; run_validate "wiki/knowledge/ml.md" "$VALID_PAGE"
assert_eq "exit 0" "0" "$CODE"; cleanup

echo "test: summary 누락 → 실패 + summary 언급"
new_sandbox; run_validate "wiki/knowledge/ml.md" "${VALID_PAGE/summary: \"짧은 요약\"$'\n'/}"
assert_eq "exit !=0" "1" "$CODE"; assert_contains "summary 언급" "summary" "$ERR"; cleanup

echo "test: summary 400자 초과 → 실패"
new_sandbox
LONG=$(printf 'x%.0s' $(seq 1 401))
run_validate "wiki/knowledge/ml.md" "${VALID_PAGE/짧은 요약/$LONG}"
assert_eq "exit !=0" "1" "$CODE"; assert_contains "400 언급" "400" "$ERR"; cleanup

echo "test: 잘못된 category enum → 실패"
new_sandbox; run_validate "wiki/knowledge/ml.md" "${VALID_PAGE/category: knowledge/category: nonsense}"
assert_eq "exit !=0" "1" "$CODE"; assert_contains "category 언급" "category" "$ERR"; cleanup

echo "test: 클래스① status enum 위반(proposed) → 실패"
new_sandbox; run_validate "wiki/knowledge/ml.md" "${VALID_PAGE/status: verified/status: proposed}"
assert_eq "exit !=0" "1" "$CODE"; assert_contains "status 언급" "status" "$ERR"; cleanup

echo "test: tags 6개 초과 → 실패"
new_sandbox
SIXTAGS='---
title: "머신러닝"
category: knowledge
tags: [a, b, c, d, e, f]
sources: ["raw/papers/x.pdf"]
created: 2026-06-25
updated: 2026-06-25
summary: "짧은 요약"
status: verified
base_confidence: 0.9
---

본문.
'
run_validate "wiki/knowledge/ml.md" "$SIXTAGS"
assert_eq "exit !=0" "1" "$CODE"; assert_contains "tags 언급" "tags" "$ERR"; cleanup

echo "test: created 날짜 형식 위반 → 실패"
new_sandbox; run_validate "wiki/knowledge/ml.md" "${VALID_PAGE/created: 2026-06-25/created: 2026\/06\/25}"
assert_eq "exit !=0" "1" "$CODE"; assert_contains "날짜 언급" "created" "$ERR"; cleanup

echo "test: base_confidence 범위 초과 → 실패"
new_sandbox; run_validate "wiki/knowledge/ml.md" "${VALID_PAGE/base_confidence: 0.9/base_confidence: 1.5}"
assert_eq "exit !=0" "1" "$CODE"; assert_contains "base_confidence 언급" "base_confidence" "$ERR"; cleanup

echo "test: 클래스③ 원장(decisions.md)은 frontmatter 없어도 통과"
new_sandbox; run_validate "wiki/projects/p/decisions.md" "## [2026-06-25] 결정
- 결정: 평문 마크다운, frontmatter 없음
"
assert_eq "exit 0 (면제)" "0" "$CODE"; cleanup

echo "test: 클래스③ index.md 통과"
new_sandbox; run_validate "wiki/index.md" "# 목차
- 평문
"
assert_eq "exit 0 (면제)" "0" "$CODE"; cleanup

# 클래스② changes 유효 본문 (축소셋)
VALID_CHANGE='---
title: "도메인 모델 변경"
category: projects
project: myproj
targets: ["architecture.md"]
status: proposed
created: 2026-06-25
status_changed: 2026-06-25
summary: "AS-IS→TO-BE"
base_confidence: 0.7
tier: core
---

## 근거
- [[x]]
'
echo "test: 클래스② changes 유효(proposed) → exit 0"
new_sandbox; run_validate "wiki/projects/p/changes/2026-06-25-x.md" "$VALID_CHANGE"
assert_eq "exit 0" "0" "$CODE"; cleanup

echo "test: 클래스② changes에 페이지 status(verified) → 실패"
new_sandbox; run_validate "wiki/projects/p/changes/2026-06-25-x.md" "${VALID_CHANGE/status: proposed/status: verified}"
assert_eq "exit !=0" "1" "$CODE"; assert_contains "status 언급" "status" "$ERR"; cleanup

# 클래스② troubleshooting 유효 본문
VALID_TS='---
title: "버그 케이스"
category: projects
status: open
created: 2026-06-25
updated: 2026-06-25
summary: "증상"
---

증상.
'
echo "test: 클래스② troubleshooting 유효(open) → exit 0"
new_sandbox; run_validate "wiki/projects/p/troubleshooting/bug.md" "$VALID_TS"
assert_eq "exit 0" "0" "$CODE"; cleanup

echo "test: troubleshooting status 위반(proposed) → 실패"
new_sandbox; run_validate "wiki/projects/p/troubleshooting/bug.md" "${VALID_TS/status: open/status: proposed}"
assert_eq "exit !=0" "1" "$CODE"; assert_contains "status 언급" "status" "$ERR"; cleanup

# ── 표기 가드: 인라인 flow 표기는 검사를 무력화하므로 fail-loud여야 한다 (§3-3) ──
echo "test: provenance 인라인 표기(합=0.3) → 실패 (조용히 통과 금지)"
new_sandbox
run_validate "wiki/knowledge/ml.md" "${VALID_PAGE/base_confidence: 0.9/base_confidence: 0.9
provenance: { extracted: 0.1, inferred: 0.1, ambiguous: 0.1 \}}"
assert_eq "exit !=0" "1" "$CODE"
assert_contains "블록 표기 안내" "provenance가 블록 표기가 아닙니다" "$ERR"; cleanup

echo "test: provenance 블록 표기(합=0.4) → 합계 위반으로 실패"
new_sandbox
run_validate "wiki/knowledge/ml.md" "${VALID_PAGE/base_confidence: 0.9/base_confidence: 0.9
provenance:
  extracted: 0.2
  inferred: 0.1
  ambiguous: 0.1}"
assert_eq "exit !=0" "1" "$CODE"
assert_contains "합계 위반 언급" "provenance 합이 1.0에서 벗어남" "$ERR"; cleanup

echo "test: provenance 블록 표기(합=1.0) → 통과"
new_sandbox
run_validate "wiki/knowledge/ml.md" "${VALID_PAGE/base_confidence: 0.9/base_confidence: 0.9
provenance:
  extracted: 0.7
  inferred: 0.2
  ambiguous: 0.1}"
assert_eq "exit 0" "0" "$CODE"; cleanup

echo "test: relationships 베어 스칼라 표기 → 실패"
new_sandbox
run_validate "wiki/knowledge/ml.md" "${VALID_PAGE/base_confidence: 0.9/base_confidence: 0.9
relationships: uses}"
assert_eq "exit !=0" "1" "$CODE"
assert_contains "블록 리스트 안내" "relationships가 블록 리스트 표기가 아닙니다" "$ERR"; cleanup

# 인라인 flow **시퀀스**는 파서의 `[ ... ]` 분기를 타 문자열 리스트로 읽히므로
# isinstance(list) 만으로는 통과한다 — 그 상태에서 type enum 루프가 무발화하는 것이
# 실제 결함이었다. 표기 자체를 끊어야 한다.
echo "test: relationships 인라인 flow 시퀀스 → 실패 (조용히 통과 금지)"
new_sandbox
run_validate "wiki/knowledge/ml.md" "${VALID_PAGE/base_confidence: 0.9/base_confidence: 0.9
relationships: [{ target: \"[[deep-learning]]\", type: extends \}]}"
assert_eq "exit !=0" "1" "$CODE"
assert_contains "블록 리스트 안내" "relationships가 블록 리스트 표기가 아닙니다" "$ERR"; cleanup

echo "test: relationships 인라인 flow 시퀀스 + 잘못된 type → 실패 (enum 우회 금지)"
new_sandbox
run_validate "wiki/knowledge/ml.md" "${VALID_PAGE/base_confidence: 0.9/base_confidence: 0.9
relationships: [{ target: \"[[deep-learning]]\", type: NOT_A_TYPE \}]}"
assert_eq "exit !=0" "1" "$CODE"; cleanup

echo "test: relationships 블록 리스트 + 잘못된 type → 실패 (enum 경로 생존)"
new_sandbox
run_validate "wiki/knowledge/ml.md" "${VALID_PAGE/base_confidence: 0.9/base_confidence: 0.9
relationships:
  - target: \"[[deep-learning]]\"
    type: NOT_A_TYPE}"
assert_eq "exit !=0" "1" "$CODE"
assert_contains "type enum 언급" "relationship type enum 위반" "$ERR"; cleanup

echo "test: relationships 블록 리스트 표기 → 통과"
new_sandbox
run_validate "wiki/knowledge/ml.md" "${VALID_PAGE/base_confidence: 0.9/base_confidence: 0.9
relationships:
  - target: \"[[deep-learning]]\"
    type: extends}"
assert_eq "exit 0" "0" "$CODE"; cleanup

# ── 클래스 판정 범위: 클래스②는 projects/{name}/{changes|troubleshooting}/ 로 한정 (§3-3) ──
# knowledge/ 는 대형 주제에 서브폴더를 허용하므로, 같은 이름의 서브폴더가 있어도
# 클래스① 페이지로 판정돼야 한다.
echo "test: knowledge/changes/ 서브폴더 → 클래스①로 판정 (통과)"
new_sandbox; run_validate "wiki/knowledge/api/changes/versioning.md" "$VALID_PAGE"
assert_eq "exit 0" "0" "$CODE"; cleanup

echo "test: knowledge/troubleshooting/ 서브폴더 → 클래스①로 판정 (통과)"
new_sandbox; run_validate "wiki/knowledge/api/troubleshooting/timeouts.md" "$VALID_PAGE"
assert_eq "exit 0" "0" "$CODE"; cleanup

echo "test: projects/{name}/changes/archive/ → 여전히 클래스② (통과)"
new_sandbox; run_validate "wiki/projects/p/changes/archive/2026-06-25-x.md" "$VALID_CHANGE"
assert_eq "exit 0" "0" "$CODE"; cleanup

echo "test: projects/{name}/changes/ 에 클래스① frontmatter → 클래스②로 판정돼 실패"
new_sandbox; run_validate "wiki/projects/p/changes/2026-06-25-y.md" "$VALID_PAGE"
assert_eq "exit !=0" "1" "$CODE"
assert_contains "클래스② 안내" "category는 projects여야 합니다" "$ERR"; cleanup

# ── 비UTF-8 locale (§3-9) ─────────────────────────────────────────────────
# 위반 메시지는 전부 한국어다. python3의 stdout/stderr 인코딩은 locale이 결정하므로
# 비UTF-8 locale에서는 메시지가 \uXXXX 이스케이프로 손상되거나 죽는다 — 사용자가 무엇을
# 고쳐야 하는지 읽을 수 없다(2026-08-04 Windows CI 실측: cp1252에서 이스케이프로 나왔다).
# macOS/Linux는 C locale에서 UTF-8 모드가 자동 활성화되므로 그 자동화까지 꺼야 동일 조건이다.
echo "test: ASCII locale에서도 한국어 위반 메시지가 온전하다"
new_sandbox
f="$SANDBOX/wiki/knowledge/broken.md"; mkdir -p "$(dirname "$f")"
printf '%s' '---
title: "요약 없음"
category: knowledge
tags: [a]
sources: ["raw/x.md"]
created: 2026-08-04
updated: 2026-08-04
status: verified
base_confidence: 0.8
---
본문.' > "$f"
ERR="$(LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 bash "$VALIDATOR" "$f" 2>&1 >/dev/null)"; CODE=$?
assert_contains "한국어 메시지 손상 없음" "필수 키 누락" "$ERR"
assert_contains "이스케이프되지 않음" "summary" "$ERR"
cleanup

echo "test: ASCII locale + 한글 파일명 페이지도 검증한다"
new_sandbox
run_validate "wiki/knowledge/한글제목.md" "$VALID_PAGE"
assert_eq "정상 페이지 통과" "0" "$CODE"
f="$SANDBOX/wiki/knowledge/한글제목.md"
LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 bash "$VALIDATOR" "$f" >/dev/null 2>&1
assert_eq "ASCII locale에서도 통과" "0" "$?"
cleanup

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
