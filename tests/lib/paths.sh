#!/usr/bin/env bash
# tests/lib/paths.sh — 테스트 공용 경로 헬퍼. `. "$REPO_ROOT/tests/lib/paths.sh"` 로 로드한다.
#
# ── 왜 있는가 (2026-08-04 Windows CI 실측) ──────────────────────────────────────
# MSYS(Git Bash)에서 **bash가 쓰는 경로**(`/tmp/tmp.XXXX`)와 **native Windows python3가
# 이해하는 경로**(`C:/Users/.../Temp/tmp.XXXX`)는 다르다. MSYS는 native 바이너리를 부를 때
# **argv에 한해** 경로를 자동 변환해 주는데, 이 하네스는 경로를 **파일 내용**(`.wiki-config.json`의
# `vault.path`)과 **stdin 페이로드**(훅의 `file_path`)로도 넘긴다 — 거기는 변환되지 않는다.
#
# 그래서 Windows CI에서 이런 모양이 났다: config 파일 자체는 열리는데(argv라 변환됨)
# 그 안의 `vault.path`가 `/tmp/...`인 채로 `os.path.isdir()`에 걸려 `ERR PATH` →
# **`E_INVALID_CONFIG` 오진**. 뒤이어 `E_VERSION`·`E_NOT_A_VAULT` 케이스도 경로 검증이
# 앞에 있어 전부 4로 뭉개졌고, 훅 스위트는 리졸버가 죽어 "비볼트 → 통과"로 흘러
# **가드 판정 로직을 한 번도 밟지 못했다**.
#
# **리졸버·훅의 결함이 아니다.** 실사용에서 Windows 사용자의 `vault.path`는 네이티브 경로이고
# 정상 동작한다. 깨진 것은 테스트 픽스처의 플랫폼 가정이다.
#
# ── 규칙 ────────────────────────────────────────────────────────────────────────
#   bash가 직접 다루는 것(mkdir·cd·리다이렉트·`[ -f ]`)  → 그대로 POSIX 경로
#   python3로 **값으로서** 건너가는 것                    → `native_path` 를 통과시킨다
#     · `.wiki-config.json` 의 `vault.path`
#     · 훅 stdin 페이로드의 `file_path` / `command`
#     · 리졸버 출력(`VAULT_PATH=`)과 비교하는 기대값
#
# `cygpath -m`(mixed)을 쓴다. `-w`는 백슬래시(`C:\...`)라 JSON에 넣으려면 이스케이프가 필요하고,
# 한 번 빠뜨리면 조용히 깨진다. `-m`은 `C:/...` 형태로 슬래시를 유지해 JSON에 그대로 넣을 수 있고
# Windows python3도 정상 해석한다.
#
# macOS/Linux에는 `cygpath`가 없으므로 **항등 함수**가 된다 — 기존 동작은 그대로다.

native_path() { # native_path <posix-path> → 플랫폼 네이티브 경로
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    printf '%s\n' "$1"
  fi
}
