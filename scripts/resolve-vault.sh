#!/usr/bin/env bash
# resolve-vault.sh — 모든 스킬·훅의 공통 Step 0 (Config Gate). 하네스 스펙 §3-2.
# 상태를 남기지 않는다: 매 호출마다 fresh resolve. 성공 출력은 stdout의 KEY=VALUE.
# 실패는 exit code + stderr 첫 줄 "E_CODE: 메시지".
set -u

# 이 스크립트가 아는 config 스키마 최신 버전 (§3-1)
KNOWN_VERSION=1

# 표준 실패: stderr 첫 줄 고정 포맷 후 종료
fail() { # fail <exit> <CODE> <message>
  printf '%s: %s\n' "$2" "$3" >&2
  exit "$1"
}

# CWD에서 루트 방향으로 .wiki-config.json 탐색
find_config_upward() {
  local dir="$PWD"
  while :; do
    if [ -f "$dir/.wiki-config.json" ]; then printf '%s\n' "$dir/.wiki-config.json"; return 0; fi
    [ "$dir" = "/" ] && return 1
    dir="$(dirname "$dir")"
  done
}

# --- 1) config 위치 결정: CWD 우선, 없으면 전역 포인터 ----------------------
CONFIG="$(find_config_upward || true)"

if [ -z "$CONFIG" ]; then
  POINTER="$HOME/.llm-wiki/default-vault"
  [ -f "$POINTER" ] || fail 2 E_NO_CONFIG "볼트 설정을 찾을 수 없습니다. /wiki-setup을 먼저 실행하세요"
  TARGET="$(head -n1 "$POINTER" 2>/dev/null || true)"
  [ -n "$TARGET" ] && [ -d "$TARGET" ] || fail 3 E_BAD_POINTER "전역 포인터가 가리키는 볼트 경로가 없습니다. /wiki-setup --update-path로 볼트 위치를 재지정하세요"
  CONFIG="$TARGET/.wiki-config.json"
  [ -f "$CONFIG" ] || fail 3 E_BAD_POINTER "전역 포인터 경로에 .wiki-config.json이 없습니다. /wiki-setup --update-path로 볼트 위치를 재지정하세요"
fi

# --- 2) config 파싱 + 필수 키/형식 검증 (python3) --------------------------
# python3은 구조화된 결과를 라인으로 내보낸다: 첫 토큰이 분기 키.
PARSED="$(python3 - "$CONFIG" <<'PY' 2>/dev/null
import json, os, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("ERR PARSE"); sys.exit(0)
v = d.get("vault")
if not isinstance(v, dict):
    print("ERR MISSING vault"); sys.exit(0)
for k in ("path", "wiki_dir", "raw_dir"):
    if k not in v or v[k] in (None, ""):
        print("ERR MISSING vault.%s" % k); sys.exit(0)
path = v["path"]
if not os.path.isabs(path) or not os.path.isdir(path):
    print("ERR PATH"); sys.exit(0)
ver = d.get("version", 1)
try:
    ver = int(ver)
except Exception:
    print("ERR VERSION"); sys.exit(0)
print("OK")
print("VERSION=%d" % ver)
print("PATH=%s" % path)
print("WIKI=%s" % v["wiki_dir"])
print("RAW=%s" % v["raw_dir"])
PY
)"

[ -z "$PARSED" ] && fail 4 E_INVALID_CONFIG "config 파싱에 실패했습니다. /wiki-setup --repair를 실행하세요"

STATUS="$(printf '%s\n' "$PARSED" | head -n1)"
case "$STATUS" in
  "ERR PARSE")        fail 4 E_INVALID_CONFIG "config JSON 파싱 실패. /wiki-setup --repair를 실행하세요" ;;
  "ERR MISSING"*)     fail 4 E_INVALID_CONFIG "필수 키 누락(${STATUS#ERR MISSING }). /wiki-setup --repair를 실행하세요" ;;
  "ERR PATH")         fail 4 E_INVALID_CONFIG "vault.path가 절대경로가 아니거나 존재하지 않습니다. /wiki-setup --repair를 실행하세요" ;;
  "ERR VERSION")      fail 4 E_INVALID_CONFIG "version 값이 정수가 아닙니다. /wiki-setup --repair를 실행하세요" ;;
  OK) : ;;
  *)                  fail 4 E_INVALID_CONFIG "알 수 없는 config 오류. /wiki-setup --repair를 실행하세요" ;;
esac

# 파싱 결과 추출
VERSION="$(printf '%s\n' "$PARSED" | sed -n 's/^VERSION=//p')"
VAULT_PATH="$(printf '%s\n' "$PARSED" | sed -n 's/^PATH=//p')"
WIKI_DIR="$(printf '%s\n' "$PARSED" | sed -n 's/^WIKI=//p')"
RAW_DIR="$(printf '%s\n' "$PARSED" | sed -n 's/^RAW=//p')"

# --- 3) version 게이트 ----------------------------------------------------
if [ "$VERSION" -gt "$KNOWN_VERSION" ]; then
  fail 5 E_VERSION "config version($VERSION)이 스킬이 아는 버전($KNOWN_VERSION)보다 높습니다. harness repo를 업데이트하세요 (git pull)"
elif [ "$VERSION" -lt "$KNOWN_VERSION" ]; then
  printf 'E_WARN: config version(%s)이 구버전입니다. 진행은 하지만 /wiki-setup --repair 권장\n' "$VERSION" >&2
fi

# --- 4) vault 서명 검증 ---------------------------------------------------
if [ ! -f "$VAULT_PATH/$WIKI_DIR/index.md" ] || [ ! -f "$VAULT_PATH/$WIKI_DIR/log.md" ]; then
  fail 6 E_NOT_A_VAULT "wiki 서명($WIKI_DIR/index.md, log.md)이 없습니다. /wiki-setup --repair를 실행하세요"
fi

# --- 5) 성공 -------------------------------------------------------------
printf 'VAULT_PATH=%s\n' "$VAULT_PATH"
printf 'WIKI_DIR=%s\n' "$WIKI_DIR"
printf 'RAW_DIR=%s\n' "$RAW_DIR"
exit 0
