#!/usr/bin/env bash
# 훅 stdin을 PROBE_OUT_DIR/<label>.captured.json에 저장하고 항상 통과한다.
set -u
LABEL="${1:-probe}"
OUT_DIR="${PROBE_OUT_DIR:-.}"
mkdir -p "$OUT_DIR"
PAYLOAD="$(cat)"
# raw 페이로드를 그대로 저장 (정규화는 사람이 검토 후)
printf '%s' "$PAYLOAD" > "$OUT_DIR/$LABEL.captured.json"
# argv·환경 컨텍스트도 따로 기록
printf 'argv: %s\n' "$*" > "$OUT_DIR/$LABEL.context.txt"
exit 0
