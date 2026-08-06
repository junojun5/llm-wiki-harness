#!/usr/bin/env bash
# 전체 테스트 러너. 각 test-*.sh를 실행하고 요약한다.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
for t in "$HERE"/scripts/test-*.sh "$HERE"/hooks/test-*.sh "$HERE"/skills/test-*.sh "$HERE"/install/test-*.sh "$HERE"/install/smoke.sh; do
  name="$(basename "$t")"
  if bash "$t" >/tmp/lwh-test.$$ 2>&1; then
    echo "PASS  $name  ($(grep -o 'PASS=[0-9]*' /tmp/lwh-test.$$ | tail -1))"
  else
    echo "FAIL  $name"; cat /tmp/lwh-test.$$; fail=1
  fi
done
rm -f /tmp/lwh-test.$$
[ "$fail" -eq 0 ] && echo "── 전체 통과 ──" || echo "── 실패 있음 ──"
exit "$fail"
