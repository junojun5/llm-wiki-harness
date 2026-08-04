#!/usr/bin/env bash
# 계약 테스트: §3-9 — 레포의 **모든** python3 호출은 PYTHONUTF8=1로 실행한다.
#
# 왜 이게 필요한가 (2026-08-04) — §3-9는 0.3.1에서 신설되며 "python3를 호출하는 모든 지점"이라고
# 적었지만, 실제로는 `scripts/`·`hooks/`만 훑어 `install.sh`의 `render()` 하나가 빠졌다. 그 누락은
# **Windows CI가 우연히 smoke.sh까지 도달한 뒤에야** 드러났고, 증상은 예외 하나가 아니라
# **훅 등록 파일이 0바이트로 남아 가드가 조용히 죽는 것**이었다.
#
# 사람이 목록을 관리하면 또 빠진다. 그래서 목록 대신 **레포를 스캔**한다.
# 이 테스트는 새 python3 호출 지점이 추가되는 순간 실패하므로, §3-9가 문서가 아니라 계약이 된다.
#
# 범위: 추적 대상 셸 스크립트 전부(scripts/·hooks/·tests/·install.sh). 주석 줄은 제외한다.
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  ok: $1"; }
no() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "test: [§3-9 계약] 모든 python3 호출에 PYTHONUTF8=1 (레포 전체 스캔)"

# 스캔 대상 — 실행 가능한 셸 코드만. docs/는 산문이라 제외한다.
TARGETS="$(find "$REPO_ROOT/scripts" "$REPO_ROOT/hooks" "$REPO_ROOT/tests" -name '*.sh' -type f 2>/dev/null; \
           printf '%s\n' "$REPO_ROOT/install.sh" "$REPO_ROOT/hooks/session-start")"

VIOLATIONS=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # 스캐너 자신은 제외한다 — 아래 case 패턴 문자열이 스스로에게 걸린다
  case "$f" in */test-python-utf8-contract.sh) continue ;; esac
  # `python3 -c` / `python3 -m` / `python3 - <<` 가 호출 형태다.
  # 주석 줄과 이미 PYTHONUTF8이 붙은 줄은 건너뛴다.
  while IFS= read -r line; do
    case "$(printf '%s' "$line" | sed 's/^[[:space:]]*//')" in \#*) continue ;; esac
    case "$line" in *PYTHONUTF8*) continue ;; esac
    case "$line" in
      *"python3 -c"*|*"python3 -m"*|*"python3 - "*)
        VIOLATIONS="$VIOLATIONS
  ${f#$REPO_ROOT/}: $(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-90)" ;;
    esac
  done < "$f"
done <<EOF
$TARGETS
EOF

if [ -z "$VIOLATIONS" ]; then
  ok "PYTHONUTF8=1 없는 python3 호출 0건"
else
  no "PYTHONUTF8=1 누락 — 비UTF-8 locale(Windows cp1252)에서 조용히 깨진다:$VIOLATIONS"
fi

echo "test: 계약이 실제로 지켜지는지 — ASCII locale에서 한국어 JSON 왕복"
# 계약이 문자열로만 지켜지고 실효가 없으면 의미가 없다. 대표 경로 하나를 실제로 돌린다.
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
OUT="$(LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 \
       PYTHONUTF8=1 python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["hooks"] and "read-ok")' \
       "$REPO_ROOT/hooks/hooks.json" 2>&1)"
[ "$OUT" = "read-ok" ] && ok "ASCII locale에서도 한국어 등록 JSON 파싱" || no "ASCII locale 파싱 실패: $OUT"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
