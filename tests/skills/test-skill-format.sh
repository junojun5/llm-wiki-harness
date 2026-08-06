#!/usr/bin/env bash
# 단위 테스트: SKILL.md 형식 계약. 정본은 `docs/skill-authoring-guide.md`다.
#
# ── 왜 있는가 ──────────────────────────────────────────────────────────────────
# 이 검증들은 `docs/plans/2026-07-11-skill-doc-rewrite.md`의 "Shared Verification
# Recipe"로만 존재했다. 그 계획서는 **실행 완료됐다**(12스킬 재작성 반영, PR #11~#14).
# 그런데 두 가지가 남았다:
#   ① 체크박스가 0/57 미체크로 남아 다음 읽는 사람에게 "미완 작업 57건"으로 읽혔다.
#   ② 검증이 **1회성 수동 레시피**여서, 그 뒤로 스킬을 고칠 때 아무것도 검사하지 않았다.
# 계획서를 삭제하면서 기계 체크만 이 스위트로 승격한다 — 산문 규칙을 테스트로 바꾸는 것이
# 이 레포의 방향이다(§10: "산문 규칙만 있고 훅·테스트가 검사하지 않아 조용히 통과한다").
#
# ── 계약은 실측에서 왔다 (2026-08-07) ──────────────────────────────────────────
# 승격하면서 가이드가 선언한 스켈레톤(`## 개요`·`## 언제 사용`·`## 워크플로우`)을 그대로
# 단언했더니 **12스킬 전부 실패했다.** 어느 스킬도 그 헤딩을 쓰지 않는다. 실제로 수렴한
# 규약은 `## 워크플로`(코드블록 안 `Step N:`) + `## 품질 체크` + `## 안티패턴`이다.
# 12곳(구현)과 1곳(문서)이 어긋났으므로 **문서를 실측에 맞췄고**, 이 스위트는 실측된
# 규약을 고정한다. 가이드 스스로 "고정 템플릿을 곧이곧대로 따르지 않는다"고 선언하므로
# 스켈레톤 헤딩을 기계 단언하는 것은 애초에 가이드와도 어긋났다.
#
# ── [7]이 닫는 갭 ──────────────────────────────────────────────────────────────
# `AGENTS.md`는 스스로 이렇게 선언한다:
#   "공통 절차의 본문은 skills/using-llm-wiki/ 이고 이 파일은 그 요약이다
#    — 규칙을 바꿀 때는 두 곳을 함께 고친다"
# 이걸 검사하는 것이 지금까지 **아무것도 없었다.** 한쪽만 고치면 Claude는 스킬을 읽고
# 비-Claude 도구(Codex·Cursor·Antigravity)는 AGENTS.md를 읽으므로 **서로 다른 규칙으로
# 같은 볼트를 만진다.** 침묵하는 종류의 결함이라 기계 체크가 유일한 방어다.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# 스킬 유형 — 가이드 "유형별 변형"의 기계 표현. 라우터형은 절차 스킬이 아니라 규칙+라우팅
# 표이므로 워크플로·품질 체크를 요구하지 않는다(실측: using-llm-wiki만 해당).
is_router() { [ "$1" = using-llm-wiki ]; }

# frontmatter 블록(첫 `---` 다음 ~ 닫는 `---` 전)만 뽑는다.
frontmatter() { awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f' "$1"; }

# 코드블록 밖의 2단 헤딩 존재 여부. ⚠️ 펜스를 세지 않으면 페이지 **템플릿** 안의 헤딩을
# 스킬 자신의 헤딩으로 오독한다(wiki-knowledge의 `## 개요`가 그 경우다 — 실측).
has_heading() { awk -v h="$2" '/^```/{c=!c; next} !c && index($0,h)==1 {found=1; exit} END{exit !found}' "$1"; }

echo "test: SKILL.md 형식 계약 (docs/skill-authoring-guide.md)"

for d in "$REPO_ROOT"/skills/*/; do
  s="$(basename "$d")"; F="$d/SKILL.md"
  [ -f "$F" ] || { bad "$s: SKILL.md 없음"; continue; }
  FM="$(frontmatter "$F")"

  # [1] 링크 표기 — `[[slug]]` 파일명만. 폴더 접두 링크는 위반 (가이드 강제 ④).
  #     유일한 예외는 변경기록 `[[changes/archive/YYYY-MM-DD-{slug}]]`이고, **링크 형태에
  #     붙는 예외지 특정 스킬에 붙는 예외가 아니다** — change proposal 생애주기를 두 스킬이
  #     나눠 갖기 때문이다(design이 proposal을 만들고 record가 결정을 박제한다). 계획서는
  #     이 예외를 wiki-project-record 항목에만 적어 뒀는데, 실측하니 wiki-project-design도
  #     같은 경로를 참조한다 — 형태 기준이 옳다.
  viol="$(grep -nE '\[\[(wiki|summaries|concepts|knowledge|entities|projects|meetings|changes)/' "$F" \
          | { grep -v '\[\[changes/archive/' || true; })"
  if [ -z "$viol" ]; then ok "$s: 링크 파일명만"
  else bad "$s: 폴더 접두 링크 — $(printf '%s' "$viol" | head -1 | cut -c1-70)"; fi

  # [2] description 트리거 (가이드 강제 ①) — "언제 쓰는가"여야 하고 워크플로우 요약은 금지다.
  #     표지는 `때 사용`이다. 가이드는 `…할 때 사용`으로 적었지만 실제 어미는 다양하다
  #     (`싶을 때 사용`·`려 할 때 사용`·`언급할 때`) — `할`을 요구하면 정상 스킬이 걸린다.
  case "$FM" in
    *"때 사용"*) ok "$s: description 트리거" ;;
    *) bad "$s: description에 '때 사용' 트리거 없음" ;;
  esac

  # [3] frontmatter 길이 — 한도는 1024자다. **바이트로 잰다**: `wc -m`은 locale 의존이라
  #     Windows/C locale에서 값이 달라지고(§3-9와 같은 계열의 함정), 한국어는 char<byte이므로
  #     바이트 통과는 char 통과를 함의한다. 현재 최대 533B라 여유가 충분하다.
  n="$(printf '%s' "$FM" | wc -c | tr -d ' ')"
  if [ "$n" -le 1024 ]; then ok "$s: frontmatter ${n}B"
  else bad "$s: frontmatter ${n}B > 1024"; fi

  # [4] `## 안티패턴` — 12/12 실측. 가이드에 없던 규약이라 승격하면서 문서에 추가했다.
  if has_heading "$F" '## 안티패턴'; then ok "$s: 안티패턴 섹션"
  else bad "$s: '## 안티패턴' 없음"; fi

  if is_router "$s"; then
    ok "$s: 라우터형 — 워크플로·품질 체크 면제(가이드 유형별 변형)"
    continue
  fi

  # [5] `## 워크플로` + [6] Step 단계 ≥3 — "워크플로우는 절대 한 줄로 압축하지 않는다"가
  #     가이드가 명시한 **기존 스킬의 최악의 문제**다. 실측 8~13단계이므로 3은 넉넉한 하한이다.
  if has_heading "$F" '## 워크플로'; then
    steps="$(awk '/^## 워크플로/{f=1; next} f && /^## /{f=0} f && /^[[:space:]]*Step /{k++} END{print k+0}' "$F")"
    if [ "$steps" -ge 3 ]; then ok "$s: 워크플로 ${steps}단계"
    else bad "$s: 워크플로가 ${steps}단계 — 한 줄 압축 금지 위반"; fi
  else
    bad "$s: '## 워크플로' 없음"
  fi

  # [6] `## 품질 체크` — 종료 전 검증. 라우터 외 11/11 실측.
  if has_heading "$F" '## 품질 체크'; then ok "$s: 품질 체크 섹션"
  else bad "$s: '## 품질 체크' 없음"; fi
done

# [7] AGENTS.md ↔ using-llm-wiki/SKILL.md 부트스트랩 패리티.
#     둘은 같은 규칙의 두 표면이다(전자는 비-Claude, 후자는 Claude). 한쪽에만 있는 항목은
#     "도구에 따라 규칙이 다르다"는 뜻이므로 곧 볼트 불일치가 된다.
echo "test: AGENTS.md ↔ using-llm-wiki/SKILL.md 부트스트랩 패리티"
ROUTER="$REPO_ROOT/skills/using-llm-wiki/SKILL.md"
for kw in resolve-vault raw index log hot QMD; do
  in_s=0; in_a=0
  grep -qF "$kw" "$ROUTER"               && in_s=1
  grep -qF "$kw" "$REPO_ROOT/AGENTS.md"  && in_a=1
  if [ "$in_s" = 1 ] && [ "$in_a" = 1 ]; then ok "'$kw' 양쪽 존재"
  else bad "'$kw' 한쪽에만 존재 (skill=$in_s agents=$in_a) — 규칙이 도구별로 갈린다"; fi
done

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
