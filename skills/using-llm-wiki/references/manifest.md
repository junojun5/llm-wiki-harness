# `.manifest.json` — ingest 원장

볼트 루트의 ingest 원장. **소스 1건 = 엔트리 1개**이고, 어떤 소스가 어떤 페이지를 낳았는지가 여기에만 남는다 — `raw/`는 14일 후 삭제되므로 영구 기록은 summaries 페이지의 `sources:` 와 이 파일 둘이다.

형식 단일 출처는 이 파일이고, `wiki-ingest`·`ingest-url`·`wiki-status`·`wiki-lint`가 인용한다.

## 동형 스키마 — raw 소스와 URL 소스가 같은 필드셋을 쓴다

소비자(`wiki-status` Step 2, `wiki-lint` 항목 15·17)가 **모든 엔트리에 `content_hash`·`ingested_at`이 있다고 가정**하므로 유형별 분기를 만들지 않는다.

```json
{
  "version": 1,
  "raw/articles/ai-ml/attention.md": {
    "source_type": "document",
    "source_url": "https://example.com/attention",
    "content_hash": "sha256:<64-hex>",
    "ingested_at": "2026-07-31T10:00:00Z",
    "size_bytes": 12345,
    "modified_at": "2026-07-30T22:00:00Z",
    "pages_created": ["summaries/articles/ai-ml/attention.md"],
    "pages_updated": ["concepts/attention-mechanism.md"]
  },
  "https://karpathy.bearblog.dev/llm-wiki/": {
    "source_type": "url",
    "source_url": "https://karpathy.bearblog.dev/llm-wiki/",
    "content_hash": "sha256:<64-hex>",
    "ingested_at": "2026-07-31T11:00:00Z",
    "pages_created": ["summaries/web/AI-ML/karpathy-llm-wiki.md"],
    "pages_updated": []
  }
}
```

## 필드

| 필드 | 규칙 |
|---|---|
| **키** | raw 소스는 **볼트 루트 기준 raw 상대경로**, URL 소스는 **정규화된 URL**. 둘은 같은 맵에 공존하며 키가 `raw/`로 시작하지 않으면 URL 엔트리다 |
| `source_type` | `document` \| `image` \| `url` |
| `content_hash` | raw는 파일 바이트, URL은 **가져온 본문**의 SHA-256. URL도 해시를 두므로 재-ingest 시 변경 감지가 된다. **접근 실패 stub 페이지는 `null`** (본문이 없으므로) |
| `ingested_at` | ISO-8601. **raw 삭제 후보 판정(14일)의 유일한 기준.** 파일 mtime은 git checkout·복사·동기화로 깨지므로 쓰지 않는다 |
| `size_bytes` / `modified_at` | raw 엔트리 전용(파일 속성). URL 엔트리는 생략한다 |
| `pages_created` / `pages_updated` | 항상 배열. 없으면 `[]`. `wiki-lint` 항목 17이 `pages_created`의 실재를 검증한다 |
| `version` | 최상위 예약 키. 값이 객체가 아니므로 엔트리 순회 시 제외된다 |

## 소유·갱신 권한

- **쓰기:** `wiki-ingest`(raw) · `ingest-url`(URL) 둘만.
- **읽기 전용:** `wiki-status` · `wiki-lint`.
- 예외: `wiki-lint --fix`만 항목 15(raw 삭제)·17(엔트리 정리)에서 **개별 확인 후** 수정한다.

## 소비 패턴 — content_hash 기준, mtime 금지

- **미처리** — 키가 manifest에 없음
- **갱신 필요** — 키는 있고 `content_hash`가 현재 소스와 다름
- **스킵** — 키가 있고 `content_hash` 동일 (mtime 무관)
- **소스 변경 미반영(`source_drift`)** — `content_hash`가 다른데 `pages_created`/`pages_updated` 페이지가 그대로
- **삭제 대기** — `content_hash` 있음(ingest 완료) + 대응 `summaries/` 페이지 존재 + `ingested_at` 14일 초과 (3조건 모두)
- **manifest 정합성 위반** — `pages_created` 경로가 디스크에 부재 (사용자가 페이지를 수동 삭제 → 재ingest 시 해시 일치로 스킵되어 영영 미복구되는 silent 손실)
