#!/usr/bin/env bash
# python3에 값으로 넘기는 경로는 native_path를 거친다. MSYS는 argv만 변환하고 파일 내용·stdin은 그대로다.

native_path() { # native_path <posix-path> → 플랫폼 네이티브 경로
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    printf '%s\n' "$1"
  fi
}
