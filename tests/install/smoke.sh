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
# 매니페스트는 레포 소스(.antigravity-plugin/plugin.json)가 단일 출처 — heredoc 리터럴 생성 금지
cmp -s "$REPO/.antigravity-plugin/plugin.json" "$HOME_DIR/.gemini/config/plugins/llm-wiki-harness/plugin.json" \
  && ok "Antigravity plugin.json == 레포 소스" || no "Antigravity plugin.json이 레포 소스와 다름"

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
(cd "$VAULT" && HOME="$HOME_DIR" bash "$REPO/hooks/session-start" claude </dev/null) \
  | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'Config Gate' in d['hookSpecificOutput']['additionalContext'] else 1)" \
  && ok "볼트 CWD → 주입" || no "볼트 CWD → 주입"
OUT_OUTSIDE="$(cd "$SB" && HOME="$HOME_DIR" bash "$REPO/hooks/session-start" claude </dev/null)"
[ -z "$OUT_OUTSIDE" ] && ok "볼트 밖 CWD → 주입 없음(스팸 방지)" || no "볼트 밖인데 주입됨"

echo "[8] install.sh 덮어쓰기 정책 — 기존 파일 보존 + .llm-wiki 사본 (비파괴)"
# 별도 격리 HOME/vault. 대상 파일을 미리 만들어 두고 install → 원본이 그대로 남고 사본이 생기는지.
SB2="$SB/nondestructive"
H2="$SB2/home"; V2="$SB2/vault"
mkdir -p "$H2/.claude" "$H2/.cursor" "$H2/.codex" "$H2/.gemini/config" "$V2/.cursor"
printf '{"USER_ORIGINAL":"codex"}\n'          > "$H2/.codex/hooks.json"
printf '{"USER_ORIGINAL":"cursor-hooks"}\n'   > "$V2/.cursor/hooks.json"
printf '{"USER_ORIGINAL":"cursor-sandbox"}\n' > "$V2/.cursor/sandbox.json"
printf '# 사용자 전역 AGENTS.md\n'             > "$H2/.gemini/config/AGENTS.md"
HOME="$H2" bash "$REPO/install.sh" --fallback --vault "$V2" >"$SB2/out" 2>&1
grep -q 'USER_ORIGINAL' "$H2/.codex/hooks.json"          && ok "~/.codex/hooks.json 원본 보존"          || no "~/.codex/hooks.json 덮어씀"
grep -q 'USER_ORIGINAL' "$V2/.cursor/hooks.json"         && ok "볼트 .cursor/hooks.json 원본 보존"      || no "볼트 .cursor/hooks.json 덮어씀"
grep -q 'USER_ORIGINAL' "$V2/.cursor/sandbox.json"       && ok "볼트 .cursor/sandbox.json 원본 보존"    || no "볼트 .cursor/sandbox.json 덮어씀"
grep -q '사용자 전역' "$H2/.gemini/config/AGENTS.md"      && ok "~/.gemini AGENTS.md 원본 보존"          || no "~/.gemini AGENTS.md 덮어씀"
[ ! -L "$H2/.gemini/config/AGENTS.md" ]                  && ok "~/.gemini AGENTS.md symlink 교체 안 함" || no "일반 파일이 symlink로 교체됨"
# 사본이 확장자를 보존한 이름으로 옆에 생겼는지
[ -f "$H2/.codex/hooks.llm-wiki.json" ]      && ok "사본 ~/.codex/hooks.llm-wiki.json"          || no "codex 사본 없음"
[ -f "$V2/.cursor/hooks.llm-wiki.json" ]     && ok "사본 .cursor/hooks.llm-wiki.json"           || no "cursor hooks 사본 없음"
[ -f "$V2/.cursor/sandbox.llm-wiki.json" ]   && ok "사본 .cursor/sandbox.llm-wiki.json"         || no "cursor sandbox 사본 없음"
[ -L "$H2/.gemini/config/AGENTS.llm-wiki.md" ] && ok "사본 AGENTS.llm-wiki.md"                  || no "AGENTS 사본 없음"
grep -q '수동 머지 필요' "$SB2/out"           && ok "머지 TODO를 설치 요약에 재고지"             || no "머지 TODO 미고지"
# 사본 내용이 실제 render 결과인지 (placeholder가 남아 있으면 안 된다)
grep -q '{{HOOKS_DIR}}'  "$V2/.cursor/hooks.llm-wiki.json"   && no "cursor 사본에 placeholder 잔존"   || ok "cursor 사본 절대경로 render됨"
grep -q '{{VAULT_ABS}}'  "$V2/.cursor/sandbox.llm-wiki.json" && no "sandbox 사본에 placeholder 잔존"  || ok "sandbox 사본 {{VAULT_ABS}} 치환됨"

echo "[9] install.sh 멱등성 — 재실행 시 사본을 만들지 않는다"
SB3="$SB/idempotent"; H3="$SB3/home"; V3="$SB3/vault"
mkdir -p "$H3/.claude" "$H3/.cursor" "$H3/.codex" "$H3/.gemini/config" "$V3"
HOME="$H3" bash "$REPO/install.sh" --fallback --vault "$V3" >/dev/null 2>&1
HOME="$H3" bash "$REPO/install.sh" --fallback --vault "$V3" >"$SB3/out2" 2>&1
[ "$(find "$SB3" -name '*.llm-wiki.*' | wc -l | tr -d ' ')" = "0" ] && ok "재실행에도 사본 0건" || no "재실행이 사본을 만들었다"
grep -q '이미 최신' "$SB3/out2" && ok "재실행은 '이미 최신'으로 보고" || no "'이미 최신' 보고 없음"

echo "[10] --help — 주석 블록만 출력(코드 누출 없음)"
HELP="$(bash "$REPO/install.sh" --help)"
printf '%s' "$HELP" | grep -qE 'set -euo pipefail|while \[ \$# -gt 0 \]' && no "--help에 코드 누출" || ok "--help 코드 누출 없음"
printf '%s' "$HELP" | grep -q 'install.sh 필수' && ok "--help에 Cursor install.sh 필수 명시" || no "Cursor 필수 명시 없음"

echo "[11] ASCII locale에서도 render가 훅 등록 파일을 만든다 (§3-9 PYTHONUTF8 계약)"
# Windows CI에서 발견(2026-08-04, run 30872986849): install.sh의 render()만 §3-9 계약에서
# 빠져 있었다. render 대상 JSON은 전부 한국어 description을 담고 있어 비UTF-8 locale에서
# UnicodeDecodeError로 죽고 → **훅 등록 파일이 아예 생성되지 않는다**(조용한 설치 실패).
# macOS/Linux는 C locale에서 UTF-8 모드가 자동 활성이므로 그 자동화까지 꺼야 Windows와 같은 조건이 된다.
SB4="$SB/ascii"; H4="$SB4/home"; V4="$SB4/vault"
mkdir -p "$H4/.claude" "$H4/.cursor" "$V4"
HOME="$H4" LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 \
  bash "$REPO/install.sh" --fallback --vault "$V4" >"$SB4/out" 2>&1
[ -f "$H4/.claude/llm-wiki-hooks.settings.json" ] && ok "Claude 훅 스니펫 생성" || no "ASCII locale에서 render 실패 — Claude 훅 스니펫 없음"
[ -f "$H4/.cursor/hooks.json" ]                   && ok "Cursor hooks.json 생성"  || no "ASCII locale에서 render 실패 — Cursor hooks.json 없음"
# render는 읽기만이 아니라 쓰기도 한다 — 한국어가 손상 없이 왕복해야 한다.
grep -q '게이팅하므로 비볼트 세션에 스팸하지 않는다' "$H4/.claude/llm-wiki-hooks.settings.json" 2>/dev/null \
  && ok "한국어 description 왕복 보존" || no "render가 한국어를 손상시켰다"
# 치환도 정상 동작해야 한다 (인코딩만 고치고 기능이 죽으면 의미 없다)
grep -q "$H4/.cursor/hooks" "$H4/.cursor/hooks.json" 2>/dev/null \
  && ok "{{HOOKS_DIR}} 절대경로 치환" || no "ASCII locale에서 치환 실패"

echo ""
echo "SMOKE PASS=$PASS FAIL=$FAIL"
echo "ⓘ 실제 Claude/Codex/Cursor/Antigravity CLI end-to-end는 in-app 검증 필요 (tests/fixtures/README.md, 배포 설계 §10)."
[ "$FAIL" -eq 0 ]
