@echo off
rem cmd 분기는 스크립트명을 인자로 다시 실으면 안 된다. shift는 %*를 바꾸지 않는다.
setlocal enabledelayedexpansion

set "HERE=%~dp0"
set "HOOKS=%HERE%..\..\hooks"
set "LAUNCHER=%HOOKS%\run-hook.cmd"
set "PROBE=%HOOKS%\_argprobe.sh"
set "OUTFILE=%TEMP%\lwh-argprobe.out"
set /a PASS=0
set /a FAIL=0
set /a WARN=0

where bash >nul 2>nul
if errorlevel 1 (
  echo FAIL: bash를 PATH에서 찾을 수 없습니다 ^(Windows는 Git Bash 또는 WSL bash가 필요^)
  exit /b 1
)

rem probe는 hooks/에 둔다. %%s는 리터럴 %s.
> "%PROBE%" echo printf '[%%s]' "$@"

echo test: run-hook.cmd 인자 전달 (cmd.exe 분기)

rem 인자 0개의 기대값은 []다. 스크립트명이 실리면 [_argprobe.sh]가 된다.
call "%LAUNCHER%" _argprobe.sh > "%OUTFILE%" 2>nul
call :check "인자 0개 — 스크립트명이 인자로 새지 않는다" "[]"

rem desc에 < > ( ) 를 넣지 않는다. 큰따옴표 안에서도 리다이렉션으로 파싱된다.
call "%LAUNCHER%" _argprobe.sh claude > "%OUTFILE%" 2>nul
call :check "인자 1개 — 실사용 계약인 hook + platform 형태" "[claude]"

call "%LAUNCHER%" _argprobe.sh codex extra > "%OUTFILE%" 2>nul
call :check "인자 2개 — 순서 보존" "[codex][extra]"

call "%LAUNCHER%" _argprobe.sh a b c > "%OUTFILE%" 2>nul
call :check "인자 3개 — 누적 루프가 전부 넘긴다" "[a][b][c]"

call "%LAUNCHER%" _argprobe.sh "x y" > "%OUTFILE%" 2>nul
call :check "공백 포함 인자가 1개로 유지된다" "[x y]"

call "%LAUNCHER%" _argprobe.sh "x y" z > "%OUTFILE%" 2>nul
call :check "공백 인자 + 추가 인자" "[x y][z]"

rem 비ASCII 인자는 경고만 한다. 실사용 인자는 ASCII다.
call "%LAUNCHER%" _argprobe.sh 한글 > "%OUTFILE%" 2>nul
call :observe "비ASCII 인자 (코드페이지 의존)" "[한글]"

del /q "%PROBE%" >nul 2>nul
del /q "%OUTFILE%" >nul 2>nul

echo.
echo PASS=%PASS% FAIL=%FAIL% WARN=%WARN%
if %FAIL% GTR 0 exit /b 1
exit /b 0

:read_got
set "GOT="
for /f "usebackq delims=" %%L in ("%OUTFILE%") do set "GOT=%%L"
goto :eof

rem if () else () 를 쓰지 않는다. desc의 닫는 괄호가 블록을 조기 종료한다.
:check
call :read_got
if not "!GOT!"=="%~2" goto :check_fail
set /a PASS+=1
echo   ok: %~1
goto :eof
:check_fail
set /a FAIL+=1
echo   FAIL: %~1  -- expected [%~2] got [!GOT!]
goto :eof

:observe
call :read_got
if not "!GOT!"=="%~2" goto :observe_warn
set /a PASS+=1
echo   ok: %~1
goto :eof
:observe_warn
set /a WARN+=1
echo   WARN: %~1  -- expected [%~2] got [!GOT!]
goto :eof
