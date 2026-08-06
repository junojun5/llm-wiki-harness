#!/usr/bin/env bash
# tests/lib/placement.sh — 배치 결과를 **메커니즘과 무관하게** 확인한다.
# `. "$REPO_ROOT/tests/lib/placement.sh"` 로 로드한다.
#
# ── 왜 있는가 (2026-08-07) ─────────────────────────────────────────────────────
# 종전 단언은 `[ -L "$dest" ]` — "symlink인가"였다. 이건 **구현 메커니즘에 대한 단언**이고
# 계약이 아니다. MSYS(Git Bash)의 `ln -s`는 복사본을 만들므로 Windows에서는 배치가 정상이어도
# 이 단언이 전부 실패했다(smoke 5건 · session-start 2건). 그 실패들은 프로덕션 결함이 아니라
# **테스트가 잘못된 것을 물어본 결과**였고, 진짜 결함(소유권 오판)은 그 소음에 섞여 있었다.
#
# 계약은 "symlink다"가 아니라 **"하네스가 놓았고 쓸 수 있다"**다:
#   ① dest가 존재하고 따라갈 수 있다 (`-e`는 symlink를 따라가므로 깨진 링크는 걸러진다)
#   ② 배치 원장(`~/.llm-wiki/.placements`)에 기록돼 있다 — install.sh가 소유권 판정에 쓰는 것과
#      같은 출처이므로, 원장이 비면 재실행이 자기 산물에 사이드카를 만드는 결함이 여기서 잡힌다.
# symlink든 복사든 둘 다 통과하고, 플랫폼 분기가 필요 없다.

# 원장 구분자는 **실제 탭**이다. bash 이중인용의 `"\t"`는 리터럴 백슬래시-t이므로 조용히
# 어긋난다(작성 중 실제로 걸렸다) — 탭을 다루는 곳을 이 파일 하나로 모은다.
LWH_TAB="$(printf '\t')"

placed() { # placed <home> <dest> — 하네스가 놓았고 쓸 수 있는가
  [ -e "$2" ] || return 1
  grep -qF "$LWH_TAB$2$LWH_TAB" "$1/.llm-wiki/.placements" 2>/dev/null
}

placed_src() { # placed_src <home> <dest> → 원장에 기록된 출처(src)
  grep -F "$LWH_TAB$2$LWH_TAB" "$1/.llm-wiki/.placements" 2>/dev/null | tail -1 | cut -f3
}
