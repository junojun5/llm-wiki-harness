# Mermaid C4 컨벤션 (wiki-project-design)

Obsidian은 Mermaid를 네이티브로 렌더링한다. 다이어그램이 제 값을 할 때 **C4 L1 (시스템 컨텍스트)**와 **L2 (컨테이너)**에 사용한다 — 절대 빈 다이어그램을 억지로 넣지 않는다. L3 (컴포넌트)는 정말로 복잡한 부분에만. 다이어그램의 *의미* 변경은 semantic 변경이다 → 다른 design 편집과 마찬가지로 `changes/` proposal을 거친다.

## 문법 서브셋
`flowchart TD` (또는 `LR`) 사용. 이색적인 노드 모양/플러그인은 피한다 — 이식성을 유지한다.

## C4 표기법을 flowchart로
- **Person / 외부 액터:** `actor([사용자])`
- **설계 대상 시스템 (L1):** `sys[["결제 게이트웨이"]]`
- **외부 시스템 (L1):** `ext[(FraudCo API)]`
- **컨테이너 (L2):** `c["API 서버<br/>(Spring)"]` — 라벨 = 이름 + 괄호 안 기술.
- **관계:** `a -->|"카드 결제 요청"| b` — 항상 엣지에 상호작용을 라벨링.

## 명명
- 노드 id: 짧은 소문자 (`api`, `db`, `queue`) — 의미 기반, `n1`/`box2` 아님.
- 노드 라벨: 실제 도메인/컨테이너 이름; 기술 스택은 `()`에.
- C4 레벨당 다이어그램 하나; 한 그래프에 여러 레벨을 섞지 않는다.

## 예시 (L2 컨테이너 뷰)
```mermaid
flowchart TD
  actor([가맹점]) -->|"결제 요청"| api["API 서버<br/>(Spring)"]
  api -->|"이벤트 발행"| queue["이벤트 버스<br/>(Kafka)"]
  queue --> worker["정산 워커<br/>(Go)"]
  api -->|"사기 점수 조회"| fraud[(FraudCo API)]
  worker --> db["원장 DB<br/>(Postgres)"]
```

다이어그램은 작게 유지; 한 레벨에 ~10개 넘는 노드가 필요하면 하위 도메인으로 분할한다.
