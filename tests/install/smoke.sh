#!/usr/bin/env bash
# smoke.sh — 하네스의 결정론적 조각들이 함께 동작하는지 end-to-end로 확인한다 (배포 설계 §9-11).
# 실제 4개 플랫폼 CLI(Claude/Codex/Cursor/Antigravity)가 필요한 부분은 별도 in-app 검증 대상이며,
# 여기서는 install → resolve → validate → protect → link-graph → bootstrap 합성 흐름을 격리 HOME에서 검증한다.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ✓ $1"; }
no(){ FAIL=$((FAIL+1)); echo "  ✗ $1"; }

SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
HOME_DIR="$SB/home"; VAULT="$SB/vault"
mkdir -p "$HOME_DIR/.claude" "$HOME_DIR/.cursor" "$HOME_DIR/.gemini" "$VAULT"

echo "[1] install.sh --fallback --vault → ~/.llm-wiki 부트스트랩 + Antigravity + 홈 전역(fallback) + 볼트 로컬"
HOME="$HOME_DIR" bash "$REPO/install.sh" --fallback --vault "$VAULT" >/dev/null 2>&1
[ -L "$HOME_DIR/.llm-wiki/scripts/resolve-vault.sh" ] && ok "런타임 스크립트 설치" || no "런타임 스크립트 설치"
[ -L "$VAULT/AGENTS.md" ] && ok "AGENTS.md 배치" || no "AGENTS.md 배치"
# Cursor 전역(User): skills + hooks.json(절대경로)
[ -L "$HOME_DIR/.cursor/skills/using-llm-wiki" ] && ok "Cursor 전역 skills" || no "Cursor 전역 skills"
[ -f "$HOME_DIR/.cursor/hooks.json" ] && grep -q "$HOME_DIR/.cursor/hooks/" "$HOME_DIR/.cursor/hooks.json" && ok "Cursor ~/.cursor/hooks.json (절대경로)" || no "Cursor hooks.json"
# Antigravity 전역 플러그인: plugin.json + skills, hooks.json 없음(스키마 미검증)
[ -f "$HOME_DIR/.gemini/config/plugins/llm-wiki-harness/plugin.json" ] && ok "Antigravity plugin.json" || no "Antigravity plugin.json"
[ -L "$HOME_DIR/.gemini/config/plugins/llm-wiki-harness/skills/wiki-setup" ] && ok "Antigravity plugin skills" || no "Antigravity plugin skills"
[ ! -e "$HOME_DIR/.gemini/config/plugins/llm-wiki-harness/hooks.json" ] && ok "Antigravity hooks.json 미포함(의도)" || no "Antigravity hooks.json이 있으면 안 됨(스키마 미검증)"

echo "[2] wiki-setup 시뮬레이션 (config + pointer + 서명)"
mkdir -p "$VAULT/wiki/knowledge" "$VAULT/raw/articles"
: > "$VAULT/wiki/index.md"; : > "$VAULT/wiki/log.md"
cat > "$VAULT/.wiki-config.json" <<JSON
{ "version": 1, "vault": { "path": "$VAULT", "wiki_dir": "wiki", "raw_dir": "raw" }, "created": "2026-06-25" }
JSON
printf '%s\n' "$VAULT" > "$HOME_DIR/.llm-wiki/default-vault"

echo "[3] resolve-vault — CWD 내부 & 외부 포인터"
R_IN="$(cd "$VAULT/wiki" && HOME="$HOME_DIR" bash "$HOME_DIR/.llm-wiki/scripts/resolve-vault.sh")"
printf '%s' "$R_IN" | grep -q "VAULT_PATH=$VAULT" && ok "CWD 내부 resolve" || no "CWD 내부 resolve"
R_OUT="$(cd "$SB" && HOME="$HOME_DIR" bash "$HOME_DIR/.llm-wiki/scripts/resolve-vault.sh")"
printf '%s' "$R_OUT" | grep -q "VAULT_PATH=$VAULT" && ok "외부→포인터 resolve" || no "외부→포인터 resolve"

echo "[4] 유효 페이지 작성 + frontmatter 검증 통과 (PostToolUse 훅 경로)"
cat > "$VAULT/wiki/knowledge/ml.md" <<'MD'
---
title: "머신러닝"
category: knowledge
tags: [ml]
sources: ["raw/articles/x.md"]
created: 2026-06-25
updated: 2026-06-25
summary: "요약"
status: verified
base_confidence: 0.8
---
[[deep-learning]] 참조.
MD
printf '{"tool_input":{"file_path":"%s"}}' "$VAULT/wiki/knowledge/ml.md" \
  | (cd "$VAULT" && HOME="$HOME_DIR" bash "$REPO/hooks/wiki-validate-frontmatter.sh") && ok "유효 페이지 통과" || no "유효 페이지 통과"

echo "[5] protect-raw — raw/ 쓰기 차단, rm 허용"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/raw/articles/y.md"}}' "$VAULT" \
  | (cd "$VAULT" && HOME="$HOME_DIR" bash "$REPO/hooks/wiki-protect-raw.sh" claude) 2>/dev/null
[ $? -eq 2 ] && ok "raw/ 쓰기 차단(exit 2)" || no "raw/ 쓰기 차단"
printf '{"tool_name":"Bash","tool_input":{"command":"rm %s/raw/articles/y.md"}}' "$VAULT" \
  | (cd "$VAULT" && HOME="$HOME_DIR" bash "$REPO/hooks/wiki-protect-raw.sh" claude) 2>/dev/null
[ $? -eq 0 ] && ok "raw/ rm 허용(exit 0)" || no "raw/ rm 허용"

echo "[6] build-link-graph — 깨진 링크 감지"
G="$(HOME="$HOME_DIR" bash "$HOME_DIR/.llm-wiki/scripts/build-link-graph.sh" "$VAULT/wiki")"
printf '%s' "$G" | grep -q "BROKEN	knowledge/ml.md	deep-learning" && ok "깨진 링크 감지" || no "깨진 링크 감지"

echo "[7] session-start — 볼트 CWD에서만 주입(자가-게이팅)"
(cd "$VAULT" && HOME="$HOME_DIR" bash "$REPO/hooks/session-start" claude) \
  | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'Config Gate' in d['hookSpecificOutput']['additionalContext'] else 1)" \
  && ok "볼트 CWD → 주입" || no "볼트 CWD → 주입"
OUT_OUTSIDE="$(cd "$SB" && HOME="$HOME_DIR" bash "$REPO/hooks/session-start" claude)"
[ -z "$OUT_OUTSIDE" ] && ok "볼트 밖 CWD → 주입 없음(스팸 방지)" || no "볼트 밖인데 주입됨"

echo ""
echo "SMOKE PASS=$PASS FAIL=$FAIL"
echo "ⓘ 실제 Claude/Codex/Cursor/Antigravity CLI end-to-end는 in-app 검증 필요 (tests/fixtures/README.md, 배포 설계 §10)."
[ "$FAIL" -eq 0 ]
