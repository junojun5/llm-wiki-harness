---
name: wiki-setup
description: 새 LLM Wiki 볼트를 초기화하거나 깨진 볼트 설정을 복구할 때 사용. 다른 어떤 wiki 스킬보다 먼저 실행되어야 한다. 볼트 설정과 전역 볼트 포인터를 세팅한다.
---

# wiki-setup

볼트를 초기화하거나 복구한다. **Config Gate가 존재하기 전에 실행되는 유일한 스킬** — 게이트가 읽는 설정을 이 스킬이 만들기 때문에, 스스로 resolve-vault.sh를 호출하지 않는다.

## 모드
- `/wiki-setup` — 대화형 초기화.
- `/wiki-setup --vault <path> [--yes]` — 비대화형.
- `/wiki-setup --update-path` — 이동·이름변경된 볼트로 재지정 (설정 + 포인터 갱신). 상세는 아래 "재지정·재정합 워크플로우".
- `/wiki-setup --repair` — 누락된 설정/디렉터리/템플릿 재생성.
- `/wiki-setup --update-qmd` — 전체 QMD 재정합 (컬렉션 전체 reconcile). 스킬 밖에서 수동 편집/이동한 후, 또는 QMD stale이 반복될 때(§3-5 self-healing 에스컬레이션) 사용. 상세는 아래 "재지정·재정합 워크플로우".

**멱등(Idempotent) — 존재 여부만 확인.** 아래의 모든 파일/디렉터리는: 없으면 생성, 있으면 그대로 둔다. 포맷이 오래돼 보여도 기존 내용을 절대 덮어쓰지 않는다 — stale 포맷 진단은 `wiki-lint --fix`의 일이지 setup의 일이 아니다.

## 워크플로우
1. 볼트 절대 경로를 묻는다 (또는 `--vault` 사용).
2. `raw_dir="raw"`, `wiki_dir="wiki"` 제안 → 확인.
3. `<vault>/.wiki-config.json` 작성 (스키마 최소주의 — "볼트가 어디인가"에만 답함; QMD/플래그/기능 키 없음):
   ```json
   { "version": 1, "vault": { "path": "<abs>", "wiki_dir": "wiki", "raw_dir": "raw" }, "created": "YYYY-MM-DD" }
   ```
4. 전역 포인터 `~/.llm-wiki/default-vault` = 볼트 절대 경로, 한 줄. 이미 존재하고 다르면 `old → new`를 보여주고 덮어쓰기 전에 확인 (`.bak` 없음 — 되돌리려면 `--update-path` 재실행). **`--yes`에서도, *다른* 볼트를 가리키는 포인터를 조용히 덮어쓰지 않는다 — 중단하고 `--update-path`를 명시적으로 실행하라고 사용자에게 알린다** (비대화형이 다른 볼트의 포인터를 가로채선 안 된다). 이것이 스킬이 어느 디렉터리에서든 볼트를 resolve할 수 있게 해준다.
5. 없으면 고정 디렉터리 생성: `wiki/concepts/ wiki/knowledge/ wiki/entities/ wiki/projects/ wiki/meetings/ wiki/archived/`. **`wiki/summaries/*` 하위 폴더는 생성하지 않는다** — ingest가 `raw/`를 미러링하며 만든다 (YAGNI). raw/ 하위 폴더, benchmark/, meta/ 는 생성하지 않는다.
6. `wiki/index.md` — 없으면, 빈 카테고리 섹션을 가진 초기 템플릿: summaries / concepts / knowledge / entities / projects.
7. `wiki/log.md` — 없으면, 날짜가 찍힌 `INIT — vault created` 항목으로 plaintext 시드 (원장; frontmatter 없음).
8. `wiki/hot.md` — 없으면, 다음 정본 템플릿 (단일 출처; 다른 스킬은 "§4-1 Step 8 template"으로 인용):
   ```
   ---
   title: Hot Cache
   updated: YYYY-MM-DD
   ---
   # Hot Cache
   *A ~500-word semantic snapshot of recent activity.*
   ## Recent Activity
   - [TIMESTAMP] INIT — vault created
   ## Active Threads
   *None yet.*
   ## Key Takeaways
   *None yet.*
   ## Flagged Contradictions
   *None yet.*
   ```
   복구 예외: `log.md`는 있는데 `hot.md`가 없으면, log.md의 마지막 ~10개 항목으로 Recent Activity를 재구성한다.
9. QMD — "qmd가 설치돼 있나요?" 묻는다.
   - 설치됨 → `${QMD_CLI:-qmd} collection add <vault>/<wiki_dir> --name wiki` (`qmd collection list`에 이미 경로가 있으면 생략), 이어서 `qmd update`. QMD 설정은 어디에도 저장하지 않는다 — qmd 자체 레지스트리가 단일 출처. 빈 볼트: `update`만, `embed` 없음.
   - 설치 안 됨 → "Grep fallback으로 동작합니다. 설치 후 `/wiki-setup --update-qmd` 가능."
10. `<vault>/.manifest.json` — 없으면, `{ "version": 1 }`.
11. `<vault>/.wiki-config.example.json` — 절대 경로를 제거한 빈 템플릿 (git 추적 대상).
12. 볼트가 git 저장소면, `.gitignore`에 `.wiki-config.json`이 있는지 확인 (머신별 절대 경로); `.example`은 추적 상태로 유지.
13. 생성한 것 vs 이미-존재-확인된 것의 sanity-check 목록을 출력한다.

## 재지정·재정합 워크플로우

### `--update-path` (볼트 재지정)
1. 사용자에게 새 볼트 절대 경로를 묻는다.
2. `<vault>/.wiki-config.json`의 `vault.path`를 새 경로로 갱신한다.
3. 전역 포인터 `~/.llm-wiki/default-vault`를 새 경로로 갱신한다 — 기존 값이 다른 경로면 Step 4와 동일하게 `old → new`를 보여주고 확인 후 덮어쓴다.
4. 경로 유효성 확인: `wiki/index.md`, `wiki/log.md`, `wiki/hot.md` 존재 여부를 점검하고 결과를 보고한다.

### `--update-qmd` (전체 QMD 재정합)
per-skill refresh(§3-5)가 쓰기마다 증분 갱신하지만, QMD를 껐다 켠 사이 쓰기가 누적됐거나·머신을 옮겼거나·git pull/외부 편집으로 볼트가 스킬 밖에서 바뀌면 일괄 reconcile이 필요하다.
1. **QMD 게이트 판정 (§3-5).** CLI 미설치 → 설치 안내 후 중단. 컬렉션 미등록 → Step 9의 등록(`${QMD_CLI:-qmd} collection add <vault>/<wiki_dir> --name wiki`)부터 수행.
2. **§3-5 명령 시퀀스를 컬렉션 전체에 적용:** `${QMD_CLI:-qmd} update` (볼트 전체 해시 스캔 — 신규·변경·삭제 반영) → (update가 벡터 필요를 보고하면; 전체 reconcile은 대개 필요) `${QMD_CLI:-qmd} embed` → `${QMD_CLI:-qmd} ls "$QMD_WIKI_COLLECTION"`로 **컬렉션 전체 가시성 검증**. per-skill refresh의 단일 페이지 검증과 달리, 여기선 `qmd ls`로 컬렉션 전체를 확인한다.
3. **`log.md` 기록:** `[YYYY-MM-DD] QMD-RECONCILE pages_indexed=N embedded=true|false`.
4. **§3-5 상태 문자열로 결과 보고.** QMD 실패는 볼트를 롤백하지 않고 QMD 상태만 별도 보고한다.

install.sh는 플랫폼에 스킬/스크립트/훅을 배포한다; wiki-setup은 *볼트*만 설정한다.
