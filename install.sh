#!/usr/bin/env bash
# install.sh — LLM Wiki Harness 부트스트랩 + 폴백 설치자 (배포 설계 §7-1).
# 배포만 담당 — 볼트 *설정*(.wiki-config.json 등)은 wiki-setup 스킬이 한다.
#
# ── 덮어쓰기 정책 (비파괴) ──
#   기존 파일은 절대 덮어쓰지 않는다.
#   **JSON 등록 파일은 마커 기반으로 병합한다** (place_merge). 우리 항목만 교체하고 남의 항목은
#   그대로 둔다 — 다른 레포도 같은 파일에 등록하므로 공존이 기본값이어야 한다.
#   병합할 수 없는 것(마크다운, 파싱 불가한 JSON)만 원본을 두고 `<이름>.llm-wiki.<확장자>`
#   사본으로 강등하고 수동 머지를 안내한다(설치 요약에 재고지).
#   내용이 이미 동일하면 아무것도 쓰지 않는다 → 재실행 안전(멱등).
#   예외는 하네스가 스스로 생성·소유하는 파일뿐이다:
#     ~/.claude/llm-wiki-hooks.settings.json (병합 원본 · 복구용 참조) ·
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
  # PYTHONUTF8=1 + 명시적 encoding은 §3-9 계약 — render 대상(hooks*.json·plugin.json)은 전부
  # 한국어 description을 담고 있고, python3의 open() 기본 인코딩은 locale이 결정한다. 비UTF-8
  # locale(Windows cp1252)에서는 read()가 UnicodeDecodeError로 죽는데, 그때 이미 "w"로 열린
  # dest는 **빈 파일로 남는다** — 훅 등록 파일이 조용히 0바이트가 되는 최악의 실패 모양이다.
  # 2026-08-04 Windows CI(run 30872986849) smoke.sh에서 실측. 회귀는 smoke.sh [11]이 고정한다.
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
# merge_json <src.json> <dest> — 공유 등록 파일에 우리 항목을 **마커 기반으로 멱등 병합**한다.
#   exit 0 = 병합 반영(변경 있음) · 3 = 이미 최신(쓰지 않음) · 4 = dest 파싱 불가(손대지 않음)
#
# 왜 병합인가: ~/.claude/settings.json·~/.codex/hooks.json·~/.cursor/hooks.json은 **공유 파일**이다.
# 원본 보존 + 사본 안내만 하면 통합이 사용자 손에 남고, 다른 레포도 같은 정책을 쓰면 사본만
# 쌓인 채 훅은 하나도 등록되지 않는다 — 설치는 성공한 것처럼 보이고 가드만 죽는다(§5-5).
#
# 마커는 **경로에 의존하지 않는다.** 우리 항목은 command가 `run-hook.cmd`(폴리글랏 런처)를 경유하고
# 우리 훅 스크립트명을 인자로 싣는다. 절대경로로 식별하면 설치 위치가 바뀔 때(레포 이동·플러그인
# 캐시 갱신) 자기 항목을 못 찾아 중복을 쌓는다 — `conda init`이 이 방식으로 유명한 멱등성 버그를
# 남겼다(conda#8703). 회귀는 tests/install/test-merge-json.sh [3][4]가 고정한다.
#
# 남의 항목을 지우는 것이 최악의 실패이므로 마커는 런처와 훅 스크립트명을 **둘 다** 요구한다.
merge_json() {
  # §3-9: 대상 파일에는 사용자가 쓴 한국어가 들어 있을 수 있고, 병합은 render와 달리
  # 그 파일을 **읽어 되쓴다** — 인코딩 누락의 대가가 사용자 설정 손상이다.
  PYTHONUTF8=1 python3 - "$1" "$2" <<'PY'
import json, os, sys

MARKER = "run-hook.cmd"                                    # 폴리글랏 런처 — 경로 무관
OURS = ("session-start", "wiki-protect-raw.sh", "wiki-validate-frontmatter.sh")
COMMENT_KEYS = ("_comment", "description")                 # 우리 설명문은 남의 파일에 밀어넣지 않는다

def commands(entry):
    """항목 하나에 실린 command 문자열 전부. Claude/Codex는 중첩(hooks[]), Cursor는 평면."""
    out = []
    if isinstance(entry, dict):
        if isinstance(entry.get("command"), str):
            out.append(entry["command"])
        for h in (entry.get("hooks") or []):
            if isinstance(h, dict) and isinstance(h.get("command"), str):
                out.append(h["command"])
    return out

def is_ours(entry):
    return any(MARKER in c and any(s in c for s in OURS) for c in commands(entry))

src_path, dest_path = sys.argv[1], sys.argv[2]
src = json.load(open(src_path, encoding="utf-8"))

if os.path.exists(dest_path):
    try:
        dest = json.loads(open(dest_path, encoding="utf-8").read())
        if not isinstance(dest, dict):
            raise ValueError("최상위가 JSON object가 아니다")
    except Exception as e:
        print("%s" % e, file=sys.stderr)
        sys.exit(4)
else:
    dest = {}

before = json.dumps(dest, ensure_ascii=False, sort_keys=True)

for key, val in src.items():
    if key in COMMENT_KEYS:
        continue
    if key not in dest:
        dest[key] = val
    elif key == "hooks" and isinstance(val, dict) and isinstance(dest[key], dict):
        # 이벤트별로 우리 항목만 걷어내고 현재 항목을 뒤에 붙인다 → 같은 src면 같은 결과(멱등).
        for event, entries in val.items():
            kept = [e for e in (dest[key].get(event) or []) if not is_ours(e)]
            dest[key][event] = kept + list(entries)
    elif isinstance(val, list) and isinstance(dest[key], list):
        # 문자열 목록(Cursor sandbox의 additionalReadwritePaths)은 합집합만 취한다.
        # 개별 경로에는 우리 것을 가릴 마커가 없으므로 **제거하지 않는다** — 사용자 경로를
        # 지우는 위험이 stale 경로가 남는 위험보다 크다.
        dest[key] = dest[key] + [v for v in val if v not in dest[key]]
    # 그 외(스칼라 충돌·타입 불일치)는 사용자 값을 그대로 둔다 — 우리가 이길 근거가 없다.

if json.dumps(dest, ensure_ascii=False, sort_keys=True) == before:
    sys.exit(3)
os.makedirs(os.path.dirname(dest_path) or ".", exist_ok=True)
with open(dest_path, "w", encoding="utf-8") as f:
    json.dump(dest, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
}
# place_merge <src> <find> <rep> <dest> <라벨> — 공유 JSON 등록 파일에 병합 배치.
#   dest 없음/병합 가능 → 우리 항목 반영 (남의 항목·무관 키 보존)
#   변경 없음           → 아무것도 쓰지 않음 (멱등)
#   dest 파싱 불가      → 손대지 않고 사본 + 수동 머지 안내로 강등
place_merge() {
  local src="$1" find="$2" rep="$3" dest="$4" label="$5" existed=0 tmp sc rc err
  [ -e "$dest" ] && existed=1
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp)"
  render "$src" "$find" "$rep" "$tmp"
  rc=0; err="$(merge_json "$tmp" "$dest" 2>&1)" || rc=$?
  rm -f "$tmp"
  case "$rc" in
    0) if [ "$existed" = 1 ]; then say "$label 병합: $dest (하네스 항목 갱신 · 기존 항목 보존)"
       else say "$label 생성: $dest"; fi ;;
    3) say "$label 이미 최신: $dest (변경 없음)" ;;
    *) sc="$(sidecar_path "$dest")"
       render "$src" "$find" "$rep" "$sc"
       say "⚠️ $dest 를 JSON으로 읽을 수 없어 손대지 않았습니다($err) — 하네스 사본을 $sc 에 두었습니다."
       MERGE_TODO+=("$dest  ←  $sc  (JSON 파싱 실패로 병합 불가)") ;;
  esac
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
  # 매니페스트는 레포 소스가 단일 출처다 — heredoc 리터럴 생성은 변경 이력이 추적되지 않고
  # 다른 3개 플랫폼(.claude-plugin/.codex-plugin/.cursor-plugin)과 비대칭이었다.
  cp "$REPO/.antigravity-plugin/plugin.json" "$AGP/plugin.json"
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
    # 스니펫은 병합 원본이자 복구용 참조다(하네스 소유 파일이라 무조건 덮어쓴다).
    # settings.json 병합이 파싱 실패로 강등될 때 사용자가 손으로 옮길 대상이 여기다.
    GUARD_SNIPPET="$HOME/.claude/llm-wiki-hooks.settings.json"
    render "$REPO/hooks/hooks.json" '${CLAUDE_PLUGIN_ROOT}' "$HOME/.claude" "$GUARD_SNIPPET"
    place_merge "$REPO/hooks/hooks.json" '${CLAUDE_PLUGIN_ROOT}' "$HOME/.claude" \
      "$HOME/.claude/settings.json" "Claude ~/.claude/settings.json"
    say "Claude: skills+hooks → ~/.claude/ ; 훅 등록은 settings.json에 병합됨(참조 사본: $GUARD_SNIPPET)."
    SUMMARY+=("✅ Claude(fallback): skills+hooks + settings.json 훅 병합")
  else
    SUMMARY+=("➖ Claude(fallback): ~/.claude 없음 — 건너뜀")
  fi

  # 3b) Codex (글로벌) — ~/.agents(스킬·훅) + ~/.codex(hooks.json)
  if [ -d "$HOME/.agents" ] || [ -d "$HOME/.codex" ] || command -v codex >/dev/null 2>&1; then
    for d in "$REPO"/skills/*/; do link "$d" "$HOME/.agents/skills/$(basename "$d")"; done
    for f in "${HOOK_FILES[@]}"; do link "$REPO/hooks/$f" "$HOME/.agents/hooks/$f"; done
    place_merge "$REPO/hooks/hooks-codex.json" '${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}' "$HOME/.agents" \
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
    place_merge "$REPO/hooks/hooks-cursor.json" '{{HOOKS_DIR}}' "$HOME/.cursor/hooks" \
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
  place_merge "$REPO/hooks/hooks-codex.json" '${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}' "$VAULT/.codex" \
    "$VAULT/.codex/hooks.json" "Codex 볼트 로컬 hooks.json (/hooks trust 필요)"
  # Cursor 볼트 로컬 훅 + 스크립트
  for f in "${HOOK_FILES[@]}"; do link "$REPO/hooks/$f" "$VAULT/.cursor/hooks/$f"; done
  place_merge "$REPO/hooks/hooks-cursor.json" '{{HOOKS_DIR}}' "$VAULT/.cursor/hooks" \
    "$VAULT/.cursor/hooks.json" "Cursor 볼트 로컬 hooks.json"
  # Cursor sandbox: 템플릿의 {{VAULT_ABS}} 치환. render()로 통일(sed와 이중 구현 제거).
  place_merge "$REPO/hooks/cursor-sandbox.template.json" '{{VAULT_ABS}}' "$VAULT" \
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
echo "다음: 볼트에서 \`wiki-setup\`(또는 wiki-setup --vault <path>)으로 .wiki-config.json·~/.llm-wiki/default-vault·QMD를 설정하세요."
