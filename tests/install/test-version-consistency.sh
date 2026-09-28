#!/usr/bin/env bash
# 배포 매니페스트 버전은 같이 움직인다. 일부만 올리면 플랫폼마다 다른 버전이 나간다.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0

ok() { PASS=$((PASS+1)); echo "  ok: $1"; }
no() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "test: 배포 매니페스트 버전 일관성"

VERSION_FILE="$REPO_ROOT/VERSION"
[ -f "$VERSION_FILE" ] || { no "VERSION 파일 부재"; echo ""; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
BASE="$(head -n1 "$VERSION_FILE" | tr -d '[:space:]')"

# semver 형식 (major.minor.patch)
if printf '%s' "$BASE" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  ok "VERSION이 semver 형식 ($BASE)"
else
  no "VERSION이 semver 형식 아님: '$BASE'"
fi

# 4개 플랫폼 매니페스트가 VERSION과 일치해야 한다
for m in .claude-plugin/plugin.json .codex-plugin/plugin.json \
         .cursor-plugin/plugin.json .antigravity-plugin/plugin.json; do
  f="$REPO_ROOT/$m"
  if [ ! -f "$f" ]; then no "$m 부재"; continue; fi
  V="$(PYTHONUTF8=1 python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1], encoding="utf-8")).get("version", ""))
except Exception as e:
    print("ERR:%s" % e)
' "$f")"
  case "$V" in
    "$BASE")  ok "$m == VERSION ($BASE)" ;;
    ERR:*)    no "$m 파싱 실패 ($V)" ;;
    "")       no "$m 에 version 키 없음" ;;
    *)        no "$m 버전 불일치: '$V' != VERSION '$BASE'" ;;
  esac
done

# 매니페스트 JSON 유효성 (marketplace.json 포함)
for m in .claude-plugin/marketplace.json .cursor-plugin/marketplace.json; do
  f="$REPO_ROOT/$m"
  [ -f "$f" ] || continue
  if PYTHONUTF8=1 python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$f" 2>/dev/null; then
    ok "$m 유효한 JSON"
  else
    no "$m JSON 파싱 실패"
  fi
done

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
