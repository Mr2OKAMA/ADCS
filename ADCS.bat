@echo off
setlocal EnableDelayedExpansion

:: ==============================
:: 実行中タイトル表示
:: ==============================
title 【実行中】SDカード自動識別システム

:: 日本語環境
chcp 932 > nul

:: ==============================
:: デバッグモード（1=ON, 0=OFF）
:: ==============================
set "DEBUG_MODE=0"

:: ==============================
:: ログ
:: ==============================
set "LOGDIR=%~dp0logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd"') do set "LOGDATE=%%i"
set "LOGFILE=%LOGDIR%\ADCS_%LOGDATE%.log"

call :log ===========================================
call :log SDカード自動識別システム（共通版） 起動

:: ==============================
:: 現在年月（YYYYMM）環境非依存
:: ==============================
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMM"') do set "YYYYMM=%%i"
if not defined YYYYMM (
    call :log [ERROR] YYYYMM の取得に失敗しました。
    echo [ERROR] YYYYMM の取得に失敗しました。
    pause
    exit /b 1
)

:: ==============================
:: OneDrive（SharePoint）ルート自動検出
:: ==============================
set "BASE_ONEDRIVE="
if defined OneDriveCommercial set "BASE_ONEDRIVE=%OneDriveCommercial%"
if not defined BASE_ONEDRIVE if defined OneDrive set "BASE_ONEDRIVE=%OneDrive%"

if not defined BASE_ONEDRIVE (
    call :log [ERROR] OneDrive の業務用パスを取得できませんでした。
    echo [ERROR] OneDrive のパスが取得できません。
    echo OneDrive にサインイン後、再実行してください。
    pause
    exit /b 1
)

:: ==============================
:: SharePoint 保存先ベース
:: ==============================
set "SP_DOC_ROOT=%BASE_ONEDRIVE%\SAM_中部チーム - ドキュメント\B01_木曽川右岸管理事務所\5215木曽川右岸【契約業務】\104.運転・運用記録\02_点検、記録"
set "BASE_YOKOGAWA=%SP_DOC_ROOT%\03_検針\01_横河"
set "BASE_MSYSTEM=%SP_DOC_ROOT%\03_検針\02_Mシステム"
set "BASE_FUJI=%SP_DOC_ROOT%\03_検針\03_フジ"

call :log SharePoint：%BASE_ONEDRIVE%

echo ===========================================
echo   SDカード自動識別システム（共通版）
echo ===========================================
echo 状態：実行中
echo SharePoint：%BASE_ONEDRIVE%
echo Iドライブ：id_00.txt がある場合のみコピー
echo 対象フォルダ：DATA0 / 71VR / S000000
echo ログ：%LOGFILE%
echo ※ 終了：Ctrl + C
echo ===========================================
echo.

:loop
for %%D in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
if exist "%%D:\" (

    call :log [%%D: 検出] 判定中...

    set "FOLDER_NAME="
    set "SAVE_BASE="
    set "SUB_PATH="
    set "SYSTEM_DIR="
    set "TARGET_EXT="
    set "SPECIAL_ID=0"

    :: ========= Mシステム =========
    if exist "%%D:\id_21.txt" (
        set "FOLDER_NAME=01_兼山ポンプ場"
        set "SAVE_BASE=%BASE_MSYSTEM%\%YYYYMM%"
        set "SUB_PATH=\01_初期データ"
        set "SYSTEM_DIR=02_Mシステム"
        set "TARGET_EXT=.71VR"
        set "SPECIAL_ID=1"
    )
    if exist "%%D:\id_22.txt" (
        set "FOLDER_NAME=02_川島ポンプ場"
        set "SAVE_BASE=%BASE_MSYSTEM%\%YYYYMM%"
        set "SUB_PATH=\01_初期データ"
        set "SYSTEM_DIR=02_Mシステム"
        set "TARGET_EXT=.71VR"
        set "SPECIAL_ID=1"
    )

    :: ========= フジ =========
    if "!SPECIAL_ID!"=="0" if exist "%%D:\id_31.txt" (
        set "FOLDER_NAME=01_岐南ポンプ場"
        set "SAVE_BASE=%BASE_FUJI%\%YYYYMM%"
        set "SYSTEM_DIR=03_フジ"
        set "TARGET_EXT=.FDT"
        set "SPECIAL_ID=1"
    )

    :: ========= 横河 =========
    if "!SPECIAL_ID!"=="0" (
        if exist "%%D:\id_01.txt" set "FOLDER_NAME=01_下羽栗"
        if exist "%%D:\id_02.txt" set "FOLDER_NAME=02_芥見"
        if exist "%%D:\id_03.txt" set "FOLDER_NAME=03_岐南西"
        if exist "%%D:\id_04.txt" set "FOLDER_NAME=04_川島第二"
        if exist "%%D:\id_05.txt" set "FOLDER_NAME=05_長森ポンプ場"
        if exist "%%D:\id_06.txt" set "FOLDER_NAME=06_米野"
        if exist "%%D:\id_07.txt" set "FOLDER_NAME=07_東部第一"
        if exist "%%D:\id_08.txt" set "FOLDER_NAME=08_東部第二"
        if exist "%%D:\id_09.txt" set "FOLDER_NAME=09_梅松"
        if exist "%%D:\id_11.txt" set "FOLDER_NAME=11_深田、酒倉"
        if exist "%%D:\id_12.txt" set "FOLDER_NAME=12_川辺"
        if exist "%%D:\id_13.txt" set "FOLDER_NAME=13_中恵土"
        if exist "%%D:\id_14.txt" set "FOLDER_NAME=14_八百津"
        if exist "%%D:\id_15.txt" set "FOLDER_NAME=15_緑苑"
        if exist "%%D:\id_16.txt" set "FOLDER_NAME=16_和知"

        if "!FOLDER_NAME!"=="" set "FOLDER_NAME=未識別カード"
        set "SAVE_BASE=%BASE_YOKOGAWA%\%YYYYMM%"
        set "SYSTEM_DIR=01_横河"
        set "TARGET_EXT=.GDS"
    )

    :: ========= コピー元フォルダ自動判定 =========
    set "SRC_DIR="
    if exist "%%D:\DATA0" (
        set "SRC_DIR=%%D:\DATA0"
    ) else if exist "%%D:\71VR" (
        set "SRC_DIR=%%D:\71VR"
    ) else if exist "%%D:\S000000" (
        set "SRC_DIR=%%D:\S000000"
    )

    if "!SRC_DIR!"=="" (
        call :log [%%D:] 対象フォルダなし（DATA0/71VR/S000000）
        goto wait_eject
    )

    :: ========= 対象拡張子（.DAD含む） =========
    set "FILE_MASKS=*%TARGET_EXT% *.DAD"

    :: ========= SharePoint（COPY） =========
    set "DEST_SP=!SAVE_BASE!\!FOLDER_NAME!!SUB_PATH!"
    if not exist "!DEST_SP!" mkdir "!DEST_SP!" >nul 2>&1
    if not exist "!DEST_SP!" (
        call :log [ERROR][%%D:] SharePoint保存先の作成失敗: !DEST_SP!
        goto wait_eject
    )

    :: robocopyを実行（詳細ログを別途ファイルに）
    set "ROBOCOPY_LOG=%LOGDIR%\ROBOCOPY_%LOGDATE%.log"
    robocopy "!SRC_DIR!" "!DEST_SP!" %FILE_MASKS% /S /COPY:DAT /R:0 /W:0 >> "!ROBOCOPY_LOG!" 2>&1
    set "RC=!errorlevel!"
    
    if !RC! GEQ 8 (
        call :log [ERROR][%%D:] SharePoint転送失敗 RC=!RC! SRC=!SRC_DIR! DEST=!DEST_SP!
    ) else if !RC! EQU 0 (
        call :log [INFO][%%D:] ファイルなし RC=!RC! DEST=!DEST_SP!
    ) else (
        call :log [OK][%%D:] SharePoint転送成功 DEST=!DEST_SP!
        
        REM OneDrive同期を待つ（最大10秒）
        set "WAIT_COUNT=0"
        :sync_wait
        if !WAIT_COUNT! GEQ 10 goto sync_done
        timeout /t 1 > nul
        set /a WAIT_COUNT+=1
        goto sync_wait
        
        :sync_done
    )

    :: ========= Iドライブ（COPY） =========
    if exist "I:\" if exist "I:\id_00.txt" (
        set "DEST_I=I:\!SYSTEM_DIR!\%YYYYMM%\!FOLDER_NAME!!SUB_PATH!"
        if not exist "!DEST_I!" mkdir "!DEST_I!" >nul 2>&1
        if not exist "!DEST_I!" (
            call :log [ERROR][%%D:] Iドライブ保存先の作成失敗: !DEST_I!
        ) else (
            robocopy "!SRC_DIR!" "!DEST_I!" %FILE_MASKS% /S /COPY:DAT /R:0 /W:0 >> "!ROBOCOPY_LOG!" 2>&1
            set "RC=!errorlevel!"
            
            if !RC! GEQ 8 (
                call :log [ERROR][%%D:] Iドライブ転送失敗 RC=!RC! SRC=!SRC_DIR! DEST=!DEST_I!
            ) else if !RC! EQU 0 (
                call :log [INFO][%%D:] Iドライブ ファイルなし RC=!RC! DEST=!DEST_I!
            ) else (
                call :log [OK][%%D:] Iドライブ転送成功 DEST=!DEST_I!
            )
        )
    ) else (
        call :log [INFO] Iドライブ未接続または id_00.txt なし
    )

    powershell -NoProfile -Command "[console]::beep(440,500)" >nul 2>&1

    :wait_eject
    if exist "%%D:\" (
        timeout /t 1 > nul
        goto wait_eject
    )
))
timeout /t 2 > nul
goto loop

:log
set "_ts="
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"`) do set "_ts=%%i"
echo [!_ts!] %*>>"%LOGFILE%"
goto :eof
