#!/usr/bin/env bash
# resolve-vault. HOME은 임시 디렉터리.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/resolve-vault.sh"
# config에 담기는 경로는 python3가 **값으로** 받으므로 네이티브 형태여야 한다 (MSYS 주의)
. "$REPO_ROOT/tests/lib/paths.sh"

PASS=0
FAIL=0

# 매 테스트마다 새 샌드박스.
new_sandbox() {
  SANDBOX="$(mktemp -d)"
  mkdir -p "$SANDBOX/home" "$SANDBOX/work"
}
cleanup() { [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"; }
trap cleanup EXIT

# 유효한 볼트를 생성한다 (config + wiki 서명 파일)
make_valid_vault() {
  local vault="$1"
  mkdir -p "$vault/wiki" "$vault/raw"
  : > "$vault/wiki/index.md"
  : > "$vault/wiki/log.md"
  cat > "$vault/.wiki-config.json" <<JSON
{
  "version": 1,
  "vault": { "path": "$(native_path "$vault")", "wiki_dir": "wiki", "raw_dir": "raw" },
  "created": "2026-06-25"
}
JSON
}

# resolver를 주어진 CWD·HOME에서 실행, stdout/stderr/exit를 전역에 담는다
run_resolver() {
  local cwd="$1"
  OUT="$(cd "$cwd" && HOME="$SANDBOX/home" bash "$RESOLVER" 2>"$SANDBOX/err")"
  CODE=$?
  ERR="$(cat "$SANDBOX/err")"
}

# MSYS는 PATH를 좁히면 복사된 bash가 죽는다. 그 플랫폼에서는 이 케이스를 건너뛰되 알린다.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) SKIP_NOPY=1 ;;
  *)                    SKIP_NOPY=0 ;;
esac

# python3 부재는 PATH를 화이트리스트만 남겨 만든다. shim을 두면 부재가 아니다.
run_resolver_nopy() {
  local cwd="$1" c
  mkdir -p "$SANDBOX/nopy"
  for c in bash dirname head sed cat env; do
    ln -sf "$(command -v "$c")" "$SANDBOX/nopy/$c"
  done
  OUT="$(cd "$cwd" && HOME="$SANDBOX/home" PATH="$SANDBOX/nopy" "$BASH" "$RESOLVER" 2>"$SANDBOX/err")"
  CODE=$?
  ERR="$(cat "$SANDBOX/err")"
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS+1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL+1)); echo "  FAIL: $desc"; echo "    expected: [$expected]"; echo "    actual:   [$actual]"
  fi
}
assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS+1)); echo "  ok: $desc"
  else
    FAIL=$((FAIL+1)); echo "  FAIL: $desc"; echo "    expected to contain: [$needle]"; echo "    actual: [$haystack]"
  fi
}

# === 테스트 1: 해피 패스 — CWD에서 config 발견 ===========================
echo "test: CWD config 발견 시 KEY=VALUE 출력 + exit 0"
new_sandbox
make_valid_vault "$SANDBOX/work/myvault"
run_resolver "$SANDBOX/work/myvault"
assert_eq "exit 0" "0" "$CODE"
assert_contains "VAULT_PATH 출력" "VAULT_PATH=$(native_path "$SANDBOX/work/myvault")" "$OUT"
assert_contains "WIKI_DIR 출력" "WIKI_DIR=wiki" "$OUT"
assert_contains "RAW_DIR 출력" "RAW_DIR=raw" "$OUT"
cleanup

# === 테스트 2: 전역 포인터 fallback — CWD에 config 없을 때 ================
echo "test: CWD config 없으면 ~/.llm-wiki/default-vault로 resolve"
new_sandbox
make_valid_vault "$SANDBOX/elsewhere"
mkdir -p "$SANDBOX/home/.llm-wiki"
printf '%s\n' "$SANDBOX/elsewhere" > "$SANDBOX/home/.llm-wiki/default-vault"
run_resolver "$SANDBOX/work"          # work엔 config 없음
assert_eq "exit 0" "0" "$CODE"
assert_contains "포인터 볼트로 resolve" "VAULT_PATH=$(native_path "$SANDBOX/elsewhere")" "$OUT"
cleanup

# === 테스트 3: E_NO_CONFIG (exit 2) — config도 포인터도 없음 =============
echo "test: config·포인터 모두 없으면 E_NO_CONFIG exit 2"
new_sandbox
run_resolver "$SANDBOX/work"
assert_eq "exit 2" "2" "$CODE"
assert_contains "stderr E_NO_CONFIG" "E_NO_CONFIG" "$ERR"
cleanup

# === 테스트 4: E_BAD_POINTER (exit 3) — 포인터가 없는 경로 지시 ==========
echo "test: 포인터가 실재하지 않는 경로면 E_BAD_POINTER exit 3"
new_sandbox
mkdir -p "$SANDBOX/home/.llm-wiki"
printf '%s\n' "$SANDBOX/does-not-exist" > "$SANDBOX/home/.llm-wiki/default-vault"
run_resolver "$SANDBOX/work"
assert_eq "exit 3" "3" "$CODE"
assert_contains "stderr E_BAD_POINTER" "E_BAD_POINTER" "$ERR"
cleanup

# === 테스트 5: E_INVALID_CONFIG (exit 4) — 필수 키 누락 ==================
echo "test: 필수 키 누락 config면 E_INVALID_CONFIG exit 4"
new_sandbox
mkdir -p "$SANDBOX/work/badvault/wiki"
: > "$SANDBOX/work/badvault/wiki/index.md"
: > "$SANDBOX/work/badvault/wiki/log.md"
cat > "$SANDBOX/work/badvault/.wiki-config.json" <<JSON
{ "version": 1, "vault": { "path": "$(native_path "$SANDBOX/work/badvault")" } }
JSON
run_resolver "$SANDBOX/work/badvault"
assert_eq "exit 4" "4" "$CODE"
assert_contains "stderr E_INVALID_CONFIG" "E_INVALID_CONFIG" "$ERR"
cleanup

# === 테스트 6: E_VERSION (exit 5) — 스크립트가 아는 버전보다 높음 ========
echo "test: config version이 너무 높으면 E_VERSION exit 5"
new_sandbox
make_valid_vault "$SANDBOX/work/futurevault"
# version을 999로 덮어쓴다
cat > "$SANDBOX/work/futurevault/.wiki-config.json" <<JSON
{ "version": 999, "vault": { "path": "$(native_path "$SANDBOX/work/futurevault")", "wiki_dir": "wiki", "raw_dir": "raw" } }
JSON
run_resolver "$SANDBOX/work/futurevault"
assert_eq "exit 5" "5" "$CODE"
assert_contains "stderr E_VERSION" "E_VERSION" "$ERR"
cleanup

# === 테스트 7: E_NOT_A_VAULT (exit 6) — 서명 파일 없음 ===================
echo "test: index.md/log.md 없으면 E_NOT_A_VAULT exit 6"
new_sandbox
mkdir -p "$SANDBOX/work/notvault/wiki" "$SANDBOX/work/notvault/raw"
cat > "$SANDBOX/work/notvault/.wiki-config.json" <<JSON
{ "version": 1, "vault": { "path": "$(native_path "$SANDBOX/work/notvault")", "wiki_dir": "wiki", "raw_dir": "raw" } }
JSON
run_resolver "$SANDBOX/work/notvault"
assert_eq "exit 6" "6" "$CODE"
assert_contains "stderr E_NOT_A_VAULT" "E_NOT_A_VAULT" "$ERR"
cleanup

# === 테스트 8: stderr 첫 줄은 'E_CODE: 메시지' 형식 =====================
echo "test: 실패 시 stderr 첫 줄이 'E_CODE: ' 형식"
new_sandbox
run_resolver "$SANDBOX/work"
FIRST_LINE="$(printf '%s\n' "$ERR" | head -1)"
assert_contains "첫 줄 E_NO_CONFIG: 접두" "E_NO_CONFIG:" "$FIRST_LINE"
cleanup

if [ "$SKIP_NOPY" = 1 ]; then
  echo "test: (SKIP) python3 은닉 케이스 2건 — MSYS/Windows에서 PATH 단독 좁히기가 성립하지 않는다"
  echo "  SKIP: 은닉 대상 도구가 msys-2.0.dll 의존으로 실행되지 않아 스위트가 매달린다 (2026-08-04 실측)"
else
# 볼트는 있고 python3가 없으면 exit 7. 4로 나오면 수리로 오진된다.
echo "test: 볼트 있음 + python3 없음이면 E_NO_RUNTIME exit 7"
new_sandbox
make_valid_vault "$SANDBOX/work/myvault"
run_resolver_nopy "$SANDBOX/work/myvault"
assert_eq "exit 7" "7" "$CODE"
FIRST_LINE="$(printf '%s\n' "$ERR" | head -1)"
assert_contains "첫 줄 E_NO_RUNTIME: 접두" "E_NO_RUNTIME:" "$FIRST_LINE"
assert_contains "python3 부재를 지목" "python3" "$ERR"
assert_contains "--repair로는 안 된다는 안내" "--repair로는 해결되지 않습니다" "$ERR"
cleanup

# 볼트가 없으면 python3를 보지 않는다. exit 7은 볼트가 있다는 뜻이다.
echo "test: 볼트 없음 + python3 없음이면 E_NO_CONFIG exit 2 (E_NO_RUNTIME 아님)"
new_sandbox
run_resolver_nopy "$SANDBOX/work"
assert_eq "exit 2" "2" "$CODE"
assert_contains "stderr E_NO_CONFIG" "E_NO_CONFIG" "$ERR"
cleanup
fi

# 한글 config는 비UTF-8 locale에서도 읽혀야 한다. 실패하면 파싱 오류로 오진된다.
run_resolver_ascii_locale() {
  local cwd="$1"
  OUT="$(cd "$cwd" && HOME="$SANDBOX/home" \
    LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 bash "$RESOLVER" 2>"$SANDBOX/err")"
  CODE=$?
  ERR="$(cat "$SANDBOX/err")"
}

echo "test: 한글 볼트 경로 + ASCII locale에서도 resolve 성공"
new_sandbox
make_valid_vault "$SANDBOX/work/한글볼트"
run_resolver_ascii_locale "$SANDBOX/work/한글볼트"
assert_eq "exit 0 (오진 없음)" "0" "$CODE"
assert_contains "VAULT_PATH가 한글 경로 그대로" "VAULT_PATH=$(native_path "$SANDBOX/work/한글볼트")" "$OUT"
assert_contains "WIKI_DIR 출력" "WIKI_DIR=wiki" "$OUT"
cleanup

# --- 결과 -----------------------------------------------------------------
echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
