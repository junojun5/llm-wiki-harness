#!/usr/bin/env bash
# install.sh — LLM Wiki Harness 부트스트랩 + 폴백 설치자 (배포 설계 §7-1).
# 배포만 담당 — 볼트 *설정*(.wiki-config.json 등)은 wiki-setup 스킬이 한다.
#
# ── 덮어쓰기 정책 (비파괴) ──
#   기존 파일은 절대 덮어쓰지 않는다. 이미 있으면 원본을 그대로 두고 render 결과를
#   `<이름>.llm-wiki.<확장자>` 사본으로 옆에 두고 수동 머지를 안내한다(설치 요약에 재고지).
#   내용이 이미 동일하면 사본도 만들지 않는다 → 재실행 안전(멱등).
#   예외는 하네스가 스스로 생성·소유하는 파일뿐이다:
#     ~/.claude/llm-wiki-hooks.settings.json (머지용 스니펫) ·
#     ~/.gemini/config/plugins/llm-wiki-harness/* (하네스 전용 번들)
#
# ── 권장 설치 = 플러그인 마켓플레이스 (Cursor 제외 — 아래 참조) ──
#   Claude Code : /plugin → llm-wiki-harness. skills+hooks 자동 등록(${CLAUDE_PLUGIN_ROOT}). 첫 SessionStart가
#                 ~/.llm-wiki/scripts를 플러그인 루트에서 자가-부트스트랩.
#   Codex CLI   : /plugins 설치 → /hooks에서 trust(비관리 훅). 비Windows.
#                 ([features] hooks=true는 0.145.0에서 불필요 — stable·기본 활성)
#   Cursor      : ⚠️ **install.sh 필수.** 플러그인은 skills만 실린다 — cursor-agent가 매니페스트의
#                 hooks를 소비하지 않으므로(실측) 훅은 이 스크립트가 .cursor/hooks.json을 배치해야
#                 등록된다. `--fallback`(전역) 또는 `--vault <p>`(프로젝트)를 반드시 실행한다.
#                 Cloud Agent는 sessionStart 미지원(로컬 데스크톱 전용).
#   Antigravity : 훅 스키마 미공개 → 플러그인은 skills+rules(AGENTS.md)만. raw/ 가드는 AGENTS.md 소프트 룰.
#
# ── 이 스크립트가 하는 일 ──
#   기본(인자 없음):
#     [1] ~/.llm-wiki/scripts 부트스트랩 — 모든 도구 공용 런타임(Config Gate). *Antigravity는 훅이 없어
#         이 부트스트랩이 유일 경로*이고, 나머지 도구엔 마켓플레이스 자가-부트스트랩의 안전망.
#     [2] Antigravity 전역 플러그인 번들(skills + rules/AGENTS.md) — ~/.gemini 감지 시. 훅 미포함(스키마 미공개).
#   옵션:
#     --fallback  : 마켓플레이스를 못 쓰는 환경용. Claude/Codex/Cursor에 skills+hooks를 홈 전역으로 symlink하고
#                   플러그인과 동일한 훅 등록을 수동 재현(command의 플러그인 루트 참조를 절대경로로 치환).
#     --vault <p> : 프로젝트-로컬 배치(Cursor/Codex 볼트 로컬 hooks + 루트 AGENTS.md).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT=""
FALLBACK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) VAULT="${2:-}"; shift 2 ;;
    --fallback) FALLBACK=1; shift ;;
    # 헤더 주석 블록만 출력한다 — 첫 비주석 행에서 멈추므로 헤더가 자라도 코드가 새지 않는다
    # (구현: sed -n '2,30p'는 set -euo pipefail·변수 선언·while 루프까지 도움말로 출력했다)
    -h|--help) awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

link() { # link <src> <dst> — 멱등 symlink (디렉토리 보존)
  mkdir -p "$(dirname "$2")"
  ln -sfn "$1" "$2"
}
say() { printf '  %s\n' "$*"; }
render() { # render <src.json> <find> <replace> <dest> — 플러그인 루트 참조를 절대경로로 치환(sed 대신 python: 중첩 브레이스 안전)
  mkdir -p "$(dirname "$4")"
  python3 -c 'import sys; open(sys.argv[4],"w").write(open(sys.argv[1]).read().replace(sys.argv[2],sys.argv[3]))' "$1" "$2" "$3" "$4"
}
sidecar_path() { # sidecar_path <dest> — 확장자를 보존한 사본 경로 (hooks.json → hooks.llm-wiki.json)
  local d="$1" dir base
  dir="$(dirname "$d")"; base="$(basename "$d")"
  case "$base" in
    *.*) printf '%s/%s.llm-wiki.%s\n' "$dir" "${base%.*}" "${base##*.}" ;;
    *)   printf '%s/%s.llm-wiki\n'    "$dir" "$base" ;;
  esac
}
# place_render <src> <find> <replace> <dest> <라벨> — 비파괴 배치 (덮어쓰기 정책은 헤더 참조).
#   dest 없음        → render해서 배치
#   dest 있고 동일   → 아무것도 안 함 (멱등)
#   dest 있고 다름   → 원본 보존 + 사본을 옆에 두고 머지 안내
place_render() {
  local src="$1" find="$2" rep="$3" dest="$4" label="$5" sc tmp
  if [ ! -e "$dest" ]; then
    render "$src" "$find" "$rep" "$dest"; say "$label 생성: $dest"; return
  fi
  tmp="$(mktemp)"
  render "$src" "$find" "$rep" "$tmp"
  if cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"; say "$label 이미 최신: $dest (변경 없음)"; return
  fi
  sc="$(sidecar_path "$dest")"
  mv "$tmp" "$sc"
  say "⚠️ 기존 $dest 보존 — 하네스 사본을 $sc 에 두었습니다. 필요한 항목을 수동 머지하세요."
  MERGE_TODO+=("$dest  ←  $sc")
}
# place_link <src> <dest> <라벨> — 비파괴 symlink. 우리 symlink면 갱신(멱등),
#   사용자 파일/다른 링크면 보존하고 사본 경로에 건다.
place_link() {
  local src="$1" dest="$2" label="$3" sc
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    link "$src" "$dest"; say "$label 생성: $dest"; return
  fi
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    link "$src" "$dest"; say "$label 이미 최신: $dest (변경 없음)"; return
  fi
  sc="$(sidecar_path "$dest")"
  link "$src" "$sc"
  say "⚠️ 기존 $dest 보존 — 하네스 사본을 $sc 에 두었습니다. 필요한 내용을 수동 머지하세요."
  MERGE_TODO+=("$dest  ←  $sc")
}
HOOK_FILES=(session-start wiki-protect-raw.sh wiki-validate-frontmatter.sh run-hook.cmd probe-hook.sh)
SUMMARY=()
MERGE_TODO=()

echo "── LLM Wiki Harness 설치 ──"

# ─────────────────────────────────────────────────────────────────────────────
# [1] 도구 비종속 런타임 홈 (항상) — 공유 스크립트 symlink
echo "[1] ~/.llm-wiki/scripts (도구 비종속 런타임)"
for s in resolve-vault.sh validate-frontmatter.sh build-link-graph.sh; do
  link "$REPO/scripts/$s" "$HOME/.llm-wiki/scripts/$s"
done
say "scripts/* → ~/.llm-wiki/scripts/ (symlink) — Config Gate·가드 훅의 공용 의존"
SUMMARY+=("✅ ~/.llm-wiki/scripts (공유 런타임)")

# ─────────────────────────────────────────────────────────────────────────────
# [2] Antigravity 전역 플러그인 (항상, ~/.gemini 감지 시) — 훅 미포함(스키마 미공개, §5-0).
#     플러그인 매니페스트가 훅을 자동등록하지 못하므로 install.sh가 유일한 전역 배치 경로.
if [ -d "$HOME/.gemini" ] || command -v agy >/dev/null 2>&1; then
  echo "[2] Antigravity 감지 → ~/.gemini/config/plugins (전역 플러그인, skills+rules)"
  AGP="$HOME/.gemini/config/plugins/llm-wiki-harness"
  mkdir -p "$AGP/rules"
  printf '{ "name": "llm-wiki-harness", "description": "LLM Wiki 하네스 — wiki 스킬 + AGENTS.md 규칙" }\n' > "$AGP/plugin.json"
  for d in "$REPO"/skills/*/; do link "$d" "$AGP/skills/$(basename "$d")"; done
  link "$REPO/AGENTS.md" "$AGP/rules/llm-wiki.md"
  # 전역 AGENTS.md는 사용자가 직접 쓴 파일일 수 있다 — 기존 파일을 symlink로 교체하지 않는다
  place_link "$REPO/AGENTS.md" "$HOME/.gemini/config/AGENTS.md" "Antigravity 전역 AGENTS.md"
  say "plugin → ~/.gemini/config/plugins/llm-wiki-harness/ (plugin.json + skills + rules/llm-wiki.md=AGENTS.md)"
  say "⚠️ hooks.json 미포함 — Antigravity 훅 스키마 미공개(agy가 파싱은 하나 0 handlers). raw/ 보호는 AGENTS.md 지침."
  SUMMARY+=("✅ Antigravity 전역 플러그인: skills+rules / ⚠️ 훅 없음(스키마 미공개)")
else
  SUMMARY+=("➖ Antigravity: ~/.gemini 없음 — 건너뜀")
fi

# ─────────────────────────────────────────────────────────────────────────────
# [3] --fallback: 마켓플레이스 대체 — Claude/Codex/Cursor 홈 전역 배치.
#     플러그인 매니페스트의 훅 command는 플러그인 루트 env var/상대경로를 쓰므로, 홈 전역 수동 배치에선
#     그 참조를 실제 설치 절대경로로 치환한 hooks 설정을 생성/안내한다(플러그인과 동일 동작 재현).
if [ "$FALLBACK" = 1 ]; then
  echo "[3] --fallback: Claude/Codex/Cursor 홈 전역 (마켓플레이스 미사용 환경)"

  # 3a) Claude Code (글로벌) — ~/.claude
  if [ -d "$HOME/.claude" ]; then
    for d in "$REPO"/skills/*/; do link "$d" "$HOME/.claude/skills/$(basename "$d")"; done
    for f in "${HOOK_FILES[@]}"; do link "$REPO/hooks/$f" "$HOME/.claude/hooks/$f"; done
    GUARD_SNIPPET="$HOME/.claude/llm-wiki-hooks.settings.json"
    render "$REPO/hooks/hooks.json" '${CLAUDE_PLUGIN_ROOT}' "$HOME/.claude" "$GUARD_SNIPPET"
    say "Claude: skills+hooks → ~/.claude/ ; 훅 등록은 $GUARD_SNIPPET 의 hooks 블록을 settings.json에 수동 머지(기존 보존)."
    SUMMARY+=("✅ Claude(fallback): skills+hooks / ⚠️ settings.json 머지 수동 → $GUARD_SNIPPET")
  else
    SUMMARY+=("➖ Claude(fallback): ~/.claude 없음 — 건너뜀")
  fi

  # 3b) Codex (글로벌) — ~/.agents(스킬·훅) + ~/.codex(hooks.json)
  if [ -d "$HOME/.agents" ] || [ -d "$HOME/.codex" ] || command -v codex >/dev/null 2>&1; then
    for d in "$REPO"/skills/*/; do link "$d" "$HOME/.agents/skills/$(basename "$d")"; done
    for f in "${HOOK_FILES[@]}"; do link "$REPO/hooks/$f" "$HOME/.agents/hooks/$f"; done
    place_render "$REPO/hooks/hooks-codex.json" '${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}' "$HOME/.agents" \
      "$HOME/.codex/hooks.json" "Codex ~/.codex/hooks.json"
    say "Codex: skills → ~/.agents/skills/ ; hooks → ~/.agents/hooks/ ; 등록 후 /hooks에서 trust 필요(미완 시 무경고 no-op)."
    SUMMARY+=("✅ Codex(fallback): skills+hooks / ⚠️ ~/.codex/hooks.json trust 필요")
  else
    SUMMARY+=("➖ Codex(fallback): ~/.agents·~/.codex 없음 — 건너뜀")
  fi

  # 3c) Cursor 전역(User) — ~/.cursor
  if [ -d "$HOME/.cursor" ]; then
    for d in "$REPO"/skills/*/; do link "$d" "$HOME/.cursor/skills/$(basename "$d")"; done
    for f in "${HOOK_FILES[@]}"; do link "$REPO/hooks/$f" "$HOME/.cursor/hooks/$f"; done
    place_render "$REPO/hooks/hooks-cursor.json" '{{HOOKS_DIR}}' "$HOME/.cursor/hooks" \
      "$HOME/.cursor/hooks.json" "Cursor ~/.cursor/hooks.json (User 전역, 절대경로)"
    say "Cursor: skills → ~/.cursor/skills/ ; hooks → ~/.cursor/hooks/"
    SUMMARY+=("✅ Cursor 전역(User): skills+hooks — Cursor는 이 경로가 훅의 유일한 등록 수단")
  else
    SUMMARY+=("➖ Cursor(fallback): ~/.cursor 없음 — 건너뜀")
  fi
else
  SUMMARY+=("➖ --fallback 미지정 — Claude/Codex/Cursor는 플러그인 마켓플레이스로 설치 권장")
fi

# ─────────────────────────────────────────────────────────────────────────────
# [4] 프로젝트-로컬 (Cursor/Codex) — --vault 지정 시
if [ -n "$VAULT" ]; then
  VAULT="$(cd "$VAULT" && pwd)"
  echo "[4] 프로젝트-로컬 배치 → $VAULT (Codex/Cursor 볼트 로컬 hooks + AGENTS.md)"
  # 공용 .agents/skills (Cursor·Codex 프로젝트 공통)
  for d in "$REPO"/skills/*/; do link "$d" "$VAULT/.agents/skills/$(basename "$d")"; done
  # AGENTS.md: 루트(canonical, Cursor·Codex) + .agents/(Antigravity) symlink.
  # 볼트에 이미 사용자 AGENTS.md가 있을 수 있으므로 비파괴 배치한다.
  place_link "$REPO/AGENTS.md" "$VAULT/AGENTS.md" "볼트 루트 AGENTS.md"
  place_link "$REPO/AGENTS.md" "$VAULT/.agents/AGENTS.md" "볼트 .agents/AGENTS.md"
  # Codex 볼트 로컬 훅 (플러그인/전역 미사용 시). 훅 스크립트 symlink + hooks.json을 볼트 절대경로로 렌더.
  for f in "${HOOK_FILES[@]}"; do link "$REPO/hooks/$f" "$VAULT/.codex/hooks/$f"; done
  place_render "$REPO/hooks/hooks-codex.json" '${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}' "$VAULT/.codex" \
    "$VAULT/.codex/hooks.json" "Codex 볼트 로컬 hooks.json (/hooks trust 필요)"
  # Cursor 볼트 로컬 훅 + 스크립트
  for f in "${HOOK_FILES[@]}"; do link "$REPO/hooks/$f" "$VAULT/.cursor/hooks/$f"; done
  place_render "$REPO/hooks/hooks-cursor.json" '{{HOOKS_DIR}}' "$VAULT/.cursor/hooks" \
    "$VAULT/.cursor/hooks.json" "Cursor 볼트 로컬 hooks.json"
  # Cursor sandbox: 템플릿의 {{VAULT_ABS}} 치환. render()로 통일(sed와 이중 구현 제거).
  place_render "$REPO/hooks/cursor-sandbox.template.json" '{{VAULT_ABS}}' "$VAULT" \
    "$VAULT/.cursor/sandbox.json" "Cursor sandbox.json"
  say ".agents/skills/, 루트 AGENTS.md(+.agents/ symlink), .codex/hooks(+hooks.json), .cursor/hooks(+hooks.json), .cursor/sandbox.json"
  SUMMARY+=("✅ 프로젝트-로컬: Codex/Cursor 볼트 로컬 hooks + AGENTS.md, .agents/skills")
else
  SUMMARY+=("➖ 프로젝트-로컬(--vault): 미지정 — 건너뜀")
fi

echo ""
echo "── 설치 요약 ──"
for line in "${SUMMARY[@]}"; do echo "  $line"; done
if [ "${#MERGE_TODO[@]}" -gt 0 ]; then
  echo ""
  echo "── ⚠️ 수동 머지 필요 (기존 파일을 보존했습니다) ──"
  for line in "${MERGE_TODO[@]}"; do echo "  $line"; done
  echo "  각 사본의 내용을 원본에 반영한 뒤 사본은 삭제하세요."
fi
echo ""
echo "다음: 볼트에서 \`/wiki-setup\`(또는 wiki-setup --vault <path>)으로 .wiki-config.json·~/.llm-wiki/default-vault·QMD를 설정하세요."
