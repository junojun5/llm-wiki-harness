#!/usr/bin/env bash
# wiki/ .md 쓰기의 frontmatter 위반은 exit 2.
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/wiki-validate-frontmatter.sh"
# 페이로드·config의 경로는 python3가 **값으로** 받는다 — 네이티브 형태여야 한다 (MSYS 주의)
. "$REPO_ROOT/tests/lib/paths.sh"
PASS=0; FAIL=0

new_sandbox() {
  SANDBOX="$(mktemp -d)"
  mkdir -p "$SANDBOX/home/.llm-wiki/scripts"
  ln -sf "$REPO_ROOT/scripts/resolve-vault.sh"      "$SANDBOX/home/.llm-wiki/scripts/resolve-vault.sh"
  ln -sf "$REPO_ROOT/scripts/validate-frontmatter.sh" "$SANDBOX/home/.llm-wiki/scripts/validate-frontmatter.sh"
  VAULT="$SANDBOX/vault"; mkdir -p "$VAULT/wiki/knowledge" "$VAULT/raw"
  VAULT_N="$(native_path "$VAULT")"
  : > "$VAULT/wiki/index.md"; : > "$VAULT/wiki/log.md"
  cat > "$VAULT/.wiki-config.json" <<JSON
{ "version": 1, "vault": { "path": "$VAULT_N", "wiki_dir": "wiki", "raw_dir": "raw" }, "created": "2026-06-25" }
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
run_hook "{\"tool_input\":{\"file_path\":\"$VAULT_N/wiki/knowledge/good.md\"}}"
eq "exit 0" "0" "$CODE"; cleanup

echo "test: 필수키 누락 wiki/.md → exit 2 + stderr"
new_sandbox
printf '%s' "${VALID/summary: \"요약\"$'\n'/}" > "$VAULT/wiki/knowledge/bad.md"
run_hook "{\"tool_input\":{\"file_path\":\"$VAULT_N/wiki/knowledge/bad.md\"}}"
eq "exit 2" "2" "$CODE"
[ -n "$ERR" ] && ok "stderr 출력" || no "stderr 출력"; cleanup

echo "test: config 경로가 비정규 표기여도 검증이 발화한다 (Windows 구분자 차이 회귀)"
# protect-raw와 같은 부류 — 정규화 없이 비교하면 wiki/ 판정이 어긋나 **검증이 조용히 통과**한다.
new_sandbox
cat > "$VAULT/.wiki-config.json" <<JSON
{ "version": 1, "vault": { "path": "$VAULT_N/./", "wiki_dir": "wiki", "raw_dir": "raw" }, "created": "2026-06-25" }
JSON
printf '%s' "${VALID/summary: \"요약\"$'\n'/}" > "$VAULT/wiki/knowledge/bad.md"
run_hook "{\"tool_input\":{\"file_path\":\"$VAULT_N/wiki/knowledge/bad.md\"}}"
eq "비정규 config에서도 발화" "2" "$CODE"
cleanup

echo "test: 클래스③ 원장(index.md) → exit 0 (validator 면제)"
new_sandbox
run_hook "{\"tool_input\":{\"file_path\":\"$VAULT_N/wiki/index.md\"}}"
eq "exit 0" "0" "$CODE"; cleanup

echo "test: wiki/ 밖 경로 → 통과 (exit 0)"
new_sandbox
run_hook "{\"tool_input\":{\"file_path\":\"$VAULT_N/raw/x.md\"}}"
eq "exit 0" "0" "$CODE"; cleanup

echo "test: 비볼트 → 통과 (exit 0)"
new_sandbox; rm -f "$SANDBOX/home/.llm-wiki/default-vault"
OUT="$(cd "$SANDBOX" && printf '%s' "{\"tool_input\":{\"file_path\":\"$SANDBOX/x.md\"}}" | HOME="$SANDBOX/home" bash "$HOOK" 2>/dev/null)"; CODE=$?
eq "exit 0" "0" "$CODE"; cleanup

# 상대경로와 apply_patch 본문에서도 대상을 뽑는다. file_path만 보면 검증이 죽는다.

echo "test: Write 상대경로(cwd 기준) — 위반 페이지에서 검증 발화 (exit 2)"
new_sandbox
printf 'title: frontmatter 블록 없음\n' > "$VAULT/wiki/knowledge/notes.md"
run_hook "{\"tool_name\":\"Write\",\"cwd\":\"$VAULT_N\",\"tool_input\":{\"file_path\":\"wiki/knowledge/notes.md\"}}"
eq "exit 2" "2" "$CODE"
[ -n "$ERR" ] && ok "stderr 출력" || no "stderr 출력"; cleanup

echo "test: apply_patch 상대경로 — 위반 페이지에서 검증 발화 (exit 2)"
new_sandbox
printf 'title: frontmatter 블록 없음\n' > "$VAULT/wiki/knowledge/notes.md"
run_hook "{\"tool_name\":\"apply_patch\",\"cwd\":\"$VAULT_N\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: wiki/knowledge/notes.md\n+title: frontmatter 블록 없음\n*** End Patch\n\"}}"
eq "exit 2" "2" "$CODE"
[ -n "$ERR" ] && ok "stderr 출력" || no "stderr 출력"; cleanup

echo "test: apply_patch 상대경로 — 유효 페이지는 통과 (exit 0)"
new_sandbox
printf '%s' "$VALID" > "$VAULT/wiki/knowledge/notes.md"
run_hook "{\"tool_name\":\"apply_patch\",\"cwd\":\"$VAULT_N\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Update File: wiki/knowledge/notes.md\n+본문 추가\n*** End Patch\n\"}}"
eq "exit 0" "0" "$CODE"; cleanup

# 픽스처 바이트는 두고 cwd만 샌드박스 볼트로 바꾼다.
echo "test: 골든 픽스처 posttooluse-apply-patch.json — 위반 페이지에서 검증 발화 (exit 2)"
new_sandbox
printf 'title: frontmatter 블록 없음\n' > "$VAULT/wiki/knowledge/notes.md"
PAYLOAD="$(PYTHONUTF8=1 python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["cwd"] = sys.argv[2]
print(json.dumps(d))
' "$REPO_ROOT/tests/fixtures/codex-hooks/posttooluse-apply-patch.json" "$VAULT_N/wiki/knowledge")"
run_hook "$PAYLOAD"
eq "exit 2 (실측 페이로드로 발화)" "2" "$CODE"
[ -n "$ERR" ] && ok "stderr 출력" || no "stderr 출력"; cleanup

echo "test: apply_patch Delete File은 추출하지 않는다 (삭제된 파일 오보고 방지)"
new_sandbox
run_hook "{\"tool_name\":\"apply_patch\",\"cwd\":\"$VAULT_N\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Delete File: wiki/knowledge/gone.md\n*** End Patch\n\"}}"
eq "exit 0" "0" "$CODE"; cleanup

# MSYS는 PATH를 좁히면 복사된 bash가 죽는다. 그 플랫폼에서는 이 케이스를 건너뛰되 알린다.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) SKIP_NOPY=1 ;;
  *)                    SKIP_NOPY=0 ;;
esac

if [ "$SKIP_NOPY" = 1 ]; then
  echo "test: (SKIP) python3 fail-open 케이스 — MSYS/Windows에서 PATH 단독 좁히기가 성립하지 않는다"
  echo "  SKIP: 은닉 대상 도구가 msys-2.0.dll 의존으로 실행되지 않아 스위트가 매달린다 (2026-08-04 실측)"
else
# python3가 없으면 검증 없이 통과한다. 판정 자체가 python3다.
echo "test: [의도된 fail-open] python3 없음 → 위반 페이로드도 통과 (exit 0)"
new_sandbox
NOPY="$SANDBOX/nopy"; mkdir -p "$NOPY"
for c in bash dirname head sed cat env; do ln -sf "$(command -v "$c")" "$NOPY/$c"; done
printf 'title 없음\n' > "$VAULT/wiki/knowledge/broken.md"
OUT="$(cd "$VAULT" && printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$VAULT_N/wiki/knowledge/broken.md\"}}" \
  | HOME="$SANDBOX/home" PATH="$NOPY" "$BASH" "$HOOK" 2>"$SANDBOX/err")"; CODE=$?
eq "exit 0 (fail-open)" "0" "$CODE"
(cd "$VAULT" && HOME="$SANDBOX/home" PATH="$NOPY" "$BASH" "$SANDBOX/home/.llm-wiki/scripts/resolve-vault.sh" >/dev/null 2>&1)
eq "resolver는 exit 7(E_NO_RUNTIME)" "7" "$?"
cleanup

fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
