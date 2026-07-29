---
name: wiki-setup
description: 새 wiki 볼트를 초기화하거나 깨진 볼트 설정을 복구할 때 사용한다. 다른 모든 wiki 스킬보다 먼저 실행해야 한다. vault root에 .wiki-config.json, 고정 wiki 서브디렉터리, index·log·hot 파일을 만든다. 볼트가 이동했을 때(--update-path)와 검색 인덱스 전체 재정렬(--update-qmd)도 담당한다. 트리거는 "wiki 초기화"·"볼트 설정"·"set up wiki", 그리고 resolver가 안내한 복구 경로.
---

# wiki-setup

볼트를 사용 가능한 상태로 만드는 유일한 스킬이다. 다른 모든 wiki 스킬의 선행 조건이며, `resolve-vault.sh`가 실패했을 때의 복구 경로도 전부 여기로 모인다.

공통 규칙·QMD 게이트·`hot.md` 템플릿은 `using-llm-wiki` 스킬을 로드해 그 정의를 따른다. 이 스킬은 config를 **만드는** 쪽이므로 Config Gate를 선행 실행하지 않는다.

## 모드

| 호출 | 하는 일 |
|---|---|
| `/wiki-setup` | 신규 초기화 (아래 워크플로) |
| `/wiki-setup --vault <path> [--yes]` | 비대화형 초기화 |
| `/wiki-setup --repair` | config 경로 재검증 + 필수 파일 복구 |
| `/wiki-setup --update-path` | 볼트가 이동했거나 머신을 옮긴 경우 경로 재지정 |
| `/wiki-setup --update-qmd` | 검색 인덱스 전체 reconcile |

## 워크플로 — 신규 초기화

```
Step 1: 사용자에게 볼트 절대경로를 묻는다
Step 2: raw_dir·wiki_dir 기본값("raw", "wiki")을 제안하고 확인받는다
Step 3: vault root에 .wiki-config.json 생성

  {
    "version": 1,
    "vault": { "path": "/절대경로/vault", "wiki_dir": "wiki", "raw_dir": "raw" },
    "created": "YYYY-MM-DD"
  }

  이 파일은 "이 머신에서 볼트가 어디 있는가" 한 가지만 답한다.
  QMD 설정·스킬 버전·기능 플래그를 추가하지 않는다 (스키마 최소주의).

Step 4: ~/.llm-wiki/default-vault 생성 — 볼트 절대경로 한 줄
  이미 존재하고 다른 경로를 가리키면 기존 값을 보여주고 확인 후 덮어쓴다:
    "현재 기본 볼트: {기존} → {새 경로}로 변경할까요?"
  .bak 백업은 만들지 않는다 — 한 줄 포인터이고 이전 값이 대화에 남으므로
  되돌리기는 그 경로로 --update-path 한 번이면 된다.

Step 5: 고정 wiki 서브디렉터리 생성 (없으면 생성, 있으면 유지)
  wiki/concepts/ wiki/knowledge/ wiki/entities/
  wiki/projects/ wiki/meetings/ wiki/archived/
  ※ wiki/summaries/ 하위는 만들지 않는다 — raw/ 와 1:1 미러링이므로 ingest 시점에 생성

Step 6~8: wiki/index.md · log.md · hot.md 없으면 생성 (있으면 유지)
  세 파일의 형식·템플릿은 using-llm-wiki 의 references/derived-files.md 가 단일 출처다
  index.md → 카테고리 섹션 없는 빈 목차
  log.md   → [YYYY-MM-DD] INIT vault="{경로}"
  hot.md   → 빈 템플릿 (파생물이라 새 볼트의 활동은 0이 올바른 초기 상태)

Step 9: QMD 설정
  "QMD가 설치돼 있나요? (https://github.com/tobi/qmd)"
  설치 확인 시:
    a. 컬렉션 등록 (1회성):
       ${QMD_CLI:-qmd} collection add {vault}/{wiki_dir} --name wiki
       collection list에서 경로 매칭으로 이미 등록됐으면 스킵
    b. ${QMD_CLI:-qmd} update
       빈 볼트는 임베딩할 내용이 없으므로 embed는 불필요하다
  미설치 시: "Grep fallback으로 동작합니다. 설치 후 /wiki-setup --update-qmd 실행 가능"
  ※ QMD 설정은 어디에도 저장하지 않는다 — qmd 자체 레지스트리가 단일 출처다

Step 10: .manifest.json 없으면 { "version": 1 } 로 생성 (있으면 유지)
Step 11: Sanity check — 생성·확인된 항목 목록을 출력
Step 12: .wiki-config.example.json 생성 (절대경로를 비운 템플릿, git 추적용)
```

`.wiki-config.json`은 `.gitignore` 대상이다(절대경로가 머신마다 다르다). `.wiki-config.example.json`만 git이 추적한다.

## 기존 파일 보존 — 존재 여부만 본다

`index.md`·`log.md`·`hot.md`는 **존재만 확인**한다. 있으면 내용 불문 유지한다 — 포맷이 낡았거나 frontmatter가 없어도 손대지 않는다. 포맷 노후의 진단·보강은 `wiki-lint --fix`의 책임이다. "백업 후 재생성"은 하지 않는다: 사용자 데이터를 LLM이 재생성하는 것은 위험하고, 백업은 git의 일이다.

## 비대화형 모드 — `--vault <path> [--yes]`

- `--vault <path>` → Step 1 질의를 생략하고 해당 경로를 사용한다.
- `--yes` → Step 2 기본값 등 모든 확인을 기본값 수락으로 진행한다.
- **예외:** Step 4에서 전역 포인터가 이미 **다른 볼트**를 가리키면 `--yes`여도 덮어쓰지 않는다 — 경고만 출력하고 유지한다. 새 볼트는 CWD 탐색으로 동작하므로 기능 손실이 없고, 포인터 변경은 `--update-path`로만 한다. 비대화형에서 파괴적 변경은 보수적으로 다룬다.

## `--repair`

기존 `.wiki-config.json`의 경로를 재검증하고, `wiki/index.md`·`log.md`·`hot.md`가 없으면 재생성한다(hot.md는 log.md가 있으면 최근 ~10개 항목으로 Recent Activity를 재구성한다). 기존 파일은 덮어쓰지 않는다. **전역 포인터는 건드리지 않는다** — repair의 책임은 현재 볼트의 config·필수 파일 복구까지다.

## `--update-path`

```
1. 사용자에게 새 볼트 절대경로를 묻는다
2. .wiki-config.json의 vault.path 갱신
3. ~/.llm-wiki/default-vault 갱신
   기존 값이 다른 경로면 Step 4와 동일하게 기존 경로를 보여주고 확인 후 덮어쓴다
4. 경로 유효성 확인 — wiki/index.md · log.md · hot.md 존재 여부
```

## `--update-qmd` — 전체 reconcile

per-skill refresh가 인덱스를 누적적으로 유지하지만, QMD를 껐다 켠 사이 쓰기가 누적됐을 때·머신을 옮겼을 때·git pull이나 외부 편집으로 볼트가 스킬 밖에서 바뀌었을 때는 일괄 reconcile이 필요하다.

```
1. QMD 게이트 판정 (using-llm-wiki)
   CLI 미설치 → 설치 안내 후 종료
   컬렉션 미등록 → Step 9-a 등록부터 수행
2. ${QMD_CLI:-qmd} update                      # 볼트 전체 해시 스캔 — 신규·변경·삭제 반영
   ${QMD_CLI:-qmd} embed                       # update가 벡터 필요를 보고할 때 (전체 reconcile은 대개 필요)
   ${QMD_CLI:-qmd} ls "$QMD_WIKI_COLLECTION"   # 단일 페이지 대신 컬렉션 전체 가시성 검증
3. log.md 기록:
   [YYYY-MM-DD] QMD-RECONCILE pages_indexed=N embedded=true|false
4. 상태 문자열로 결과 보고
```

`qmd update`는 컬렉션 전체 스캔이므로 "전체 재인덱싱 전용 스킬"은 두지 않는다 — 드리프트 복구는 이 모드가 전담한다.

## 품질 체크

```
□ .wiki-config.json 필수 키(vault.path 절대경로·wiki_dir·raw_dir) 완비
□ ~/.llm-wiki/default-vault 가 이 볼트를 가리킴 (또는 타 볼트 보호로 의도적 미변경)
□ 고정 서브디렉터리 6개 + index.md · log.md · hot.md 존재
□ 기존 파일을 덮어쓰지 않음
□ .manifest.json · .wiki-config.example.json 존재
□ bash ~/.llm-wiki/scripts/resolve-vault.sh 가 exit 0 + 세 값을 출력
□ QMD 상태 문자열을 최종 리포트에 포함
```

## 안티패턴

| 이렇게 하기 쉽다 | 무엇이 깨지나 | 대신 |
|---|---|---|
| 기존 `index.md`·`log.md`·`hot.md`를 열어보고 "포맷이 낡았다"며 보강 | setup과 lint가 같은 책임을 갖게 되고, 사용자 데이터를 LLM이 재생성한다 | **존재 여부만** 확인하고 있으면 유지. 포맷 진단·보강은 `wiki-lint --fix`로 안내 |
| 덮어쓰기 전에 `.bak` 백업 파일을 만든다 | 볼트에 관리 주체 없는 파일이 쌓인다 | 확인 대화에 이전 값을 보여주는 것으로 갈음. 백업은 git의 일이다 |
| `--yes`니까 전역 포인터도 새 볼트로 덮어쓴다 | 다른 볼트를 쓰던 세션이 조용히 이 볼트로 끌려온다 | 타 볼트를 가리키면 **경고만 하고 유지**. 새 볼트는 CWD 탐색으로 동작하므로 손실이 없다 |
| `--repair`에서 전역 포인터까지 손본다 | repair가 "현재 볼트 복구"를 넘어 기본 볼트를 바꾼다 | 포인터 변경은 `--update-path` 전용 |
| `wiki/summaries/articles/` 같은 하위 폴더를 미리 만든다 | `raw/` 1:1 미러링 불변식과 어긋난 빈 폴더가 남는다 | 고정 6개만 만들고, summaries 하위는 ingest 시점에 `raw/` 구조에 맞춰 생성 |
| QMD 컬렉션명·CLI 경로·enabled를 `.wiki-config.json`에 적는다 | 같은 사실이 두 곳에 생겨 config와 qmd 레지스트리가 갈라진다 | config는 "볼트가 어디 있는가"만 답한다. QMD 상태는 매번 런타임 게이트로 판정 |
| `collection add` 없이 `qmd update`부터 실행한다 | 인덱싱 대상이 없어 조용히 아무 일도 일어나지 않는다 | Step 9-a 등록을 먼저(기등록이면 경로 매칭으로 스킵) |
| 새 볼트에 `qmd embed`까지 돌린다 | 임베딩할 내용이 0인데 고비용 모델 추론을 태운다 | 빈 볼트는 `update`만. embed는 `--update-qmd`나 실제 쓰기 이후에 |
| QMD 단계가 실패해서 생성한 config·폴더를 되돌린다 | source of truth(볼트)를 사본(인덱스) 때문에 버린다 | 볼트는 그대로 두고 QMD 상태 문자열로만 보고 |
| resolver가 실패해서 볼트 경로를 추론해 넣는다 | 엉뚱한 디렉터리가 볼트로 등록된다 | 경로는 **사용자에게 묻거나** `--vault`로 받는다 |
