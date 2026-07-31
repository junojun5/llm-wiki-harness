#!/usr/bin/env bash
# 단위 테스트: 배포 매니페스트 버전 일관성.
#
# 왜 필요한가 — `claude plugin update`는 **plugin.json의 version 문자열로만** 갱신 여부를
# 판단한다. 2026-08-01 스모크에서 실측: 마켓플레이스 클론은 머지 커밋까지 갱신됐고
# 설치 기록의 gitCommitSha도 구버전인데, version이 그대로라 update가
# "already at the latest version"으로 캐시를 refresh하지 않았다. 즉 **버전을 올리지 않으면
# 머지한 수정이 설치된 사용자에게 도달하지 않는다.**
#
# 이 테스트는 "언제 올려야 하는가"는 알 수 없다(사람의 판단이다). 대신 **부분 bump**를 막는다 —
# 5곳 중 일부만 올리면 플랫폼마다 다른 버전이 배포되고, 어느 쪽이 진짜인지 알 수 없어진다.
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
  V="$(python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("version", ""))
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
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null; then
    ok "$m 유효한 JSON"
  else
    no "$m JSON 파싱 실패"
  fi
done

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
