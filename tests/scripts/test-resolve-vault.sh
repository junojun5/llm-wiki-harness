#!/usr/bin/env bash
# 단위 테스트: scripts/resolve-vault.sh (하네스 스펙 §3-2)
# 격리: HOME을 임시 디렉토리로 덮어써 실제 ~/.llm-wiki를 건드리지 않는다.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/resolve-vault.sh"

PASS=0
FAIL=0

# --- 테스트 환경 ----------------------------------------------------------
# 매 테스트마다 신선한 샌드박스: SANDBOX/home (가짜 $HOME), SANDBOX/work (CWD)
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
  "vault": { "path": "$vault", "wiki_dir": "wiki", "raw_dir": "raw" },
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

# python3가 없는 머신을 재현해 실행한다 (§3-2 E_NO_RUNTIME).
# PATH를 화이트리스트 디렉토리 **단독**으로 좁힌다 — 뒤에 /usr/bin을 붙이면 거기 있는
# python3가 그대로 보여 은닉이 실패하고, python3 shim 파일을 두는 것도 안 된다
# (파일이 존재하면 `command -v python3`가 성공하므로 부재를 재현하지 못한다).
# 목록에서 빠진 명령이 있으면 테스트가 시끄럽게 실패한다 — 이 방향의 실패는 안전하다.
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
assert_contains "VAULT_PATH 출력" "VAULT_PATH=$SANDBOX/work/myvault" "$OUT"
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
assert_contains "포인터 볼트로 resolve" "VAULT_PATH=$SANDBOX/elsewhere" "$OUT"
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
{ "version": 1, "vault": { "path": "$SANDBOX/work/badvault" } }
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
{ "version": 999, "vault": { "path": "$SANDBOX/work/futurevault", "wiki_dir": "wiki", "raw_dir": "raw" } }
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
{ "version": 1, "vault": { "path": "$SANDBOX/work/notvault", "wiki_dir": "wiki", "raw_dir": "raw" } }
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

# === 테스트 9: E_NO_RUNTIME (exit 7) — 볼트는 있고 python3가 없음 ========
# 오진 방지: 이 상황이 E_INVALID_CONFIG(4)로 나오면 사용자는 듣지 않는 --repair를 반복한다.
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

# === 테스트 10: 게이트가 위치 판정을 앞지르지 않는다 =====================
# 볼트가 없는 머신에서는 python3를 볼 일도 없어야 한다 — E_NO_RUNTIME이
# "볼트 존재"를 함의해야 글로벌 훅이 스팸 없이 분기할 수 있다 (§3-2).
echo "test: 볼트 없음 + python3 없음이면 E_NO_CONFIG exit 2 (E_NO_RUNTIME 아님)"
new_sandbox
run_resolver_nopy "$SANDBOX/work"
assert_eq "exit 2" "2" "$CODE"
assert_contains "stderr E_NO_CONFIG" "E_NO_CONFIG" "$ERR"
cleanup

# --- 결과 -----------------------------------------------------------------
echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
