---
name: wiki-status
description: 사용자가 ingest 대기 중인 raw 파일, 최근 처리된 것, 또는 wiki의 전반적 상태를 알고 싶어 할 때 사용 — "wiki status", "뭐 쌓여있어", "ingest 뭐 남았어", "what's left", "/wiki-status".
---

# wiki-status

**read-only** 진행 리포트: **"뭐가 남았나"이지 "뭐가 깨졌나"가 아니다.** 먼저 Config Gate.

## wiki-lint와의 경계 (엄격)
status는 *할 일이 뭐가 남았나*에 답한다 — ingest 대기, 최근 활동, 크기 풋프린트. 품질 문제는 **보고하지 않는다**: 고아, 깨진 링크, 충돌, `⚠️ unverified` 주장은 **wiki-lint의 영역이며 — 여기서 절대 보고하지 않는다.** 탐지가 겹치는 항목(정리 가능한 raw, manifest↔page 정합성)에 대해서도, status는 **카운트/목록만** 보고하고 판단과 수정은 `/wiki-lint`로 넘긴다. **status는 절대 삭제·수정하거나 삭제를 제안하지 않는다.** read-only다 — 아무것도 쓰지 않는다 (log 줄조차도).

## 워크플로우
0. Config Gate. 0.5 `hot.md` 읽기 (최근 활동 맥락).
1. `.manifest.json` 읽기: 마지막 ingest 타임스탬프, 전체 소스 수, 전체 페이지 수. manifest 없음 → "아직 ingest된 파일 없음. /wiki-ingest를 먼저 실행하세요" → step 4.
2. `raw/`를 manifest와 **`content_hash` 기준(절대 mtime 아님)**으로 스캔:
   - manifest에 없음 → 📥 미처리 (pending ingest)
   - manifest에 있고 해시 다름 → 🔄 갱신 필요
   - manifest에 있고 해시 같음 → skip
   - manifest에 있고 ingest됨 + `ingested_at` >14d → 🗑️ 삭제 대기 — **카운트/목록만 보고; 판단과 삭제는 wiki-lint의 몫(§4-6 체크 15).**
3. **토큰 풋프린트 추정** (Glob `wiki/` 크기; tier는 frontmatter grep으로):
   - tier별(core/supporting/peripheral): N페이지 → ~K 토큰 (≈ bytes/4; "추정치" 라벨 — 한국어 + 마크다운이 왜곡함)
   - index-only 패스 추정; normal-query 추정 (index + top 5 페이지)
   - **full-load 총합**(모든 tier) > 100000 → ⚠️ "전체 로드 시 100K 초과 — wiki-query index-only 모드 권장" (임계값을 넘기는 것은 full-load 총합뿐; 패스별 추정치는 참고용).
4. `log.md` 마지막 5개 항목 읽기.
5. **리포트:** `## 개요` (pages / sources / last ingest) · `## Raw 현황` (📥 🔄 🗑️ 카운트 + 목록) · `## 토큰 풋프린트` (tier 표 + 패스 추정) · `## 최근 작업` (log tail).
6. **What to Do Next** (≤5개 우선순위 액션, 해당하는 것만):
   1. 📥 미처리 raw N개 → `/wiki-ingest`
   2. 🔄 갱신 필요 raw N개 → `/wiki-ingest`
   3. 🗑️ 삭제 대기 raw N개 → `/wiki-lint --fix`
   4. 🩺 wiki-lint 마지막 실행 {date} — log.md에서 마지막 `LINT` 줄 grep (최근 5개 tail보다 오래됐을 수 있음); >30일이면 → "점검 권장".
   해당 없음 → "✅ Wiki가 최신 상태입니다. 처리 대기 항목 없음."
