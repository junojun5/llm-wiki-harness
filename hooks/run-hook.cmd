:; # ─────────────────────────────────────────────────────────────────
:; # run-hook.cmd — 폴리글랏 런처. Unix=bash, Windows=cmd.exe 양쪽에서 동작.
:; # 용도: Windows 네이티브 에이전트가 .sh 훅을 직접 실행 못 할 때, Git Bash/WSL의
:; #       bash로 위임한다. 인자: <hook-script> [platform]. (배포 설계 §11-4·§10 — 향후
:; #       .ps1 패리티 전까지 Windows는 Git Bash/WSL bash가 PATH에 있어야 함.)
:; # Unix 진입: ':'는 sh의 no-op 명령이라 ';' 뒤 명령이 그대로 실행된다
:; #       (cmd.exe 라벨과 달리 건너뛰지 않음). shebang 없이 직접 실행해도
:; #       동작하는 건, execve가 ENOEXEC를 반환하면 셸이 'sh <file>'로
:; #       재실행하는 POSIX 폴백 덕분.
:; # ⚠️ 이 파일은 **CRLF**로 배포된다(.gitattributes). cmd.exe는 LF-only 배치의 줄
:; #    경계를 잡지 못해 파일을 중간부터 오해석한다 — 2026-08-04 CI 실측에서 주석 조각과
:; #    코드 조각("라벨과", "SCRIPT=_dbg.sh", "ect_args")이 각각 명령으로 실행됐다.
:; #    그래서 아래 실행 줄들은 끝에 ' #'을 달아 **CR을 주석으로 흡수**시킨다. 없으면
:; #    bash가 'shift\r' 같은 토큰을 실행하려다 죽는다. 새 줄을 추가할 때도 ' #'을 붙인다.
:; HOOK_DIR="$(cd "$(dirname "$0")" && pwd)" #
:; SCRIPT="$1"; shift #
:; exec bash "$HOOK_DIR/$SCRIPT" "$@" #
@echo off
rem ── Windows 진입점 ──
rem ⚠️ cmd.exe의 `shift`는 %* 에 영향이 없다 — %* 는 항상 "원본 전체 인자"로 확장된다.
rem    따라서 `shift` 후 `bash %SCRIPT% %*` 를 쓰면 스크립트명이 첫 인자로 다시 실려
rem    `session-start session-start claude` 가 되고 PLATFORM="session-start" →
rem    unknown platform exit 2 로 세 훅이 전부 죽는다. %2 부터 직접 누적한다.
rem    (.github/workflows/windows.yml 의 cmd-launcher 잡이 windows-latest에서 실기 검증한다.
rem     Windows는 Git Bash/WSL bash가 PATH에 있어야 한다.)
setlocal
set "HOOK_DIR=%~dp0"
set "SCRIPT=%~1"
set "ARGS="
:collect_args
shift
if "%~1"=="" goto :args_collected
set "ARGS=%ARGS% "%~1""
goto :collect_args
:args_collected
where bash >nul 2>nul
if errorlevel 1 (
  echo run-hook.cmd: bash를 찾을 수 없습니다. Git Bash 또는 WSL bash를 PATH에 추가하세요. 1>&2
  exit /b 1
)
bash "%HOOK_DIR%%SCRIPT%" %ARGS%
exit /b %errorlevel%
