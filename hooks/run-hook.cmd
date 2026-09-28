:; # 폴리글랏. Unix는 ':' no-op 뒤 bash, Windows는 @echo off. 인자: <hook-script> [platform].
:; # CRLF로 배포한다. 실행 줄 끝 ' #'이 CR을 삼킨다. 하나만 있으면 한쪽 플랫폼이 죽는다.
:; HOOK_DIR="$(cd "$(dirname "$0")" && pwd)" #
:; SCRIPT="$1"; shift #
:; exec bash "$HOOK_DIR/$SCRIPT" "$@" #
@echo off
rem shift는 %*를 바꾸지 않는다. %2부터 직접 모은다.
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

rem Git bash.exe를 where보다 먼저 본다. System32 WSL bash는 C:\ 경로를 해석하지 못한다.
rem %ProgramFiles(x86)%는 if () 블록에서 깨진다. goto만 쓴다.
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
rem bash 없음: session-start는 exit 2, 가드는 무음 exit 0. 전부 2면 편집이 막히고 1이면 알림이 도배된다.
rem 경고는 ASCII다. 배치 파일 한글은 코드페이지에 따라 깨진다.
if /i "%SCRIPT%"=="session-start" goto :no_bash_session
exit /b 0
:no_bash_session
echo [llm-wiki] bash not found - wiki guard hooks are DISABLED. Install Git for Windows, or add bash to PATH. 1>&2
exit /b 2
