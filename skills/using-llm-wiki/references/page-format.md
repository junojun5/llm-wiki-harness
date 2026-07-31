# 페이지 포맷 — frontmatter·문서 클래스·전환 절차

볼트 페이지의 형식 단일 출처. 페이지를 쓰는 모든 스킬이 이 파일을 따른다.

기계 규칙(필수 키·enum·길이·형식)은 PostToolUse 훅이 `~/.llm-wiki/scripts/validate-frontmatter.sh`로 매 쓰기마다 자동 검증한다 — 스킬 워크플로에 검증 단계를 따로 두지 않는다. 의미적 필드(`summary`·`tags`·`relationships`·`provenance` 비율)는 스크립트가 생성할 수 없으므로 이 문서를 기준으로 직접 작성한다.

## 파일명 (canonicalization)

- `title:` = 사람이 읽는 이름(한글 가능). **파일명 = slug**으로 분리한다.
- slug: 소문자 ASCII kebab-case 기본. 한글 허용하되 공백→하이픈, 양끝 특수문자 제거, NFC 정규화. 영문 표기가 일반적인 개념은 영문 우선.
- 동음이의·중복은 `-2` suffix. **한 번 정한 slug는 바꾸지 않는다** — QMD 경로·`[[링크]]` 안정성. 부득이 변경 시 들어오는 링크를 함께 갱신한다.

## frontmatter (클래스 ① 페이지 풀세트)

```yaml
---
title: "페이지 제목"
# 검색·인덱싱 기준. 파일명(slug)과 의미 일치 권장

category: summaries | concepts | knowledge | entities | projects
# 페이지 타입 (wiki/ 하위 폴더와 대응)
#   summaries → 소스별 1:1 요약. articles/ books/ papers/ meetings/ 는 raw/ 미러링,
#               web/ 은 URL ingest, sessions/ 는 대화 캡처. knowledge/ 승격은 사용자 명시 요청 시만
#   concepts  → "X란 무엇인가?" 정의형. 스크롤 1~2화면 이내
#   knowledge → ① summaries·concepts에서 증류된 공식 지식 + ② 사용자의 궁금증·조사·경험을
#               종합하는 살아있는 심층 문서. 사용자 주도 생성만. 대형 주제는 서브폴더 허용
#   entities  → 사람·조직 전용 (도구·제품은 knowledge/)
#   projects  → projects/{name}/ 하위 문서 (wiki-project 스킬군 소유)

tags: [tag1, tag2]        # 도메인·주제 태그 최대 5개

sources: ["raw/경로 또는 URL"]
# 원본 출처. 우선순위:
#   1순위 "https://example.com/article"  → 원본 URL (raw 파일 frontmatter의 source_url: 에서 추출)
#   2순위 "raw/articles/topic/file.md"   → URL이 없을 때만 raw 경로로 fallback
#         (raw는 14일 후 삭제되므로 URL이 영구 기록에 적합)
#   특수  "conversation:YYYY-MM-DD"      → 대화 기반 (wiki-capture)

created: YYYY-MM-DD       # 페이지 최초 생성일
updated: YYYY-MM-DD       # 마지막 수정일. (오늘 - updated) > 90일 → wiki-query가 stale 표시

summary: "요약 (≤400자)"
# wiki-query cheap retrieval path의 핵심. 있으면 frontmatter grep만으로 답변 가능,
# 없으면 전체 페이지 읽기가 강제된다. QMD 벡터 인덱싱의 핵심 임베딩 소스.
# 400자 초과 = 페이지 범위가 너무 넓다는 신호 → 서브폴더 분할 검토

status: verified | unverified | conflict | archived
#   verified   → 출처 확인 완료
#   unverified → 대화 기반·출처 미확인 (wiki-capture 기본값), [NEEDS CLARIFICATION] 잔존 문서
#   conflict   → 다른 소스와 충돌, 사용자 판단 대기 (본문 ## Conflicts 필수)
#   archived   → 폐기. wiki/archived/로 이동됨

base_confidence: 0.0-1.0
# 소스 유형별 신뢰도. paper=0.9 / official=0.85 / project=0.8 / repository=0.75 /
# blog=0.55 / conversation=0.42 / forum=0.4 / unknown=0.35 / change proposal=0.3(최저)
# 소스의 속성이므로 archive돼도 불변이다
#
# project=0.8 — projects/ 스냅샷 문서(overview·context·goals·architecture·domain·conventions).
#   형식상 인터뷰(=대화) 산출물이지만 **그 프로젝트에 관한 한 1차 사료**다. conversation=0.42를
#   쓰면 "내 프로젝트의 아키텍처 결정 근거"가 임의의 블로그(0.55)보다 낮게 랭킹되는 왜곡이 생긴다.
#   문장 단위 신뢰도는 본문 (출처: [[page]])·⚠️ unverified가 담당하므로, 페이지 스칼라는
#   "이 문서가 이 주제에 갖는 권위"로 읽는다. sources: 는 ["conversation:YYYY-MM-DD"]를 그대로 쓴다.
# unknown=0.35 — forum과 같은 0.4면 frontmatter만으로 두 유형을 구분할 수 없어
#   "ingest-url fallback으로 들어온 페이지"를 감사할 수 없다. 값을 분리해 식별 가능하게 한다.

# ─── 선택 필드 ───────────────────────────────────────────
tier: core | supporting | peripheral
# wiki-query 랭킹 우선순위. 미설정 = supporting 취급
#   core → 동점 시 먼저 읽힘 / peripheral → 유일한 매치일 때만 읽힘

relationships:
  - target: "[[related-concept]]"
    type: uses | contradicts | extends | depends_on | related_to
# wiki-query가 탐색하는 typed edge. 방향·타입이 명확할 때만 작성, 애매하면 related_to 또는 생략
#   uses=target 개념을 활용 / contradicts=상충(충돌 근거) / extends=확장·심화
#   depends_on=선수 지식 전제 / related_to=방향 불명확한 일반 연관

provenance:
  extracted: 0.0-1.0      # 원본에서 직접 추출한 claim 비율 (기본값 — 마커 없는 나머지)
  inferred: 0.0-1.0       # 추론·일반화 비율 (본문 ^[inferred] 마커)
  ambiguous: 0.0-1.0      # 불확실·논쟁적 비율 (본문 ^[ambiguous] 마커)
# 합 = 1.0 ± 0.05 (validator 허용오차). 대화 기반·추론 비중이 높은 페이지에 설정.
# 공식 소스 ingest만 있는 페이지는 생략 (= 전부 extracted = 1.0으로 간주)
# ⚠️ **provenance·relationships는 반드시 위와 같은 블록 표기다.** 세 비율을 한 줄짜리
#   인라인 flow mapping(중괄호)으로 적으면 validator가 그 값을 스칼라 문자열로 읽어
#   검사 자체가 무의미해진다 — 그래서 validator는 "키는 있는데 dict/list로 파싱되지 않으면
#   에러"로 끊는다. 인라인으로 쓰면 페이지 쓰기가 실패한다. relationships도 같은 함정이 있다.

superseded_by: "[[replacement-page]]"   # archived 페이지가 무엇으로 대체됐는지
status_changed: YYYY-MM-DD              # status 마지막 변경일 (status 변경 시 함께 갱신)
---
```

본문은 짧은 문단·명확한 제목·`[[wiki-link]]` 내부 링크로 쓰고, 끝에 `## Related pages` 섹션을 둔다.

### 파서 호환성 — 수용된 한계

중첩 필드(`relationships`·`provenance`)는 **머신 전용 필드**다. 표준 YAML 파서(QMD·yq)는 정상 해석하지만 Obsidian은 Properties UI에서 편집할 수 없고 중첩 안의 `"[[wikilink]]"`를 그래프·백링크로 인식하지 않는다. 이 필드들의 소비자는 `wiki-query`(머신)이지 Obsidian 그래프(사람)가 아니므로 수용한다 — 사람용 연결은 본문 `[[wiki-link]]`와 `## Related pages`가 담당한다.

## 문서 클래스 — frontmatter 적용 범위

status enum이 클래스마다 다른 이유: 세 라이프사이클(출처 신뢰 / 제안 수명 / 사건 수명)은 의미가 직교하므로 하나의 enum으로 합치면 검색 강등·인용 로직이 의미를 잃는다.

| 클래스 | 대상 | status enum | 필수 frontmatter |
|---|---|---|---|
| ① 페이지 | summaries·concepts·knowledge·entities + projects의 overview·context·goals·architecture·domain·conventions + 모든 meetings | `verified\|unverified\|conflict\|archived` | 풀세트 9키 |
| ② 라이프사이클 | `projects/*/changes/*` · `projects/*/troubleshooting/*` | changes=`proposed\|applied\|rejected` · troubleshooting=`open\|resolved` | 축소셋 |
| ③ 원장(ledger) | `projects/*/decisions.md` · `projects/*/backlog.md` · `index.md` · `log.md` · `hot.md` | — | frontmatter 검증 제외 |

- **① 풀세트 9키:** `title` `category` `tags` `sources` `created` `updated` `summary` `status` `base_confidence`
- **② changes/ 축소셋:** `title` `category`(=projects) `project` `targets` `status` `created` `status_changed` `summary` `base_confidence` `tier` — `tags`·`sources`·`updated` 비필수(델타 문서라 근거는 본문 `## 근거`의 `[[링크]]`가 담당)
- **② troubleshooting/ 축소셋:** `title` `category`(=projects) `status` `created` `updated` `summary` — `base_confidence`·`sources` 없음(출처 파생 페이지가 아니다)
- **③ 원장:** 의미 단위가 파일이 아니라 항목(`## 헤딩`)이라 파일 레벨 `summary`·`status`가 무의미하다. frontmatter 검증에서 제외하고, 내부 구조(append-only·항목 형식·짝)는 `wiki-lint`가 검증한다.

## provenance 산정 — 마커가 진실, frontmatter는 캐시

- **분모 = claim 수:** 본문의 문장 1개 또는 리스트 항목 1개 = claim 1개. heading·코드블록·인용블록·frontmatter·`## Related pages`는 분모에서 제외한다.
- `inferred` = `^[inferred]` 마커가 붙은 claim 수 / 전체 claim 수
- `ambiguous` = `^[ambiguous]` 마커가 붙은 claim 수 / 전체 claim 수
- `extracted` = 1 − inferred − ambiguous (마커 없는 나머지 — **extracted가 기본값**이고, inferred/ambiguous는 기본에서 벗어났음을 알리는 능동적 자기표시다)

**책임 분업:** 쓰기 스킬이 마커를 달고 비율을 눈대중 추정해 저장 → `wiki-lint`가 마커로 재계산해 검산·교정. 둘이 어긋나면 **항상 본문 마커 기준으로 frontmatter를 고친다.**

⚠️ 사각지대: 추론한 문장에 마커를 누락하면 조용히 extracted로 집계돼 페이지가 실제보다 출처에 충실해 보인다 — lint의 재계산도 마커를 세므로 누락은 잡지 못한다. 마커를 성실히 다는 것이 이 비율의 유일한 신뢰 기반이다.

## status 전환 — archive·복원

archive는 frontmatter 전반 변경이 아니라 **status 계열만 변경**한다. 검색 강등은 `status: archived` 하나가 담당한다 (단일 강등 메커니즘).

```
변경:  status → archived / status_changed → 오늘 / updated → 오늘
       superseded_by → "[[대체 페이지]]" (있으면) / 본문 상단에 폐기 사유·날짜 노트

보존:  base_confidence · tier · tags · sources · created
       — 소스 유형·내용의 속성이지 현행성이 아니다. 폐기돼도 "그 논문이 논문이었다"는
         사실은 불변이고, 값을 바꾸면 복원 시 원래 값을 잃는다.

파일:  wiki/archived/로 이동 → 종료 시퀀스(index → log → hot → QMD refresh)
```

들어오는 링크는 깨진 채로 둔다 — `wiki-lint`가 보고한다.

**복원(승격)은 역방향:** status 원복 + `superseded_by` 제거 + `status_changed`·`updated` 갱신 + 원위치 이동. 보존 필드는 그대로이므로 추가 작업이 없다.

## 충돌 노트 표준 포맷

충돌은 ingest 전용 사건이 아니다 — 모든 쓰기 스킬에서 발생할 수 있다. 발견 시 본문에 `## Conflicts` 섹션을 두고 기록한다.

```markdown
## Conflicts
- claim: "충돌하는 주장 한 줄"
  sources: [[소스-A]] vs [[소스-B]]
  status: open
- claim: "이전에 해소된 주장"
  sources: [[소스-C]] vs [[소스-D]]
  status: resolved (YYYY-MM-DD, 채택: [[소스-C]], 사유: 한 줄)
```

- **판단 주체는 사용자, 기록 주체는 LLM.** 발견 시 `open`으로 기록하고 사용자에게 채택을 묻는다. 결정되면 같은 항목을 `resolved(...)`로 갱신한다.
- resolved 항목은 삭제하지 않는다 — 의사결정 이력이다.
- **불변식: frontmatter `status: conflict` ⟺ `## Conflicts`에 open 항목 ≥ 1.** 전부 resolved되면 frontmatter를 `verified`로 복귀시킨다.
