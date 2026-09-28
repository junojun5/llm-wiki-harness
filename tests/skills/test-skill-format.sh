#!/usr/bin/env bash
# SKILL.md 형식: [[slug]]만, description에 '때 사용', frontmatter ≤1024바이트, 안티패턴.
# 절차 스킬은 워크플로(Step≥3)와 품질 체크. using-llm-wiki는 라우터라 면제. AGENTS.md와 공통 키를 맞춘다.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# using-llm-wiki는 라우터라 워크플로·품질 체크를 요구하지 않는다.
is_router() { [ "$1" = using-llm-wiki ]; }

# frontmatter 블록(첫 `---` 다음 ~ 닫는 `---` 전)만 뽑는다.
frontmatter() { awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f' "$1"; }

# 헤딩은 코드 펜스 밖에서만 센다. 템플릿 안 헤딩을 스킬 헤딩으로 보면 안 된다.
has_heading() { awk -v h="$2" '/^```/{c=!c; next} !c && index($0,h)==1 {found=1; exit} END{exit !found}' "$1"; }

echo "test: SKILL.md 형식 계약 (docs/skill-authoring-guide.md)"

for d in "$REPO_ROOT"/skills/*/; do
  s="$(basename "$d")"; F="$d/SKILL.md"
  [ -f "$F" ] || { bad "$s: SKILL.md 없음"; continue; }
  FM="$(frontmatter "$F")"

  # 링크는 파일명만. 예외는 [[changes/archive/YYYY-MM-DD-{slug}]] 형태뿐.
  viol="$(grep -nE '\[\[(wiki|summaries|concepts|knowledge|entities|projects|meetings|changes)/' "$F" \
          | { grep -v '\[\[changes/archive/' || true; })"
  if [ -z "$viol" ]; then ok "$s: 링크 파일명만"
  else bad "$s: 폴더 접두 링크 — $(printf '%s' "$viol" | head -1 | cut -c1-70)"; fi

  # description에는 '때 사용'이 있어야 한다. '할'까지 요구하면 정상 스킬이 걸린다.
  case "$FM" in
    *"때 사용"*) ok "$s: description 트리거" ;;
    *) bad "$s: description에 '때 사용' 트리거 없음" ;;
  esac

  # frontmatter는 1024바이트 이하. wc -m은 locale에 따라 값이 바뀐다.
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

  # 워크플로는 Step이 3개 이상이다.
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

# AGENTS.md와 using-llm-wiki는 같은 키를 가진다. 한쪽에만 있으면 도구마다 규칙이 갈린다.
echo "test: AGENTS.md ↔ using-llm-wiki/SKILL.md 부트스트랩 패리티"
ROUTER="$REPO_ROOT/skills/using-llm-wiki/SKILL.md"
for kw in resolve-vault raw index log hot QMD; do
  in_s=0; in_a=0
  grep -qF "$kw" "$ROUTER"               && in_s=1
  grep -qF "$kw" "$REPO_ROOT/AGENTS.md"  && in_a=1
  if [ "$in_s" = 1 ] && [ "$in_a" = 1 ]; then ok "'$kw' 양쪽 존재"
  else bad "'$kw' 한쪽에만 존재 (skill=$in_s agents=$in_a) — 규칙이 도구별로 갈린다"; fi
done

# 영어 답변 프리픽스와 인라인 provenance 오브젝트는 없어야 한다.
echo "test: 되돌아오면 안 되는 표기 (Phase 2에서 정리된 것)"
# 답변 프리픽스가 영어로 되돌아가지 않는가. 스킬 본문·출력 포맷은 한국어가 계약이다.
hit="$(grep -rn 'Based on the wiki' "$REPO_ROOT/skills/" 2>/dev/null | head -1)"
[ -z "$hit" ] && ok "영어 답변 프리픽스 없음" || bad "영어 프리픽스 잔존 — ${hit#$REPO_ROOT/}"
# provenance: { 인라인 오브젝트는 금지다.
hit="$(grep -rnE 'provenance: *\{' "$REPO_ROOT/skills/" 2>/dev/null | head -1)"
[ -z "$hit" ] && ok "인라인 provenance 오브젝트 없음" || bad "인라인 provenance 잔존 — ${hit#$REPO_ROOT/}"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
