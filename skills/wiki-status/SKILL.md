---
name: wiki-status
description: ingest 대기 raw·처리 현황·볼트 상태를 확인할 때 사용 — "남은 거 뭐야?", "볼트 상태", "뭐 쌓여있어", "ingest 뭐 남았어", "/wiki-status".
---

# wiki-status

## 개요
ingest 대기 raw, 최근 처리 내역, 토큰 풋프린트 등 **볼트의 진행 상황**을 보고하는 read-only 스킬이다. 먼저 Config Gate.

## wiki-lint와의 경계
status는 *"무엇이 남았나"*에 답한다 — ingest 대기, 최근 활동, 크기 풋프린트. status는 **보고 전용(read-only)**이다.

품질 문제는 여기서 다루지 않는다: 고아 페이지, 깨진 링크, 충돌, `⚠️ unverified` 주장은 **wiki-lint의 영역**이며 — *"무엇이 깨졌나"*에 답한다.

탐지 기준이 겹치는 항목(삭제 대기 raw, manifest↔파일 정합성)도 status는 **개수·목록만** 보고한다. 판정 기준의 단일 출처와 수정 권한은 항상 wiki-lint에 둔다 — 삭제 대기 raw의 삭제 기준·실행은 wiki-lint 체크 15가 SoT다. status는 절대 삭제·수정하거나 삭제를 제안하지 않는다.

status가 쓰는 것은 Step 7의 log append(관찰 기록) 하나뿐이다 — 페이지·`index.md`·`hot.md`·QMD는 건드리지 않는다.

## 워크플로우
**Step 0 — Config Gate.**

**Step 0.5 — `wiki/hot.md` 읽기(있으면).** 최근 활동을 파악해 Step 5 "최근 작업" 맥락을 보강한다.

**Step 1 — `.manifest.json` 읽기.**
- 마지막 ingest 타임스탬프, 총 소스 수, 총 wiki 페이지 수.
- manifest가 없으면 → "아직 ingest된 파일 없음. /wiki-ingest를 먼저 실행하세요" 출력 후 Step 2(raw 스캔)·Step 3(토큰 풋프린트)을 건너뛰고 Step 4(log.md 읽기)로.

**Step 2 — `raw/` 스캔 vs `.manifest.json` 비교 (`content_hash` 기준, 절대 mtime 아님).** 각 raw 파일에 대해:
- manifest에 없음 → 📥 미처리 (ingest 대기)
- manifest에 있고 content_hash 다름 → 🔄 갱신 필요
- manifest에 있고 content_hash 같음 → skip
- manifest에 있고 ingest 완료 + manifest의 `ingested_at` 기준 14일 초과 → 🗑️ 삭제 대기 (**보고만**)
  - 판정 기준·삭제 권한은 wiki-lint(체크 15)가 단일 출처. status는 개수·목록만 보고하고 삭제하지 않는다.
  - mtime은 git checkout·복사·동기화로 깨질 수 있어 `ingested_at`을 채택한다.

**Step 3 — 토큰 풋프린트 추정.**
- `wiki/` 전체 `.md` 파일 size 합산(Glob).
- frontmatter grep으로 tier 분류(core/supporting/peripheral; 미설정은 supporting).
- 추정 공식: `file_size_bytes / 4`(4자/token 근사) — 한글·마크다운 기호로 오차가 크므로 항상 "추정치"로 표기한다.
- tier별 집계: core / supporting / peripheral / 전체 각각 N개 → ~K tokens.
- index-only 추정(title + summary + tags 길이 합 / 4), 일반 쿼리 추정(index-only + 상위 5페이지 평균 크기)도 함께 산출.
- `token_warn_threshold`(wiki-status 내 고정 상수, 100000) — 판정 대상은 **전체(core+supporting+peripheral) 추정값**뿐이다. index-only·일반 쿼리 추정은 참고용이며 threshold 판정 대상이 아니다. 전체 추정값이 threshold를 초과하면 경고를 리포트에 포함한다.

**Step 4 — `log.md` 최근 5개 항목 읽기.**

**Step 5 — 리포트 출력.**
```
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
| 범위         | 페이지 수 | 추정 토큰 |
|------------|---------|---------|
| core       | N       | ~K      |
| supporting | N       | ~K      |
| peripheral | N       | ~K      |
| 전체        | N       | ~K      |
index-only 패스: ~K tokens
일반 쿼리 (index + 5페이지): ~K tokens
⚠️ [threshold 초과 시] 전체 로드 시 100K 초과 — wiki-query index-only 모드 권장

### 최근 작업 (log.md 최근 5개)
{log.md 항목}
```

**Step 6 — What to Do Next (우선순위 액션, 최대 5개, 해당하는 것만 출력).**
```
1. 📥 미처리 raw N개 → /wiki-ingest
2. 🔄 갱신 필요 raw N개 → /wiki-ingest
3. 🗑️ 삭제 대기 raw N개 → /wiki-lint --fix
4. 🩺 wiki-lint 마지막 실행: {날짜} (30일 이상이면 "점검 권장" 표시)
   ※ log.md에서 마지막 LINT 라인을 grep — Step 4의 최근 5개 tail에는 없을 수 있다.
```
모두 해당 없으면 → "✅ Wiki가 최신 상태입니다. 처리 대기 항목 없음."

**Step 7 — `wiki/log.md` 상태 조회 기록** (read-only 예외 — 관찰 기록, §3-6 "read-only 스킬의 경계"):
```
[YYYY-MM-DD] STATUS unprocessed=N recent_ingest="{경로}" token_estimate=K
```
log append 실패해도 리포트는 이미 전달됐으므로 스킬 실패가 아니다(self-healing).
