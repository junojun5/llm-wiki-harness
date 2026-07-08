#!/usr/bin/env bash
# probe-hook.sh <label> — 훅 이벤트의 raw stdin 페이로드와 argv를 픽스처로 캡처한다.
# 가드 훅을 작성하기 전(또는 CLI 버전 변경 시) Codex/Cursor의 실제 stdin/stdout 스키마를
# 확보하기 위한 도구다 (배포 설계 §9-6). 차단하지 않고 항상 통과(exit 0)한다.
#
# 사용법: 해당 플랫폼 훅 등록에서 명령을 임시로 이 스크립트로 바꾸고
#   PROBE_OUT_DIR=tests/fixtures/codex-hooks  ~/.../probe-hook.sh pretooluse-write
# 식으로 등록 → 이벤트를 한 번 트리거 → 생성된 *.captured.json을 검토·정규화해 골든 픽스처로 커밋.
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
