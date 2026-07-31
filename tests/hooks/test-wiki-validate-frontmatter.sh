#!/usr/bin/env bash
# 단위 테스트: hooks/wiki-validate-frontmatter.sh (하네스 스펙 §5-3)
# wiki/ 하위 .md 쓰기마다 validate-frontmatter.sh를 wrapper로 호출. 위반 시 exit 2 + stderr.
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/wiki-validate-frontmatter.sh"
PASS=0; FAIL=0

new_sandbox() {
  SANDBOX="$(mktemp -d)"
  mkdir -p "$SANDBOX/home/.llm-wiki/scripts"
  ln -sf "$REPO_ROOT/scripts/resolve-vault.sh"      "$SANDBOX/home/.llm-wiki/scripts/resolve-vault.sh"
  ln -sf "$REPO_ROOT/scripts/validate-frontmatter.sh" "$SANDBOX/home/.llm-wiki/scripts/validate-frontmatter.sh"
  VAULT="$SANDBOX/vault"; mkdir -p "$VAULT/wiki/knowledge" "$VAULT/raw"
  : > "$VAULT/wiki/index.md"; : > "$VAULT/wiki/log.md"
  cat > "$VAULT/.wiki-config.json" <<JSON
{ "version": 1, "vault": { "path": "$VAULT", "wiki_dir": "wiki", "raw_dir": "raw" }, "created": "2026-06-25" }
JSON
  printf '%s\n' "$VAULT" > "$SANDBOX/home/.llm-wiki/default-vault"
}
cleanup() { [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"; }
trap cleanup EXIT
run_hook() {
  OUT="$(cd "$VAULT" && printf '%s' "$1" | HOME="$SANDBOX/home" bash "$HOOK" 2>"$SANDBOX/err")"
  CODE=$?; ERR="$(cat "$SANDBOX/err")"
}
ok(){ PASS=$((PASS+1)); echo "  ok: $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
eq(){ [ "$2" = "$3" ] && ok "$1" || no "$1 (exp [$2] got [$3])"; }

VALID='---
title: "유효"
category: knowledge
tags: [a]
sources: ["raw/x.md"]
created: 2026-06-25
updated: 2026-06-25
summary: "요약"
status: verified
base_confidence: 0.8
---
본문.'

echo "test: 유효 wiki/.md 쓰기 → exit 0"
new_sandbox
printf '%s' "$VALID" > "$VAULT/wiki/knowledge/good.md"
run_hook "{\"tool_input\":{\"file_path\":\"$VAULT/wiki/knowledge/good.md\"}}"
eq "exit 0" "0" "$CODE"; cleanup

echo "test: 필수키 누락 wiki/.md → exit 2 + stderr"
new_sandbox
printf '%s' "${VALID/summary: \"요약\"$'\n'/}" > "$VAULT/wiki/knowledge/bad.md"
run_hook "{\"tool_input\":{\"file_path\":\"$VAULT/wiki/knowledge/bad.md\"}}"
eq "exit 2" "2" "$CODE"
[ -n "$ERR" ] && ok "stderr 출력" || no "stderr 출력"; cleanup

echo "test: 클래스③ 원장(index.md) → exit 0 (validator 면제)"
new_sandbox
run_hook "{\"tool_input\":{\"file_path\":\"$VAULT/wiki/index.md\"}}"
eq "exit 0" "0" "$CODE"; cleanup

echo "test: wiki/ 밖 경로 → 통과 (exit 0)"
new_sandbox
run_hook "{\"tool_input\":{\"file_path\":\"$VAULT/raw/x.md\"}}"
eq "exit 0" "0" "$CODE"; cleanup

echo "test: 비볼트 → 통과 (exit 0)"
new_sandbox; rm -f "$SANDBOX/home/.llm-wiki/default-vault"
OUT="$(cd "$SANDBOX" && printf '%s' "{\"tool_input\":{\"file_path\":\"$SANDBOX/x.md\"}}" | HOME="$SANDBOX/home" bash "$HOOK" 2>/dev/null)"; CODE=$?
eq "exit 0" "0" "$CODE"; cleanup

# ── 상대경로·apply_patch 추출 (§5-3 — §5-2와 동일 규칙이어야 한다) ──────────────
# 절대경로 + file_path 전제였던 구현은 아래 케이스에서 검증이 조용히 죽었다.

echo "test: Write 상대경로(cwd 기준) — 위반 페이지에서 검증 발화 (exit 2)"
new_sandbox
printf 'title: frontmatter 블록 없음\n' > "$VAULT/wiki/knowledge/notes.md"
run_hook "{\"tool_name\":\"Write\",\"cwd\":\"$VAULT\",\"tool_input\":{\"file_path\":\"wiki/knowledge/notes.md\"}}"
eq "exit 2" "2" "$CODE"
[ -n "$ERR" ] && ok "stderr 출력" || no "stderr 출력"; cleanup

echo "test: apply_patch 상대경로 — 위반 페이지에서 검증 발화 (exit 2)"
new_sandbox
printf 'title: frontmatter 블록 없음\n' > "$VAULT/wiki/knowledge/notes.md"
run_hook "{\"tool_name\":\"apply_patch\",\"cwd\":\"$VAULT\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: wiki/knowledge/notes.md\n+title: frontmatter 블록 없음\n*** End Patch\n\"}}"
eq "exit 2" "2" "$CODE"
[ -n "$ERR" ] && ok "stderr 출력" || no "stderr 출력"; cleanup

echo "test: apply_patch 상대경로 — 유효 페이지는 통과 (exit 0)"
new_sandbox
printf '%s' "$VALID" > "$VAULT/wiki/knowledge/notes.md"
run_hook "{\"tool_name\":\"apply_patch\",\"cwd\":\"$VAULT\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Update File: wiki/knowledge/notes.md\n+본문 추가\n*** End Patch\n\"}}"
eq "exit 0" "0" "$CODE"; cleanup

# 골든 픽스처(실측 페이로드)로 검증. tool_input은 실측 바이트 그대로 두고
# 환경 의존값인 cwd만 샌드박스 볼트로 바꿔 넣는다 — 픽스처의 `*** Add File: notes.md`가
# wiki/knowledge/notes.md 로 해석되게 한다.
echo "test: 골든 픽스처 posttooluse-apply-patch.json — 위반 페이지에서 검증 발화 (exit 2)"
new_sandbox
printf 'title: frontmatter 블록 없음\n' > "$VAULT/wiki/knowledge/notes.md"
PAYLOAD="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
d["cwd"] = sys.argv[2]
print(json.dumps(d))
' "$REPO_ROOT/tests/fixtures/codex-hooks/posttooluse-apply-patch.json" "$VAULT/wiki/knowledge")"
run_hook "$PAYLOAD"
eq "exit 2 (실측 페이로드로 발화)" "2" "$CODE"
[ -n "$ERR" ] && ok "stderr 출력" || no "stderr 출력"; cleanup

echo "test: apply_patch Delete File은 추출하지 않는다 (삭제된 파일 오보고 방지)"
new_sandbox
run_hook "{\"tool_name\":\"apply_patch\",\"cwd\":\"$VAULT\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Delete File: wiki/knowledge/gone.md\n*** End Patch\n\"}}"
eq "exit 0" "0" "$CODE"; cleanup

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
