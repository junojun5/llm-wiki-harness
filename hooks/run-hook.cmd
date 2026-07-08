:; # ─────────────────────────────────────────────────────────────────
:; # run-hook.cmd — 폴리글랏 런처. Unix=bash, Windows=cmd.exe 양쪽에서 동작.
:; # 용도: Windows 네이티브 에이전트가 .sh 훅을 직접 실행 못 할 때, Git Bash/WSL의
:; #       bash로 위임한다. 인자: <hook-script> [platform]. (배포 설계 §11-4·§10 — 향후
:; #       .ps1 패리티 전까지 Windows는 Git Bash/WSL bash가 PATH에 있어야 함.)
:; # Unix 진입: ':'는 sh의 no-op 명령이라 ';' 뒤 명령이 그대로 실행된다
:; #       (cmd.exe 라벨과 달리 건너뛰지 않음). shebang 없이 직접 실행해도
:; #       동작하는 건, execve가 ENOEXEC를 반환하면 셸이 'sh <file>'로
:; #       재실행하는 POSIX 폴백 덕분.
:; HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
:; SCRIPT="$1"; shift
:; exec bash "$HOOK_DIR/$SCRIPT" "$@"
@echo off
rem ── Windows 진입점 ──
setlocal
set "HOOK_DIR=%~dp0"
set "SCRIPT=%~1"
shift
where bash >nul 2>nul
if errorlevel 1 (
  echo run-hook.cmd: bash를 찾을 수 없습니다. Git Bash 또는 WSL bash를 PATH에 추가하세요. 1>&2
  exit /b 1
)
bash "%HOOK_DIR%%SCRIPT%" %*
exit /b %errorlevel%
