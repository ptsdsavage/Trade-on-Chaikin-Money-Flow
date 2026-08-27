@echo off
REM Builds standalone Windows executables for cmf_spy.py (signal viewer) and
REM cmf_trader.py (paper trader) using an isolated venv, so PyInstaller
REM doesn't bundle unrelated packages from the system Python. Run this on a
REM Windows machine with Python 3.10+ installed (py launcher or python on
REM PATH). The resulting exes + launcher scripts are packaged into
REM "Trade on Chaikin Money Flow.zip".
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "APP_NAME=Trade on Chaikin Money Flow"

if exist build rmdir /s /q build
if exist dist rmdir /s /q dist
if exist .build-venv-win rmdir /s /q .build-venv-win
if exist "%APP_NAME%" rmdir /s /q "%APP_NAME%"
if exist "%APP_NAME%.zip" del /q "%APP_NAME%.zip"
if exist SPY-CMF-Signal.spec del /q SPY-CMF-Signal.spec
if exist CMF-Trader.spec del /q CMF-Trader.spec

where py >nul 2>nul
if %errorlevel%==0 (
    set "PY=py -3"
) else (
    set "PY=python"
)

%PY% -m venv .build-venv-win || goto :error
call .build-venv-win\Scripts\activate.bat || goto :error
python -m pip install --quiet --upgrade pip || goto :error
python -m pip install --quiet -r requirements.txt || goto :error
python -m PyInstaller --onefile --name SPY-CMF-Signal --console cmf_spy.py || goto :error
python -m PyInstaller --onefile --name CMF-Trader --console cmf_trader.py || goto :error
call .build-venv-win\Scripts\deactivate.bat

rmdir /s /q build
del /q SPY-CMF-Signal.spec CMF-Trader.spec
rmdir /s /q .build-venv-win

mkdir "%APP_NAME%"
copy /y dist\SPY-CMF-Signal.exe "%APP_NAME%\" >nul
copy /y dist\CMF-Trader.exe "%APP_NAME%\" >nul

> "%APP_NAME%\Run SPY Signal.bat" (
    echo @echo off
    echo cd /d "%%~dp0"
    echo SPY-CMF-Signal.exe
    echo pause
)

> "%APP_NAME%\Run CMF Trader.bat" (
    echo @echo off
    echo cd /d "%%~dp0"
    echo CMF-Trader.exe
    echo pause
)

powershell -NoProfile -Command "Compress-Archive -Path '%APP_NAME%' -DestinationPath '%APP_NAME%.zip' -Force" || goto :error
rmdir /s /q "%APP_NAME%"

echo Built: %APP_NAME%.zip (SPY-CMF-Signal.exe + CMF-Trader.exe)
exit /b 0

:error
echo Build failed.
exit /b 1
