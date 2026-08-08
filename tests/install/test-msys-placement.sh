#!/usr/bin/env bash
# 회귀 테스트: MSYS(Git Bash) `ln -s` 시맨틱에서의 install.sh 멱등성.
#
# ── 왜 있는가 ──────────────────────────────────────────────────────────────────
# Git for Windows의 `ln -s`는 **진짜 symlink를 만들지 않고 복사한다**(진짜 symlink는
# `MSYS=winsymlinks:nativestrict` + 개발자 모드/관리자 권한이 필요하다). 그런데 install.sh와
# hooks/session-start는 **"이 파일 우리가 놓았나?"를 `[ -L ]`로 판정**했다 — 복사본은
# symlink가 아니므로 판정이 **항상 "사용자 파일"로 떨어진다.**
#
# Windows CI(2026-08-04 run 30903396251 이후)와 이 스위트의 셰임이 같은 결함을 보인다:
#   1회차  rc=0  사이드카 0건            정상
#   2회차  rc=0  사이드카 **3건**        자기 복사본을 사용자 파일로 오판 → 병합할 게 없는데
#                                        AGENTS.md 3자리 전부 "수동 머지하세요"
#   3회차  rc=1  `ln: …/skills/ingest-url/ingest-url: cannot overwrite directory`
#                dest가 실존 디렉터리라 `ln`이 그 **안쪽**에 만들려 하고, `-f`는 디렉터리를
#                지우지 못한다. `set -euo pipefail` 아래서 **install.sh가 즉사**하고
#                그 뒤의 `[3]` 구간 — **훅 등록 전체**가 한 줄도 실행되지 않는다.
# 전부 fail-open이고 증상이 조용하다: 사용자는 `ln:` 한 줄만 보고 "왜 가드가 안 도는지"를
# 연결하지 못한다.
#
# ── 왜 셰임인가 ────────────────────────────────────────────────────────────────
# windows-latest 러너에는 Git Bash가 항상 있어 이 상태를 CI에서 만들 수 없고, macOS/Linux의
# `ln -s`는 진짜 symlink를 만든다. 그래서 MSYS 시맨틱을 **PATH 셰임으로 재현**한다 — 결함이
# 플랫폼이 아니라 **소유권 판정 로직**에 있으므로 로직은 어디서든 같게 밟힌다.
# (Windows에서 이 스위트를 돌리면 셰임이 이미-복사인 `ln`을 한 번 더 감싸는 것뿐이라 무해하다.)
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  ✓ $1"; }
no() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }

SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
SHIM="$SB/shim"; mkdir -p "$SHIM"

# MSYS `ln -s` 시맨틱 셰임. 관측된 진행을 그대로 재현한다:
#   dst 없음            → 복사
#   dst가 실존 디렉터리  → ln의 통상 규칙대로 dst/basename(src) 안쪽을 노린다
#   그 경로가 디렉터리    → `-f`가 못 지워 실패 (죽는 지점)
cat >"$SHIM/ln" <<'SHIM_EOF'
#!/usr/bin/env bash
set -u
SRC=""; DST=""; FORCE=0
for a in "$@"; do
  case "$a" in
    -*) case "$a" in *f*) FORCE=1 ;; esac ;;
    *)  if [ -z "$SRC" ]; then SRC="$a"; else DST="$a"; fi ;;
  esac
done
[ -n "$SRC" ] && [ -n "$DST" ] || { echo "ln-shim: bad args: $*" >&2; exit 1; }
if [ -d "$DST" ] && [ ! -L "$DST" ]; then DST="$DST/$(basename "$SRC")"; fi
if [ -e "$DST" ] || [ -L "$DST" ]; then
  if [ -d "$DST" ] && [ ! -L "$DST" ]; then
    echo "ln: $DST: cannot overwrite directory" >&2; exit 1
  fi
  [ "$FORCE" = 1 ] && rm -f "$DST"
fi
cp -R "$SRC" "$DST"
SHIM_EOF
chmod +x "$SHIM/ln"

# ⚠️ Windows에서 install 1회가 ~20초다(셰임이 symlink를 전부 복사로 떨어뜨려 스킬 트리를
# 통째로 복사한다). 전체 install을 남발하면 스위트가 CI 상한을 넘는다 — 2026-08-08에 실제로
# rc=124로 잘렸다(120.09초). 그래서 `--fallback`은 그게 **꼭 필요한 케이스에서만** 붙인다.
run_install() { # run_install <home> <vault> <outfile> [--fallback]
  HOME="$1" PATH="$SHIM:$PATH" bash "$REPO/install.sh" ${4:+--fallback} --vault "$2" >"$3" 2>&1
}
sidecars() { find "$@" -name '*.llm-wiki.*' 2>/dev/null | wc -l | tr -d ' '; }

# ─────────────────────────────────────────────────────────────────────────────
echo "[1] MSYS 시맨틱에서 install.sh 3회 연속 실행"
H="$SB/h1"; V="$SB/v1"; mkdir -p "$H/.claude" "$H/.cursor" "$H/.gemini" "$V"
rc1=0; rc2=0; rc3=0
run_install "$H" "$V" "$SB/o1" --fallback || rc1=$?
run_install "$H" "$V" "$SB/o2" --fallback || rc2=$?
run_install "$H" "$V" "$SB/o3" --fallback || rc3=$?

[ "$rc1" = 0 ] && ok "1회차 rc=0" || no "1회차 rc=$rc1"
[ "$rc2" = 0 ] && ok "2회차 rc=0" || no "2회차 rc=$rc2"
# 핵심 회귀: 3회차가 `ln: cannot overwrite directory`로 즉사했다.
if [ "$rc3" = 0 ]; then ok "3회차 rc=0"
else no "3회차 rc=$rc3 — $(grep -m1 '^ln:' "$SB/o3" || echo '(ln 에러 없음)')"; fi

# 죽으면 `[3]` 구간(훅 등록 6곳)이 돌지 않는다. rc만으로는 1회차의 산물과 구별되지 않으므로
# **그 실행이 끝까지 갔는지**를 종료 마커로 확인한다.
grep -q '── 설치 요약 ──' "$SB/o3" && ok "3회차가 끝까지 실행됨(훅 등록 구간 도달)" \
  || no "3회차가 중간에서 죽었다 — [3] 훅 등록이 실행되지 않았다"

# ─────────────────────────────────────────────────────────────────────────────
echo "[2] 재실행이 사이드카를 만들지 않는다 (자기 산물을 사용자 파일로 오판 금지)"
n="$(sidecars "$H" "$V")"
[ "$n" = 0 ] && ok "사이드카 0건" \
  || no "사이드카 ${n}건 — 병합할 게 없는데 수동 머지를 요구한다: $(find "$H" "$V" -name '*.llm-wiki.*' 2>/dev/null | head -1 | sed "s|$SB/||")"

# ─────────────────────────────────────────────────────────────────────────────
# 오판을 막는 것이 **비파괴 정책을 끄는 것과 같지 않다.** 진짜 사용자 파일은 여전히 보존해야
# 한다 — 이 단언이 없으면 "사이드카 0건"을 정책을 없애서 통과시킬 수 있다.
echo "[3] 진짜 사용자 파일은 보존 + 사이드카 (비파괴 정책 회귀 방지)"
H2="$SB/h2"; V2="$SB/v2"; mkdir -p "$H2/.claude" "$H2/.cursor" "$H2/.gemini" "$V2"
printf '# 내가 직접 쓴 규칙\n사용자 소유 파일이다.\n' >"$V2/AGENTS.md"
run_install "$H2" "$V2" "$SB/o4" || true
grep -q '내가 직접 쓴 규칙' "$V2/AGENTS.md" && ok "사용자 AGENTS.md 원본 보존" || no "사용자 파일이 덮어써졌다"
[ -f "$V2/AGENTS.llm-wiki.md" ] && ok "하네스 사본을 사이드카로 배치" || no "사용자 파일 충돌인데 사이드카가 없다"

# ─────────────────────────────────────────────────────────────────────────────
# 기존 사용자(macOS/Linux)는 **진짜 symlink + 스탬프 없음** 상태다. 소유권 판정을 스탬프로
# 바꿀 때 그 상태를 "사용자 파일"로 읽으면 기존 설치 전부가 다음 실행에서 사이드카를 뒤집어쓴다.
echo "[4] 스탬프 이전 설치(진짜 symlink, 원장 없음)를 사이드카 없이 흡수"
H3="$SB/h3"; V3="$SB/v3"; mkdir -p "$H3/.claude" "$H3/.cursor" "$H3/.gemini" "$V3"
/bin/ln -sfn "$REPO/AGENTS.md" "$V3/AGENTS.md"   # 셰임을 우회해 진짜 symlink를 만든다
run_install "$H3" "$V3" "$SB/o5" || true
n3="$(sidecars "$H3" "$V3")"
[ "$n3" = 0 ] && ok "기존 symlink 설치 흡수 — 사이드카 0건" \
  || no "기존 설치가 사이드카 ${n3}건을 얻었다 (마이그레이션 파손)"

# ─────────────────────────────────────────────────────────────────────────────
# `link()`은 무조건 배치 경로다(스킬·훅 트리 15곳). MSYS 대응으로 "dest를 먼저 비운다"를
# 넣으면 **그 자리에 있던 사용자 디렉터리를 지운다.** 지금도 무해하지 않다: `ln -sfn`은 dest가
# 실존 디렉터리면 그 **안쪽**에 링크를 만들어 사용자 트리를 오염시킨다.
# 소유권을 확인하지 않는 배치는 어느 쪽으로도 안전하지 않다.
echo "[5] 사용자 소유 디렉터리를 지우지도 오염시키지도 않는다"
H4="$SB/h4"; V4="$SB/v4"; mkdir -p "$H4/.claude/skills/wiki-setup" "$H4/.cursor" "$H4/.gemini" "$V4"
printf '내 스킬이다.\n' >"$H4/.claude/skills/wiki-setup/mine.md"
run_install "$H4" "$V4" "$SB/o6" --fallback || true
[ -f "$H4/.claude/skills/wiki-setup/mine.md" ] && ok "사용자 파일 생존" || no "사용자 디렉터리가 삭제됐다"
[ ! -e "$H4/.claude/skills/wiki-setup/wiki-setup" ] && ok "사용자 트리에 중첩 링크 없음" \
  || no "사용자 디렉터리 안쪽에 중첩 배치됐다 (ln이 dest 내부를 노렸다)"

# ─────────────────────────────────────────────────────────────────────────────
# install.sh만 고치면 절반이다. **마켓플레이스 설치는 install.sh를 거치지 않는다** —
# `hooks/session-start`의 부트스트랩 ①이 같은 판정을 하고, 거기도 `[ -L ]`을 썼다.
# 결과: Windows에서 런타임 홈이 **영구히 stale해진다.** 플러그인을 업데이트해도 복사본은
# `-L`이 false이므로 `[ -e "$DST" ] && continue`에 걸려 재지정이 일어나지 않고, 스킬·가드가
# 계속 옛 스크립트를 호출한다(2026-08-01에 이미 한 번 겪은 결함의 Windows 재발).
echo "[6] MSYS에서 session-start 부트스트랩 — 배치 + 형제 버전 재지정 + 클론 보존"
HOOK="$REPO/hooks/session-start"
mkdir -p "$SB/plugins/cache/llm-wiki-harness/llm-wiki-harness"
MP="$(cd "$SB/plugins/cache/llm-wiki-harness/llm-wiki-harness" && pwd -P)"
for v in 0.1.0 0.2.0; do
  mkdir -p "$MP/$v/hooks" "$MP/$v/scripts" "$MP/$v/skills/using-llm-wiki"
  cp "$HOOK" "$MP/$v/hooks/session-start"
  cp "$REPO/skills/using-llm-wiki/SKILL.md" "$MP/$v/skills/using-llm-wiki/SKILL.md"
  for s in resolve-vault.sh validate-frontmatter.sh build-link-graph.sh; do
    printf '#!/usr/bin/env bash\necho %s\n' "$v" >"$MP/$v/scripts/$s"
  done
done
boot() { # boot <home> <version>
  (cd "$SB" && HOME="$1" PATH="$SHIM:$PATH" bash "$MP/$2/hooks/session-start" claude </dev/null >/dev/null 2>&1) || true
}

# ① 빈 상태에서 배치되는가 (symlink든 복사든 — 쓸 수 있어야 한다)
HB="$SB/hb"; mkdir -p "$HB"
boot "$HB" 0.1.0
[ -e "$HB/.llm-wiki/scripts/resolve-vault.sh" ] && ok "부트스트랩 배치됨" || no "부트스트랩이 아무것도 놓지 않았다"
[ "$(bash "$HB/.llm-wiki/scripts/build-link-graph.sh" 2>/dev/null)" = "0.1.0" ] \
  && ok "배치된 스크립트가 실행된다(0.1.0)" || no "배치된 스크립트가 실행되지 않는다"

# ② 형제 버전으로 업데이트하면 재지정되는가 — Windows에서 영구 stale이던 지점
boot "$HB" 0.2.0
got="$(bash "$HB/.llm-wiki/scripts/build-link-graph.sh" 2>/dev/null || echo '(실행 실패)')"
[ "$got" = "0.2.0" ] && ok "형제 버전 재지정 (0.1.0 → 0.2.0)" \
  || no "재지정 안 됨 — 여전히 [$got] 실행 (런타임 홈이 영구 stale)"

# ③ 사용자 클론 배치는 보존되는가 (install.sh 비파괴 정책이 MSYS에서도 성립해야 한다)
HC="$SB/hc"; CLONE="$SB/my-clone/scripts"; mkdir -p "$HC/.llm-wiki/scripts" "$CLONE"
for s in resolve-vault.sh validate-frontmatter.sh build-link-graph.sh; do
  printf '#!/usr/bin/env bash\necho clone\n' >"$CLONE/$s"
  cp "$CLONE/$s" "$HC/.llm-wiki/scripts/$s"           # MSYS 설치 = 복사본
  printf 'copy\t%s\t%s\n' "$HC/.llm-wiki/scripts/$s" "$CLONE/$s" >>"$HC/.llm-wiki/.placements"
done
boot "$HC" 0.2.0
[ "$(bash "$HC/.llm-wiki/scripts/build-link-graph.sh" 2>/dev/null)" = "clone" ] \
  && ok "사용자 클론 배치 보존" || no "클론 배치가 플러그인 캐시로 덮어써졌다"

# ④ 하네스 산물이 아닌 실제 파일은 손대지 않는다 (원장에 없는 것 = 사용자 소유)
HU="$SB/hu"; mkdir -p "$HU/.llm-wiki/scripts"
printf '#!/usr/bin/env bash\necho mine\n' >"$HU/.llm-wiki/scripts/build-link-graph.sh"
boot "$HU" 0.2.0
[ "$(bash "$HU/.llm-wiki/scripts/build-link-graph.sh" 2>/dev/null)" = "mine" ] \
  && ok "사용자 파일 보존" || no "사용자 파일이 덮어써졌다"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
