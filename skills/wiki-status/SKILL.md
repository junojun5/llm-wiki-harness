---
name: wiki-status
description: ingest 대기 중인 raw 파일, 최근 처리 내역, 볼트 전반 상태를 알고 싶을 때 사용한다. "무엇이 잘못됐나"가 아니라 "무엇이 남았나"에 답하며, 개수·토큰 풋프린트·우선순위 액션 목록을 보고한다. 트리거는 "wiki 상태"·"뭐 쌓여있어"·"ingest 뭐 남았어".
---

# wiki-status

볼트에서 **무엇이 남았나**(진행 상황)를 보고한다. ("무엇이 잘못됐나"는 `wiki-lint`.)

시작 전 `using-llm-wiki` 스킬을 로드한다 — Config Gate, read-only 경계.

> **보고 전용(read-only).** 탐지 기준이 `wiki-lint`와 겹치는 항목(삭제 대기 raw, manifest↔파일 정합성)도 **개수·목록만 보고**한다. 판정 기준의 단일 출처와 수정 권한은 항상 `wiki-lint`에 있다. `log.md` append 외의 쓰기와 QMD refresh는 하지 않는다.

## 워크플로

```
Step 0:   Config Gate
Step 0.5: wiki/hot.md 읽기 (있으면) — Step 5 "최근 작업" 맥락 보강

Step 1: .manifest.json 읽기
  마지막 ingest 타임스탬프 / 총 소스 수 / 총 wiki 페이지 수
  manifest 없으면 → "아직 ingest된 파일 없음. /wiki-ingest를 먼저 실행하세요" 출력 후 Step 4로

Step 2: raw/ 스캔 vs .manifest.json 비교 (content_hash 기반)
  manifest에 없음                          → 📥 미처리 (ingest 대기)
  있고 content_hash 다름                    → 🔄 갱신 필요
  있고 content_hash 같음                    → 스킵 (mtime 무관)
  ingest 완료 + ingested_at 14일 초과        → 🗑️ 삭제 대기 (보고만, 삭제하지 않는다)

Step 3: 토큰 풋프린트 추정
  wiki/ 전체 .md size 합산 (Glob) + frontmatter grep으로 tier 분류
  추정식: file_size_bytes / 4  — 한글·마크다운 기호로 오차가 크므로 항상 "추정치"로 표기한다
  tier별(core / supporting / peripheral) + 전체 집계
  index-only 추정 = (title + summary + tags 길이 합) / 4
  일반 쿼리 추정 = index-only + 상위 5페이지 평균 크기
  token_warn_threshold = 100000 (이 스킬 내 고정 상수).
    기준은 "wiki 전체 로드" 추정치다 — 전체(core+supporting+peripheral)가 초과하면 경고한다.
    index-only·일반 쿼리 추정은 참고용이고 threshold 판정 대상이 아니다

Step 4: log.md 최근 5개 항목 읽기
Step 5: 리포트 출력 (아래)
Step 6: What to Do Next 출력 (아래)
```

## 리포트 형식

```markdown
## Wiki Status — YYYY-MM-DD

### 개요
- 총 wiki 페이지: N개
- 총 ingest 소스: N개
- 마지막 ingest: YYYY-MM-DD {파일명}

### Raw 현황
📥 미처리: N개 → {파일명 목록}
🔄 갱신 필요: N개 → {파일명 목록}
🗑️ 삭제 대기: N개 (ingest 완료 + ingested_at 14일 경과) → {파일명 목록}

### 토큰 풋프린트 추정
| 범위 | 페이지 수 | 추정 토큰 |
|---|---|---|
| core | N | ~K |
| supporting | N | ~K |
| peripheral | N | ~K |
| 전체 | N | ~K |
index-only 패스: ~K tokens
일반 쿼리 (index + 5페이지): ~K tokens
⚠️ [threshold 초과 시] 전체 로드 시 100K 초과 — wiki-query index-only 모드 권장

### 최근 작업 (log.md 최근 5개)
{log.md 항목}
```

## What to Do Next

해당하는 항목만 이 순서로, 최대 5개까지 출력한다.

```
1. 📥 미처리 raw N개        → /wiki-ingest
2. 🔄 갱신 필요 raw N개      → /wiki-ingest
3. 🗑️ 삭제 대기 raw N개      → /wiki-lint --fix
4. 🩺 wiki-lint 마지막 실행: {날짜}  (30일 이상이면 "점검 권장" 표시)
   ※ log.md에서 마지막 LINT 라인을 grep한다 — Step 4의 최근 5개에 없을 수 있다

모두 해당 없으면:
✅ Wiki가 최신 상태입니다. 처리 대기 항목 없음.
```

## 품질 체크

```
□ 삭제 대기·정합성 항목은 개수·목록만 보고 (판정·수정은 wiki-lint)
□ 토큰 수치에 "추정치" 표기 + threshold는 전체 로드 기준으로만 판정
□ raw 판정에 mtime 대신 manifest content_hash·ingested_at 사용
□ 페이지·index·hot·QMD 무수정 (QMD refresh 없음)
□ What to Do Next 를 우선순위 순으로, 없으면 최신 상태 메시지
```

## 안티패턴

| 이렇게 하기 쉽다 | 무엇이 깨지나 | 대신 |
|---|---|---|
| 삭제 대기로 잡힌 raw를 지운다 | 삭제 판정이 두 곳에 생기고 보고 전용 경계가 무너진다 | 개수·목록만. 삭제는 `wiki-lint --fix` |
| 왜 잘못됐는지까지 진단해 보고한다 | lint와 리포트가 겹쳐 두 스킬의 경계가 사라진다 | "무엇이 남았나"만 답한다 |
| mtime으로 미처리·삭제 대기를 판정한다 | git checkout·복사·동기화가 mtime을 깨뜨려 오탐이 난다 | `content_hash`·`ingested_at` |
| 토큰 수를 확정치처럼 제시한다 | `size/4`는 한글·마크다운 기호에서 오차가 커 신뢰를 잃는다 | 항상 "추정치"로 표기 |
| index-only 추정이 threshold를 넘었다고 경고한다 | 판정 기준이 흐려져 경고가 의미를 잃는다 | threshold는 전체 로드 추정에만 적용 |
| 최근 작업 맥락을 정리해 `hot.md`에 반영한다 | 조회가 볼트를 바꾼다 | 읽기만 한다 |
