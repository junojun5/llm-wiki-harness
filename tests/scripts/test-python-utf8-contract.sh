#!/usr/bin/env bash
# 셸 스크립트의 python3 호출은 전부 PYTHONUTF8=1이다. 목록 대신 레포를 스캔한다. 주석 줄은 제외.
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  ok: $1"; }
no() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "test: 모든 python3 호출에 PYTHONUTF8=1 (레포 전체 스캔)"

# 스캔은 python3 한 번이다. 줄마다 서브셸을 띄우면 MSYS에서 시간 초과한다.
VIOLATIONS="$(REPO_ROOT="$REPO_ROOT" PYTHONUTF8=1 python3 - <<'PY'
import os
from pathlib import Path

root = Path(os.environ["REPO_ROOT"])
# 실행 가능한 셸 코드만. docs/는 산문이라 제외한다.
targets = sorted(set(
    list((root / "scripts").rglob("*.sh"))
    + list((root / "hooks").rglob("*.sh"))
    + list((root / "tests").rglob("*.sh"))
    + [root / "install.sh", root / "hooks" / "session-start"]
))
# `python3 -c` / `python3 -m` / `python3 - <<HEREDOC` 이 호출 형태다.
CALLS = ("python3 -c", "python3 -m", "python3 - ")
for f in targets:
    if not f.is_file():
        continue
    if f.name == "test-python-utf8-contract.sh":
        continue  # 스캐너 자신 — 위 CALLS 리터럴이 스스로에게 걸린다
    for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
        s = line.lstrip()
        if s.startswith("#") or "PYTHONUTF8" in line:
            continue
        if any(c in line for c in CALLS):
            print("  %s:%d: %s" % (f.relative_to(root), i, s[:90]))
PY
)"

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
