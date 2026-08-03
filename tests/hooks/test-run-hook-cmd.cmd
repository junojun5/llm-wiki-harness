@echo off
rem 단위 테스트: hooks/run-hook.cmd 의 **cmd.exe 분기** — 인자 전달 계약.
rem
rem 왜 필요한가: cmd.exe의 `shift`는 %* 에 영향이 없다(항상 원본 전체 인자로 확장된다).
rem `shift` 후 `bash %SCRIPT% %*` 를 쓰면 스크립트명이 첫 인자로 다시 실려
rem `session-start session-start claude` 가 되고 PLATFORM="session-start" →
rem unknown platform exit 2 로 **Windows에서 세 훅이 전부 죽는다.**
rem Phase 2 T5에서 %2부터 누적하는 루프로 고쳤으나, macOS/Linux에서는 cmd.exe를 실행할 수
rem 없어 **정적 검토 + 주석으로만** 확인돼 있었다 — 이 테스트가 그 갭을 닫는다
rem (.github/workflows/windows.yml 의 cmd-launcher 잡이 실행한다).
rem
rem Unix 분기(`:;` 프리픽스)의 회귀는 tests/hooks/test-session-start.sh 가 담당한다.
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

rem 인자를 [x][y] 로 그대로 되울리는 probe 훅. run-hook.cmd 는 %~dp0 기준으로 스크립트를
rem 찾으므로 hooks/ 안에 둔다 — 실사용과 동일한 경로 해석을 지나게 하려는 것이다.
rem (배치 파일 안에서 %%s 는 리터럴 %s 로 쓰인다.)
> "%PROBE%" echo printf '[%%s]' "$@"

echo test: run-hook.cmd 인자 전달 (cmd.exe 분기)

call "%LAUNCHER%" _argprobe.sh > "%OUTFILE%" 2>nul
call :check "인자 0개 — 스크립트명이 인자로 새지 않는다" ""

call "%LAUNCHER%" _argprobe.sh claude > "%OUTFILE%" 2>nul
call :check "인자 1개 (실사용 계약: <hook> <platform>)" "[claude]"

call "%LAUNCHER%" _argprobe.sh codex extra > "%OUTFILE%" 2>nul
call :check "인자 2개 — 순서 보존" "[codex][extra]"

call "%LAUNCHER%" _argprobe.sh a b c > "%OUTFILE%" 2>nul
call :check "인자 3개 — 누적 루프가 전부 넘긴다" "[a][b][c]"

call "%LAUNCHER%" _argprobe.sh "x y" > "%OUTFILE%" 2>nul
call :check "공백 포함 인자가 1개로 유지된다" "[x y]"

call "%LAUNCHER%" _argprobe.sh "x y" z > "%OUTFILE%" 2>nul
call :check "공백 인자 + 추가 인자" "[x y][z]"

rem 비ASCII 인자는 **관측만** 한다(WARN). cmd.exe의 활성 코드페이지·배치 파일 인코딩에
rem 따라 리터럴이 오독될 수 있고, 실사용 계약의 인자는 `session-start`·`claude|codex|cursor`
rem 로 전부 ASCII다. 여기서 required 잡을 빨간불로 만들면 신호가 죽는다 —
rem 실패가 반복되면 그때 별도 항목으로 다룬다.
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

:check
call :read_got
if "!GOT!"=="%~2" (
  set /a PASS+=1
  echo   ok: %~1
) else (
  set /a FAIL+=1
  echo   FAIL: %~1  -- expected [%~2] got [!GOT!]
)
goto :eof

:observe
call :read_got
if "!GOT!"=="%~2" (
  set /a PASS+=1
  echo   ok: %~1
) else (
  set /a WARN+=1
  echo   WARN: %~1  -- expected [%~2] got [!GOT!]
)
goto :eof
