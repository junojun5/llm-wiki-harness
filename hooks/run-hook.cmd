:; # ─────────────────────────────────────────────────────────────────
:; # run-hook.cmd — 폴리글랏 런처. Unix=bash, Windows=cmd.exe 양쪽에서 동작.
:; # 용도: Windows 네이티브 에이전트가 .sh 훅을 직접 실행 못 할 때, Git Bash의
:; #       bash로 위임한다. 인자: <hook-script> [platform]. (배포 설계 §11-4·§10)
:; #
:; # ⚠️ Claude Code에서 cmd.exe 분기는 **예외 경로**다 (2026-08-05 공식 문서 확인,
:; #    code.claude.com/docs/en/hooks). 훅 항목의 `shell` 필드가 실행 셸을 정하고
:; #    그 기본값이 "bash"이며, Windows에서 **Git Bash가 없을 때만** "powershell"로
:; #    떨어진다. 즉 Git Bash가 있으면 Claude는 이 파일을 **bash로** 실행해 아래
:; #    Unix 분기를 탄다 — CRLF+' #' 페어가 Windows Claude 경로에서도 필수인 이유다.
:; #    cmd.exe 분기가 실제로 필요한 쪽은 ① Git Bash 없는 Claude(→PowerShell→.cmd)
:; #    ② Codex·Cursor 다. 이 분기를 지울 수 없는 이유이자, 여기가 유일 경로가
:; #    아니라는 사실을 함께 기억해야 하는 이유.
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
rem    (.github/workflows/windows.yml 의 cmd-launcher 잡이 windows-latest에서 실기 검증한다.)
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

rem ── bash 탐색 — Git for Windows 우선, PATH는 마지막 수단 ──
rem ⚠️ `where bash`만 쓰면 안 된다. WSL 기능이 켜진 시스템에는 System32에 레거시 런처
rem    `bash.exe`가 있고 System32는 PATH 앞쪽에 거의 항상 있다. 그걸 집으면 아래에서
rem    넘기는 `%~dp0` 형식의 Windows 경로(`C:\...`)를 WSL 안에서 해석할 수 없어 훅이
rem    조용히 죽는다 — 그래서 Git for Windows의 실제 설치 위치를 먼저 확인한다.
rem    (README·배포 설계의 "Git Bash 또는 WSL bash" 문구는 이 이유로 정정됐다.)
rem ⚠️ %ProgramFiles(x86)% 는 변수명에 괄호가 있어 `if (...)` 괄호 블록 안에서 파싱이
rem    깨진다. 여기서는 goto 분기만 쓰므로 안전하다 (tests/hooks/test-run-hook-cmd.cmd
rem    주석의 같은 함정 참조).
set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if exist "%BASH_EXE%" goto :have_bash
set "BASH_EXE=%ProgramFiles(x86)%\Git\bin\bash.exe"
if exist "%BASH_EXE%" goto :have_bash
set "BASH_EXE=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if exist "%BASH_EXE%" goto :have_bash
set "BASH_EXE=bash"
where bash >nul 2>nul
if errorlevel 1 goto :no_bash

:have_bash
"%BASH_EXE%" "%HOOK_DIR%%SCRIPT%" %ARGS%
exit /b %errorlevel%

:no_bash
rem ── bash 없음 → 훅 역할에 따라 갈린다 ──
rem ⚠️ 전부 `exit /b 1`로 처리하면 안 된다. 비영 exit는 non-blocking error이고
rem    PreToolUse matcher가 Write|Edit|MultiEdit|NotebookEdit|Bash 로 **전역**이므로,
rem    볼트와 무관한 아무 편집에서도 매번 "hook error" 알림이 뜬다.
rem    반대로 `exit /b 2`로 fail-closed 하면 그 전역 matcher가 **모든 편집을 차단**해
rem    도구 자체를 쓸 수 없게 만든다. 그래서 역할로 가른다:
rem      session-start  → stderr + exit 2. SessionStart는 exit 2로 차단되지 않고
rem                       stderr만 사용자에게 보인다 → 세션당 1회 "가드 비활성" 경고로
rem                       정확히 맞는 신호다. session-start 자신이 SKILL.md 부재를
rem                       알리는 관례와 동일하다.
rem      가드 2개       → 무음 exit 0. "판정할 수 없으면 조용히 통과"라는
rem                       wiki-protect-raw.sh 의 resolver 실패 정책과 일관된다
rem                       (세션 시작 시 이미 경고했으므로 중복 노출도 아니다).
rem ⚠️ 메시지는 **ASCII로 쓴다.** 배치 파일의 한글 리터럴은 cmd.exe 활성 코드페이지에
rem    따라 mojibake가 된다(test-run-hook-cmd.cmd 가 비ASCII 인자를 WARN으로만 두는
rem    것과 같은 이유). 이 문장은 사용자가 조치를 취해야 하는 유일한 출력이므로
rem    깨지면 안 된다.
if /i "%SCRIPT%"=="session-start" goto :no_bash_session
exit /b 0
:no_bash_session
echo [llm-wiki] bash not found - wiki guard hooks are DISABLED. Install Git for Windows, or add bash to PATH. 1>&2
exit /b 2
