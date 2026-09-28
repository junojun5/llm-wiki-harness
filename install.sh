#!/usr/bin/env bash
# install.sh — 부트스트랩 + 폴백 설치. 볼트 설정은 wiki-setup. 기존 파일은 덮어쓰지 않고, 다르면 .llm-wiki 사본만 둔다.
# Cursor는 훅 등록에 install.sh 필수. Antigravity는 skills+rules만 배치한다(훅 스키마 없음).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FALLBACK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fallback) FALLBACK=1; shift ;;
    # 헤더 주석만 출력한다. 첫 비주석 행에서 멈춘다.
    -h|--help) awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# 소유 판정은 원장이다(mechanism, dest, src). MSYS의 ln -s는 복사라 -L로 구분하지 않는다.
LEDGER="$HOME/.llm-wiki/.placements"
stamp_get() { # stamp_get <dest> → 기록이 있으면 그 줄, 없으면 빈 문자열
  [ -f "$LEDGER" ] || return 0
  grep -F "	$1	" "$LEDGER" | tail -1
}
stamp_put() { # stamp_put <dest> <src> <mechanism>
  local tmp
  mkdir -p "$(dirname "$LEDGER")"
  tmp="$LEDGER.$$"
  if [ -f "$LEDGER" ]; then grep -vF "	$1	" "$LEDGER" >"$tmp" || :; else : >"$tmp"; fi
  printf '%s\t%s\t%s\n' "$3" "$1" "$2" >>"$tmp"
  mv "$tmp" "$LEDGER"
}
owned() { # owned <dest> <src> — 하네스가 놓은 자리인가
  # ① 원장에 있으면 우리 것.
  [ -n "$(stamp_get "$1")" ] && return 0
  # 원장 도입 전 symlink는 흡수한다. 없으면 기존 설치가 다음 실행에서 사이드카를 뒤집어쓴다.
  [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ] && return 0
  # 바이트가 같으면 우리 것(Windows 복사본 포함). 사용자가 고친 파일은 내용이 달라 보존된다.
  [ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2" && return 0
  return 1
}

link() { # link <src> <dst> — 멱등 배치. 우리 자리면 갱신, 아니면 **건드리지 않는다.**
  local src="$1" dst="$2"
  [ -n "$dst" ] || return 0
  mkdir -p "$(dirname "$dst")"
  # 소유가 아니면 배치하지 않는다. rm은 사용자 디렉터리를 지우고, ln -sfn은 그 안쪽에 링크를 만든다.
  if { [ -e "$dst" ] || [ -L "$dst" ]; } && ! owned "$dst" "$src"; then
    say "⚠️ $dst 보존 — 하네스가 놓은 자리가 아닙니다(사용자 소유)."
    return 0
  fi
  rm -rf "$dst"
  ln -sfn "$src" "$dst" 2>/dev/null || true
  # MSYS는 ln이 복사로 떨어진다. symlink가 아니면 직접 복사하고 원장에 copy로 남긴다.
  if [ -L "$dst" ]; then
    stamp_put "$dst" "$src" symlink
  else
    rm -rf "$dst"; cp -R "$src" "$dst"; stamp_put "$dst" "$src" copy
  fi
}
say() { printf '  %s\n' "$*"; }
render() { # render <src.json> <find> <replace> <dest> — 플러그인 루트 참조를 절대경로로 치환(sed 대신 python: 중첩 브레이스 안전)
  mkdir -p "$(dirname "$4")"
  # 한국어 JSON이라 UTF-8을 고정한다. locale 인코딩으로 읽다 죽으면 dest가 빈 파일로 남는다.
  PYTHONUTF8=1 python3 -c 'import sys; open(sys.argv[4],"w",encoding="utf-8").write(open(sys.argv[1],encoding="utf-8").read().replace(sys.argv[2],sys.argv[3]))' "$1" "$2" "$3" "$4"
}
sidecar_path() { # sidecar_path <dest> — 확장자를 보존한 사본 경로 (hooks.json → hooks.llm-wiki.json)
  local d="$1" dir base
  dir="$(dirname "$d")"; base="$(basename "$d")"
  case "$base" in
    *.*) printf '%s/%s.llm-wiki.%s\n' "$dir" "${base%.*}" "${base##*.}" ;;
    *)   printf '%s/%s.llm-wiki\n'    "$dir" "$base" ;;
  esac
}
# 비파괴 배치. 없으면 생성, 같으면 무동작, 다르면 원본을 두고 .llm-wiki 사본만 만든다.
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
# 비파괴 배치. 우리 자리면 갱신하고, 사용자 파일이면 .llm-wiki 사본만 둔다.
place_link() {
  local src="$1" dest="$2" label="$3" sc
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    link "$src" "$dest"; say "$label 생성: $dest"; return
  fi
  if owned "$dest" "$src"; then
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

echo "[1] ~/.llm-wiki/scripts (도구 비종속 런타임)"
for s in resolve-vault.sh validate-frontmatter.sh build-link-graph.sh; do
  link "$REPO/scripts/$s" "$HOME/.llm-wiki/scripts/$s"
done
say "scripts/* → ~/.llm-wiki/scripts/ (symlink, MSYS에선 복사) — Config Gate·가드 훅의 공용 의존"
SUMMARY+=("✅ ~/.llm-wiki/scripts (공유 런타임)")

# Antigravity는 훅 스키마가 없어 skills+rules만 둔다. 이 경로가 유일한 전역 배치다.
if [ -d "$HOME/.gemini" ] || command -v agy >/dev/null 2>&1; then
  echo "[2] Antigravity 감지 → ~/.gemini/config/plugins (전역 플러그인, skills+rules)"
  AGP="$HOME/.gemini/config/plugins/llm-wiki-harness"
  mkdir -p "$AGP/rules"
  # plugin.json은 레포 파일이 정본이다.
  cp "$REPO/.antigravity-plugin/plugin.json" "$AGP/plugin.json"
  for d in "$REPO"/skills/*/; do link "$d" "$AGP/skills/$(basename "$d")"; done
  link "$REPO/AGENTS.md" "$AGP/rules/llm-wiki.md"
  # 전역 AGENTS.md는 사용자가 직접 쓴 파일일 수 있다 — 기존 파일을 우리 배치로 교체하지 않는다
  place_link "$REPO/AGENTS.md" "$HOME/.gemini/config/AGENTS.md" "Antigravity 전역 AGENTS.md"
  say "plugin → ~/.gemini/config/plugins/llm-wiki-harness/ (plugin.json + skills + rules/llm-wiki.md=AGENTS.md)"
  say "⚠️ hooks.json 미포함 — Antigravity 훅 스키마 미공개(agy가 파싱은 하나 0 handlers). raw/ 보호는 AGENTS.md 지침."
  SUMMARY+=("✅ Antigravity 전역 플러그인: skills+rules / ⚠️ 훅 없음(스키마 미공개)")
else
  SUMMARY+=("➖ Antigravity: ~/.gemini 없음 — 건너뜀")
fi

# 홈 전역 배치. 훅 command의 플러그인 루트를 설치 절대경로로 바꾼다.
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

# 프로젝트-로컬. 볼트는 ~/.llm-wiki/default-vault에서 읽는다.
VAULT=""
if [ -f "$HOME/.llm-wiki/default-vault" ]; then
  VAULT="$(cat "$HOME/.llm-wiki/default-vault")"
fi
if [ -n "$VAULT" ] && [ -d "$VAULT" ]; then
  VAULT="$(cd "$VAULT" && pwd)"
  echo "[4] 프로젝트-로컬 배치 → $VAULT (Codex/Cursor 볼트 로컬 hooks + AGENTS.md)"
  # 공용 .agents/skills (Cursor·Codex 프로젝트 공통)
  for d in "$REPO"/skills/*/; do link "$d" "$VAULT/.agents/skills/$(basename "$d")"; done
  # 사용자 AGENTS.md가 있을 수 있어 비파괴로 둔다.
  place_link "$REPO/AGENTS.md" "$VAULT/AGENTS.md" "볼트 루트 AGENTS.md"
  place_link "$REPO/AGENTS.md" "$VAULT/.agents/AGENTS.md" "볼트 .agents/AGENTS.md"
  # Codex 볼트 로컬 훅 (플러그인/전역 미사용 시). 훅 스크립트 배치 + hooks.json을 볼트 절대경로로 렌더.
  for f in "${HOOK_FILES[@]}"; do link "$REPO/hooks/$f" "$VAULT/.codex/hooks/$f"; done
  place_render "$REPO/hooks/hooks-codex.json" '${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}' "$VAULT/.codex" \
    "$VAULT/.codex/hooks.json" "Codex 볼트 로컬 hooks.json (/hooks trust 필요)"
  # Cursor 볼트 로컬 훅 + 스크립트
  for f in "${HOOK_FILES[@]}"; do link "$REPO/hooks/$f" "$VAULT/.cursor/hooks/$f"; done
  place_render "$REPO/hooks/hooks-cursor.json" '{{HOOKS_DIR}}' "$VAULT/.cursor/hooks" \
    "$VAULT/.cursor/hooks.json" "Cursor 볼트 로컬 hooks.json"
  # sandbox는 볼트와 ~/.cursor 양쪽에 둔다. 전역이 있어야 다른 워크스페이스에서도 경로가 열린다.
  place_render "$REPO/hooks/cursor-sandbox.template.json" '{{VAULT_ABS}}' "$VAULT" \
    "$VAULT/.cursor/sandbox.json" "Cursor sandbox.json (볼트 로컬)"
  if [ -d "$HOME/.cursor" ]; then
    place_render "$REPO/hooks/cursor-sandbox.template.json" '{{VAULT_ABS}}' "$VAULT" \
      "$HOME/.cursor/sandbox.json" "Cursor sandbox.json (전역 ~/.cursor)"
  fi
  say ".agents/skills/, 루트 AGENTS.md(+.agents/), .codex/hooks(+hooks.json), .cursor/hooks(+hooks.json), .cursor/sandbox.json(볼트+전역)"
  SUMMARY+=("✅ 프로젝트-로컬: Codex/Cursor 볼트 로컬 hooks + AGENTS.md, .agents/skills")
else
  echo "[4] 프로젝트-로컬: default-vault 없음 — wiki-setup을 먼저 실행한 뒤 install.sh를 재실행하세요."
  SUMMARY+=("➖ 프로젝트-로컬(Cursor/Codex): default-vault 미설정 — wiki-setup 후 재실행")
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
echo "다음: 볼트에서 \`wiki-setup\`(또는 wiki-setup --vault <path>)으로 .wiki-config.json·~/.llm-wiki/default-vault·QMD를 설정하세요."
