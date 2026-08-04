---
name: wiki-status
description: ingest 대기 중인 raw 파일, 최근 처리 내역, 볼트 전반 상태를 알고 싶을 때 사용한다. "무엇이 잘못됐나"가 아니라 "무엇이 남았나"에 답하며, 개수·토큰 풋프린트·우선순위 액션 목록을 보고한다. 트리거는 "wiki 상태"·"뭐 쌓여있어"·"ingest 뭐 남았어".
---

# wiki-status

볼트에서 **무엇이 남았나**(진행 상황)를 보고한다. ("무엇이 잘못됐나"는 `wiki-lint`.)

시작 전 `using-llm-wiki` 스킬을 로드한다 — Config Gate, read-only 경계.

> **보고 전용(read-only).** 탐지 기준이 `wiki-lint`와 겹치는 항목(삭제 대기 raw, manifest↔파일 정합성)도 **개수·목록만 보고**한다. 판정 기준의 단일 출처와 수정 권한은 항상 `wiki-lint`에 있다. 유일한 쓰기는 Step 7의 `log.md` append(관찰 기록, §3-6 read-only 경계)이고 그 실패는 스킬 실패가 아니다 — 페이지·`index.md`·`hot.md`는 수정하지 않고 QMD refresh도 하지 않는다.

## 워크플로

```
Step 0:   Config Gate
Step 0.5: wiki/hot.md 읽기 (있으면) — Step 5 "최근 작업" 맥락 보강

Step 1: .manifest.json 읽기 (스키마·소비 패턴: using-llm-wiki/references/manifest.md)
  마지막 ingest 타임스탬프 / 총 소스 수 / 총 wiki 페이지 수
  manifest 없으면 → "아직 ingest된 파일 없음. wiki-ingest를 먼저 실행하세요" 출력 후 Step 4로

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

Step 3.5: 가드 생존 점검 (스펙 §5-5)
  bash ~/.llm-wiki/scripts/check-guards.sh --platform {너를 실행 중인 도구}
  출력: GUARD <platform> <layer> <status> <detail> 라인 + SUMMARY
  exit 0 → 정상·해당없음 / exit 1 → degraded 1건 이상 / exit 2 → 점검 불가
  ⚠️ 이 점검은 **등록과 판정**만 본다. "에이전트가 실제로 훅을 호출하는가"(발화)는
     검증 대상이 아니다 — 리포트에 그 경계를 함께 낸다(아래 형식). 빠뜨리면 초록불이
     거짓 안심이 된다. 특히 Codex는 /hooks trust 전까지 등록 정상 + 무발화다.
  스크립트가 없거나 실행 실패 → "가드 점검 불가(스크립트 없음 — install.sh 재실행)"
     한 줄만 내고 진행한다. 이 스킬의 실패가 아니다.

Step 4: log.md 최근 5개 항목 읽기
Step 5: 리포트 출력 (아래)
Step 6: What to Do Next 출력 (아래)

Step 7: wiki/log.md 상태 조회 기록 (read-only 예외 — 관찰 기록)
  [YYYY-MM-DD] STATUS unprocessed=N recent_ingest="{경로}" token_estimate=K
  ※ read-only 스킬이지만 log append는 허용된다 (§3-6). 리포트는 이미 전달됐으므로
    append 실패는 스킬 실패가 아니다 — 경고 없이 넘어간다(self-healing).
    페이지·index.md·hot.md·QMD는 여전히 건드리지 않는다.
```

## 리포트 형식

```markdown
## Wiki Status — YYYY-MM-DD

### 개요
- 총 wiki 페이지: N개
- 총 ingest 소스: N개
- 마지막 ingest: YYYY-MM-DD {파일명}

### 가드 생존
{전부 정상이면 한 줄로 접는다 — 정상일 때 길면 안 읽는다}
✅ 가드 생존 — {platform} 등록·판정 정상 (발화는 미검증)
{degraded가 있으면 해당 항목만 펼친다}
❌ {platform} — {detail}
   복구: ./install.sh --fallback 재실행
➖ {나머지} — 미설치 / 해당 없음
ⓘ 발화 여부는 검증 대상이 아닙니다 (Codex는 /hooks trust 별도 필요)

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

해당하는 항목만 이 순서로, **최대 4개**까지 출력한다 (§3-8 `NEXT_ACTIONS_MAX` — 정의된 항목이 4개다).

**가드 degraded는 이 목록보다 위다.** 보호가 꺼진 상태는 ingest 대기보다 급하고, 4개 상한과
무관하게 항상 맨 앞에 낸다 — 상한에 밀려 잘리면 이 점검을 만든 이유가 사라진다.

```
0. ❌ 가드 degraded         → ./install.sh --fallback 재실행 후 wiki-status로 재확인
1. 📥 미처리 raw N개        → wiki-ingest
2. 🔄 갱신 필요 raw N개      → wiki-ingest
3. 🗑️ 삭제 대기 raw N개      → wiki-lint --fix
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
□ What to Do Next 를 우선순위 순으로 최대 4개, 없으면 최신 상태 메시지
□ Step 7 STATUS 로그 라인 append (실패는 무시 — 스킬 실패 아님)
□ 가드 리포트에 "발화는 미검증" 경계 문구 포함 (빠지면 초록불이 거짓 안심이 된다)
□ 가드 degraded는 4개 상한과 무관하게 항상 맨 앞
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
| 가드 초록불을 "훅이 동작한다"로 보고한다 | 발화는 검증 대상이 아니다 — Codex는 trust 전까지 등록 정상 + 무발화다 | "등록·판정 정상 (발화는 미검증)" |
| 가드가 degraded면 직접 고쳐 준다 | 진단과 복구가 섞여 read-only 경계가 무너진다 | `install.sh` 재실행을 **안내만** 한다 |
