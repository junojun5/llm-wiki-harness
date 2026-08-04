#!/usr/bin/env bash
# check-guards.sh [--platform claude|codex|cursor|antigravity] — 가드 훅 생존 점검. 스펙 §5-5.
#
# 왜 있는가 — 가드는 **fail-open**이다(§5-2). resolver가 죽으면 raw/만 골라 막을 수 없어 통과시키는데,
# 그 강등을 알리는 session-start 고지가 **같은 훅 시스템 위에 살아** 함께 죽는다(상관된 실패).
# 2026-08-04 Windows에서 실제로 그 모양이 나왔다: install.sh의 render()가 인코딩으로 죽어 훅 등록
# 파일이 0바이트로 남았고, 설치는 성공한 것처럼 보이며 가드만 사라졌다. 세 번째 방어선은 훅 밖,
# 즉 스킬이 직접 실행하는 이 스크립트다.
#
# ⚠️ **검증 범위의 경계** — "발화"는 검증하지 않는다(할 수 없다). 에이전트 런타임이 등록된 command를
#    실제로 호출하는지는 에이전트 소관이다. 실례로 Codex는 `/hooks` trust 전까지 **등록 정상 + 무발화**
#    상태이며 여기서 초록불이 나온다. 이 경계를 리포트에 함께 내지 않으면 점검 자체가 거짓 안심이 된다.
#
# 2층으로 본다 (서로를 대체하지 못한다):
#   L1 등록 건강   — 등록 파일이 살아 있고 참조 경로가 실재하는가
#   L2 판정 정확성 — 훅 본체가 옳게 판정하는가 (합성 페이로드 프로브, 볼트 무부작용)
#
# 출력: GUARD <platform> <layer> <status> <detail> / SUMMARY guards=N ok=N degraded=N skipped=N
# 종료: 0=정상·해당없음 · 1=degraded 1건 이상 · 2=점검 불가(resolver 실패)
set -u

PLATFORM_FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) PLATFORM_FILTER="${2:-}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- Step 0: 볼트 resolve (§3-2). 실패는 degraded가 아니라 **점검 불가**다 --------------
RESOLVED="$(bash "$HOME/.llm-wiki/scripts/resolve-vault.sh" 2>/dev/null)" || {
  echo "GUARD - - unknown resolver 실패 — 볼트를 확정할 수 없어 점검하지 않았습니다"
  echo "SUMMARY guards=0 ok=0 degraded=0 skipped=0"
  exit 2
}
VAULT_ROOT="$(printf '%s\n' "$RESOLVED" | sed -n 's/^VAULT_PATH=//p')"
RAW_DIR="$(printf '%s\n' "$RESOLVED" | sed -n 's/^RAW_DIR=//p')"
WIKI_DIR="$(printf '%s\n' "$RESOLVED" | sed -n 's/^WIKI_DIR=//p')"
[ -n "$VAULT_ROOT" ] && [ -n "$RAW_DIR" ] && [ -n "$WIKI_DIR" ] || {
  echo "GUARD - - unknown resolver 출력 불완전 — 점검하지 않았습니다"
  echo "SUMMARY guards=0 ok=0 degraded=0 skipped=0"
  exit 2
}

# --- L1: 등록 스캔 (python3 단일 블록) ---------------------------------------------------
# PYTHONUTF8=1은 §3-9 계약 — 등록 JSON에 한국어 description이 들어 있고 경로에 한글이 올 수 있다.
# 기계 판독 라인으로 돌려받는다: REG|<platform>|<layer>|<status>|<detail>|<probe_script>|<probe_arg>
L1="$(VAULT_ROOT="$VAULT_ROOT" PLATFORM_FILTER="$PLATFORM_FILTER" PYTHONUTF8=1 python3 - <<'PY'
import json, os, shlex, sys
from pathlib import Path

home = Path(os.path.expanduser("~"))
vault = Path(os.environ["VAULT_ROOT"])
only = os.environ.get("PLATFORM_FILTER") or ""

OURS = ("run-hook.cmd", "wiki-protect-raw.sh", "wiki-validate-frontmatter.sh", "session-start")

# ⚠️ `$`+`{` 리터럴을 이 블록에 직접 쓰지 않는다 — bash 3.2(macOS 기본)의 `$( )` 파서는
#    heredoc 안에서도 그 두 글자를 파라미터 확장 시작으로 읽어 닫는 `)`를 못 찾는다
#    (2026-08-04 실측: `unexpected EOF while looking for matching '"'`). 조립해서 쓴다.
EXP = "$" + "{"
PR_CLAUDE = EXP + "CLAUDE_PLUGIN_ROOT}"
PR_CODEX = EXP + "PLUGIN_ROOT:-" + EXP + "CLAUDE_PLUGIN_ROOT}}"

def emit(platform, status, detail, script="", arg="", layer="L1"):
    # layer는 "이 플랫폼에 등록이라는 개념이 있는가"를 담는다. Antigravity는 훅 표면 자체가
    # 없으므로 "-" — L1 미설치와 구분해야 "언젠가 설치하면 켜진다"는 오해가 생기지 않는다.
    print("REG|%s|%s|%s|%s|%s|%s" % (platform, layer, status, detail, script, arg))

def walk_commands(node, out):
    """등록 스키마가 플랫폼마다 다르다(중첩 hooks 배열 vs 평면 배열). command 키를 재귀로 긁는다."""
    if isinstance(node, dict):
        c = node.get("command")
        if isinstance(c, str):
            out.append(c)
        for v in node.values():
            walk_commands(v, out)
    elif isinstance(node, list):
        for v in node:
            walk_commands(v, out)

def parse_command(cmd, plugin_root):
    """command → (launcher, script, platform_arg). ${CLAUDE_PLUGIN_ROOT}는 런타임 확장이라
    등록 파일이 플러그인 레이아웃(<root>/hooks/x.json)일 때만 정적으로 해석할 수 있다."""
    if plugin_root:
        cmd = cmd.replace(PR_CODEX, plugin_root)
        cmd = cmd.replace(PR_CLAUDE, plugin_root)
    try:
        toks = shlex.split(cmd)
    except ValueError:
        toks = cmd.split()
    if not toks:
        return None
    launcher = toks[0]
    script = toks[1] if len(toks) > 1 else ""
    arg = toks[2] if len(toks) > 2 else "claude"
    return launcher, script, arg

def classify(platform, regfile, tool_present, plugin_root=None, note=""):
    """등록 파일 하나를 4상태로 가른다. '없음'을 전부 경고로 만들면 이 점검은 무시된다."""
    if regfile is None or not regfile.exists():
        if not tool_present:
            emit(platform, "n/a", note or "미설치 — 이 도구를 쓰지 않습니다")
        else:
            emit(platform, "absent", note or "도구는 있으나 훅이 등록되어 있지 않습니다")
        return
    if regfile.stat().st_size == 0:
        emit(platform, "corrupt", "%s 가 0바이트입니다 — 설치가 중간에 죽었습니다" % regfile)
        return
    try:
        data = json.loads(regfile.read_text(encoding="utf-8"))
    except Exception as e:
        emit(platform, "corrupt", "%s 파싱 실패: %s" % (regfile, type(e).__name__))
        return
    cmds = []
    walk_commands(data.get("hooks", data), cmds)
    ours = [c for c in cmds if any(o in c for o in OURS)]
    if not ours:
        emit(platform, "absent", "%s 에 LLM Wiki 훅이 없습니다" % regfile)
        return
    if any(EXP in c for c in ours) and not plugin_root:
        emit(platform, "unexpanded", "%s 의 command가 런타임 확장 참조라 정적 검증 불가" % regfile)
        return
    probe_script, probe_arg = "", ""
    for c in ours:
        p = parse_command(c, plugin_root)
        if not p:
            continue
        launcher, script, arg = p
        if not os.path.exists(launcher):
            emit(platform, "broken-ref", "등록된 런처가 실재하지 않습니다: %s" % launcher)
            return
        if script:
            body = os.path.join(os.path.dirname(launcher), script)
            if not os.path.exists(body):
                emit(platform, "broken-ref", "등록된 훅 본체가 실재하지 않습니다: %s" % body)
                return
            if script == "wiki-protect-raw.sh":
                probe_script, probe_arg = body, arg
    emit(platform, "ok", "%s — 훅 %d건 등록·참조 실재" % (regfile, len(ours)), probe_script, probe_arg)

def want(p):
    return (not only) or only == p

# --- Claude: 마켓플레이스 캐시 우선, 없으면 --fallback 경로(settings.json 본체) ---
if want("claude"):
    claude_dir = home / ".claude"
    plug = None
    pdir = claude_dir / "plugins"
    if pdir.is_dir():
        # 설치 경로가 **버전 스코프**라 하드코딩 금지 — glob으로 찾는다 (배포 설계 §10)
        found = sorted(pdir.glob("**/hooks/hooks.json"))
        if found:
            plug = found[-1]
    if plug is not None:
        classify("claude", plug, True, plugin_root=str(plug.parent.parent))
    else:
        settings = claude_dir / "settings.json"
        snippet = claude_dir / "llm-wiki-hooks.settings.json"
        # ⚠️ 스니펫은 install.sh가 만드는 **머지 안내 파일**이지 등록이 아니다.
        #    그 존재를 등록으로 세면 이 점검이 잡아야 할 바로 그 결함을 놓친다.
        note = ""
        if snippet.exists():
            note = "훅이 settings.json에 머지되지 않았습니다 (%s 의 hooks 블록을 머지하세요)" % snippet
        classify("claude", settings if settings.exists() else None, claude_dir.is_dir(), note=note)

if want("codex"):
    classify("codex", home / ".codex" / "hooks.json",
             (home / ".codex").is_dir() or (home / ".agents").is_dir())

if want("cursor"):
    classify("cursor", home / ".cursor" / "hooks.json", (home / ".cursor").is_dir())

if want("cursor-vault"):
    classify("cursor-vault", vault / ".cursor" / "hooks.json", (vault / ".cursor").is_dir())

if want("antigravity"):
    # 공식 훅 스키마 미공개(404 · agy가 파싱하고도 0 handlers) — 검증 대상이 아니다
    emit("antigravity", "n/a", "훅 스키마 미공개 — raw/ 보호는 AGENTS.md 소프트 룰", layer="-")
PY
)" || {
  echo "GUARD - - unknown L1 스캔 실패"
  echo "SUMMARY guards=0 ok=0 degraded=0 skipped=0"
  exit 2
}

# --- L2: 합성 페이로드 프로브 -------------------------------------------------------------
# 훅 본체에 **경로 문자열만** 넘겨 판정을 받는다. 훅은 파일을 만들지 않으므로 볼트 무부작용이다
# (read-only 스킬 경계 준수 — tests/scripts/test-check-guards.sh가 고정한다).
# 음성 대조군(wiki/)이 반드시 함께 간다 — 양성만 보면 "무조건 차단"하는 고장도 초록불이 된다.
probe() { # probe <script> <arg> <path> → 차단이면 0, 통과면 1
  local out code
  out="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$3" \
        | (cd "$VAULT_ROOT" && bash "$1" "$2" 2>/dev/null))"
  code=$?
  [ "$code" = 2 ] && return 0
  printf '%s' "$out" | grep -q '"permission"[[:space:]]*:[[:space:]]*"deny"' && return 0
  return 1
}

GUARDS=0; OK=0; DEGRADED=0; SKIPPED=0
while IFS='|' read -r tag platform layer status detail script arg; do
  [ "$tag" = "REG" ] || continue
  GUARDS=$((GUARDS+1))
  echo "GUARD $platform $layer $status $detail"
  case "$status" in
    ok) OK=$((OK+1)) ;;
    n/a) SKIPPED=$((SKIPPED+1)) ;;
    *) DEGRADED=$((DEGRADED+1)); continue ;;
  esac
  [ -n "$script" ] || continue
  if probe "$script" "$arg" "$VAULT_ROOT/$RAW_DIR/__guard_probe__.md"; then
    if probe "$script" "$arg" "$VAULT_ROOT/$WIKI_DIR/__guard_probe__.md"; then
      echo "GUARD $platform L2 degraded wiki/ 쓰기까지 차단합니다 — 오탐 (가드가 과차단)"
      DEGRADED=$((DEGRADED+1)); OK=$((OK-1))
    else
      echo "GUARD $platform L2 ok raw/ 차단 · wiki/ 통과"
    fi
  else
    echo "GUARD $platform L2 degraded raw/ 쓰기를 차단하지 못했습니다 — 보호가 꺼져 있습니다"
    DEGRADED=$((DEGRADED+1)); OK=$((OK-1))
  fi
done <<EOF
$L1
EOF

echo "SUMMARY guards=$GUARDS ok=$OK degraded=$DEGRADED skipped=$SKIPPED"
[ "$DEGRADED" -eq 0 ]
