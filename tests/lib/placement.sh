#!/usr/bin/env bash
# 배치 확인은 symlink 여부가 아니라 "존재하고 원장에 있다"다. 탭은 printf로만 만든다.
LWH_TAB="$(printf '\t')"

placed() { # placed <home> <dest> — 하네스가 놓았고 쓸 수 있는가
  [ -e "$2" ] || return 1
  grep -qF "$LWH_TAB$2$LWH_TAB" "$1/.llm-wiki/.placements" 2>/dev/null
}

placed_src() { # placed_src <home> <dest> → 원장에 기록된 출처(src)
  grep -F "$LWH_TAB$2$LWH_TAB" "$1/.llm-wiki/.placements" 2>/dev/null | tail -1 | cut -f3
}
