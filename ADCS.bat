@echo off
setlocal EnableDelayedExpansion

title 【実行中】SDカード自動識別システム
chcp 932 > nul

REM ==============================
REM 設定（現場に合わせて変更）
REM ==============================
REM SDカードを監視するドライブ文字（Iドライブ等のバックアップ先は含めない）
set "SCAN_DRIVES=E F G H J K L M N"
set "BACKUP_DRIVE=I"
set "LOG_KEEP_DAYS=90"

REM 検出に失敗する特殊な環境向けの手動指定（03_検針 の親フォルダを設定）
REM 例: set "ADCS_ROOT=D:\OneDrive - 会社名\02_点検、記録"

REM クイック編集モード無効化（コンソールのクリックで停止するのを防ぐ。次回起動のコンソールから有効）
reg add "HKCU\Console" /v QuickEdit /t REG_DWORD /d 0 /f >nul 2>&1

REM ==============================
REM ログ
REM ==============================
set "LOGDIR=%~dp0logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1

call :refresh_date
if errorlevel 1 (
    echo [ERROR] 日付の取得に失敗しました。
    pause
    exit /b 1
)

forfiles /p "%LOGDIR%" /m *.log /d -%LOG_KEEP_DAYS% /c "cmd /c del @path" >nul 2>&1

call :log ===========================================
call :log SDカード自動識別システム（共通版） 起動
call :log [INFO] USERPROFILE=%USERPROFILE%
call :log [INFO] OneDriveCommercial=%OneDriveCommercial%
call :log [INFO] OneDrive=%OneDrive%

REM ==============================
REM SharePoint保存先自動判定
REM %USERPROFILE%直下（ライブラリ同期）と
REM %OneDriveCommercial%配下（OneDriveへのショートカット追加）の両対応
REM ==============================
echo SharePoint保存先を検索しています...
set "TRY=0"

:detect
set "SP_DOC_ROOT="
set "SP_DOC_PARTIAL="
set "SP_DOC_MISSING="
set "BASE_N=0"
call :collect_bases

REM --- 第1段階：既知の階層パターンで高速判定 ---
for /l %%I in (1,1,!BASE_N!) do if not defined SP_DOC_ROOT call :try_root "!BASE_%%I!"

REM --- 第2段階：03_検針 を再帰検索（負荷軽減のため10回に1回） ---
set /a "DEEPNOW=TRY %% 10"
if not defined SP_DOC_ROOT if !DEEPNOW! EQU 0 (
    for /l %%I in (1,1,!BASE_N!) do if not defined SP_DOC_ROOT if "!BASE_DEEP_%%I!"=="1" call :deep_root "!BASE_%%I!"
)

if not defined SP_DOC_ROOT (
    set /a TRY+=1
    if !TRY! LSS 60 (
        ping -n 6 127.0.0.1 >nul
        goto detect
    )
)

if not defined SP_DOC_ROOT (
    call :log [ERROR] SharePoint保存先の検出に失敗しました
    for /l %%I in (1,1,!BASE_N!) do call :log [INFO] 検索した場所 !BASE_%%I!
    echo.
    echo [ERROR]
    if defined SP_DOC_PARTIAL (
        call :log [ERROR] 部分同期の可能性 ROOT=!SP_DOC_PARTIAL! 不足=!SP_DOC_MISSING!
        echo 検針フォルダは見つかりましたが、次の系統フォルダがローカルにありません。
        echo   場所：!SP_DOC_PARTIAL!\03_検針
        echo   不足：!SP_DOC_MISSING!
        echo.
        echo OneDrive設定 ＞ アカウント ＞ フォルダーの選択 で
        echo 上記フォルダのチェックが外れていないか確認してください。
        echo チェックが入っている場合は SharePoint 側のアクセス権を確認してください。
    ) else (
        echo SharePoint保存先が見つかりません。OneDriveにサインイン後、
        echo 以下のいずれかをOneDriveへ追加してください。
        echo.
        echo SAM_中部チーム - ドキュメント（ライブラリ同期）
        echo B01_木曽川右岸管理事務所
        echo 5215木曽川右岸【契約業務】
        echo 104.運転・運用記録
        echo 02_点検、記録
        echo 03_検針
        echo.
        echo 検索した場所はログに記録しています。
        echo ログ：!LOGFILE!
    )
    echo.
    pause
    exit /b 1
)

for %%F in ("!SP_DOC_ROOT!\.") do set "SP_DOC_ROOT=%%~fF"

set "KENSHIN_ROOT=!SP_DOC_ROOT!\03_検針"

for %%N in (01_横河 02_Mシステム 03_フジ) do if not exist "!KENSHIN_ROOT!\%%N\" (
    call :log [ERROR] %%N フォルダが見つかりません ROOT=!KENSHIN_ROOT!
    echo [ERROR] %%N フォルダが見つかりません
    echo 場所：!KENSHIN_ROOT!
    pause
    exit /b 1
)

set "BASE_YOKOGAWA=!KENSHIN_ROOT!\01_横河"
set "BASE_MSYSTEM=!KENSHIN_ROOT!\02_Mシステム"
set "BASE_FUJI=!KENSHIN_ROOT!\03_フジ"

call :log 検針ルート=!KENSHIN_ROOT!

echo ===========================================
echo   SDカード自動識別システム（共通版）
echo ===========================================
echo 状態：実行中
echo 検針ルート：!KENSHIN_ROOT!
echo 監視ドライブ：%SCAN_DRIVES%
echo バックアップ：%BACKUP_DRIVE%ドライブ（id_00.txt がある場合のみコピー）
echo バックアップ構成：系統\年月\設備\!MONTH_DIR!
echo 対象フォルダ：DATA0 / 71VR / S000000
echo ログ：!LOGFILE!
echo ※ 終了：Ctrl + C
echo ※ エラー音が鳴った場合はカードを抜かずに画面を確認してください
echo ===========================================
echo.

:loop
for %%D in (%SCAN_DRIVES%) do call :process_drive %%D
ping -n 3 127.0.0.1 >nul
goto loop


REM ==============================
REM ドライブ単位の処理
REM ==============================
:process_drive
set "DRV=%~1"
if /i "%DRV%"=="%BACKUP_DRIVE%" exit /b

REM カードが無い＝処理済み・通知済みフラグをクリア
if not exist "%DRV%:\" (
    set "DONE_%DRV%="
    set "NOTE_%DRV%="
    set "TRIES_%DRV%="
    exit /b
)
if defined DONE_%DRV% exit /b

REM ========= コピー元フォルダ自動判定 =========
set "SRC_DIR="
if exist "%DRV%:\DATA0" (
    set "SRC_DIR=%DRV%:\DATA0"
) else if exist "%DRV%:\71VR" (
    set "SRC_DIR=%DRV%:\71VR"
) else if exist "%DRV%:\S000000" (
    set "SRC_DIR=%DRV%:\S000000"
)

if not defined SRC_DIR (
    if not defined NOTE_%DRV% (
        set "NOTE_%DRV%=1"
        call :log [%DRV%:] 対象フォルダなし DATA0/71VR/S000000
    )
    exit /b
)

REM ========= 年月・ログ日付を最新化 =========
call :refresh_date
if errorlevel 1 (
    set "DONE_%DRV%=1"
    call :alert_error "[%DRV%:] 日付の取得に失敗しました。コピーを中止しました"
    exit /b
)
set "ROBOCOPY_LOG=%LOGDIR%\ROBOCOPY_!LOGDATE!.log"

call :log [%DRV%: 検出] 判定中...

REM ========= 設備判定（表形式。複数IDはエラー） =========
set "ID_COUNT=0"
set "SYS_CODE="
set "FOLDER_NAME="
set "SUB_PATH="
set "TARGET_EXT="
set "SYS_ROOT="
set "SYSTEM_DIR="
set "SAVE_BASE="

REM 書式: "ID番号|系統(Y=横河,M=Mシステム,F=フジ)|フォルダ名"
for %%T in (
    "01|Y|01_下羽栗"
    "02|Y|02_芥見"
    "03|Y|03_岐南西"
    "04|Y|04_川島第二"
    "05|Y|05_長森ポンプ場"
    "06|Y|06_米野"
    "07|Y|07_東部第一"
    "08|Y|08_東部第二"
    "09|Y|09_梅松"
    "11|Y|11_深田、酒倉"
    "12|Y|12_川辺"
    "13|Y|13_中恵土"
    "14|Y|14_八百津"
    "15|Y|15_緑苑"
    "16|Y|16_和知"
    "21|M|01_兼山ポンプ場"
    "22|M|02_川島ポンプ場"
    "31|F|01_岐南ポンプ場"
) do for /f "tokens=1-3 delims=|" %%a in (%%T) do (
    if exist "%DRV%:\id_%%a.txt" (
        set /a ID_COUNT+=1
        set "SYS_CODE=%%b"
        set "FOLDER_NAME=%%c"
    )
)

if !ID_COUNT! GTR 1 (
    set "DONE_%DRV%=1"
    call :alert_error "[%DRV%:] IDファイルが複数あります。コピーを中止しました"
    exit /b
)
if !ID_COUNT! EQU 0 (
    set "SYS_CODE=Y"
    set "FOLDER_NAME=未識別カード"
)

if "!SYS_CODE!"=="Y" set "SYS_ROOT=!BASE_YOKOGAWA!" & set "SYSTEM_DIR=01_横河" & set "TARGET_EXT=.GDS"
if "!SYS_CODE!"=="M" set "SYS_ROOT=!BASE_MSYSTEM!" & set "SYSTEM_DIR=02_Mシステム" & set "TARGET_EXT=.71VR" & set "SUB_PATH=\01_初期データ"
if "!SYS_CODE!"=="F" set "SYS_ROOT=!BASE_FUJI!" & set "SYSTEM_DIR=03_フジ" & set "TARGET_EXT=.FDT"

if not defined TARGET_EXT (
    set "DONE_%DRV%=1"
    call :alert_error "[%DRV%:] 対象拡張子を決定できません。コピーを中止しました"
    exit /b
)

set "SAVE_BASE=!SYS_ROOT!\!YYYYMM!"
set "FILE_MASKS=*!TARGET_EXT! *.DAD"

call :log [%DRV%:] 設備=!FOLDER_NAME! 系統=!SYS_CODE! マスク=!FILE_MASKS!

set "SP_OK=0"
set "I_STATE=SKIP"
set "ONEDRIVE_DOWN="

REM ========= OneDrive稼働確認 =========
tasklist /fi "imagename eq OneDrive.exe" 2>nul | find /i "OneDrive.exe" >nul
if errorlevel 1 set "ONEDRIVE_DOWN=1"

REM ========= SharePoint（OneDrive同期フォルダへCOPY） =========
if not exist "!SYS_ROOT!" (
    call :log [ERROR][%DRV%:] 保存先の系統フォルダがありません 同期解除の可能性 !SYS_ROOT!
) else (
    set "DEST_SP=!SAVE_BASE!\!FOLDER_NAME!!SUB_PATH!"
    if not exist "!DEST_SP!" mkdir "!DEST_SP!" >nul 2>&1
    if not exist "!DEST_SP!" (
        call :log [ERROR][%DRV%:] 保存先の作成失敗 !DEST_SP!
    ) else (
        call :do_copy "!SRC_DIR!" "!DEST_SP!"
        if "!COPY_RESULT!"=="COPIED" (
            set "SP_OK=1"
            call :log [OK][%DRV%:] OneDrive同期フォルダへコピー完了 DEST=!DEST_SP!
        ) else if "!COPY_RESULT!"=="NOCHANGE" (
            set "SP_OK=1"
            call :log [INFO][%DRV%:] 新規コピーなし 該当ファイルなしまたはコピー済み DEST=!DEST_SP!
        ) else (
            call :log [ERROR][%DRV%:] 転送失敗 RC=!RC! RC2=!RC2! SRC=!SRC_DIR! DEST=!DEST_SP!
        )
    )
)

REM ========= バックアップドライブ（COPY） =========
if exist "%BACKUP_DRIVE%:\id_00.txt" (
    set "DEST_I=%BACKUP_DRIVE%:\!SYSTEM_DIR!\!YYYYMM!\!FOLDER_NAME!\!MONTH_DIR!!SUB_PATH!"
    if not exist "!DEST_I!" mkdir "!DEST_I!" >nul 2>&1
    if not exist "!DEST_I!" (
        set "I_STATE=NG"
        call :log [ERROR][%DRV%:] バックアップ保存先の作成失敗 !DEST_I!
    ) else (
        call :do_copy "!SRC_DIR!" "!DEST_I!"
        if "!COPY_RESULT!"=="NG" (
            set "I_STATE=NG"
            call :log [ERROR][%DRV%:] バックアップ転送失敗 RC=!RC! RC2=!RC2! DEST=!DEST_I!
        ) else (
            set "I_STATE=OK"
            call :log [OK][%DRV%:] バックアップ転送成功 !COPY_RESULT! DEST=!DEST_I!
        )
    )
) else (
    call :log [INFO] バックアップドライブ未接続または id_00.txt なし
)

REM ========= 結果判定 =========
set "ALL_OK=1"
if not "!SP_OK!"=="1" set "ALL_OK=0"
if "!I_STATE!"=="NG" set "ALL_OK=0"

if "!ALL_OK!"=="1" (
    set "DONE_%DRV%=1"
    call :log [%DRV%:] 処理完了 カードを取り外せます
    powershell -NoProfile -Command "[console]::beep(440,500)" >nul 2>&1
    if defined ONEDRIVE_DOWN call :alert_error "OneDriveが起動していません。コピーは同期されていません"
) else (
    set /a "TRIES_%DRV%+=1"
    for %%V in (TRIES_%DRV%) do set "TRY_NOW=!%%V!"
    call :alert_error "[%DRV%:] コピー失敗 カードを抜かずに管理者へ連絡してください 試行=!TRY_NOW!/3"
    if !TRY_NOW! GEQ 3 (
        set "DONE_%DRV%=1"
        call :log [ERROR][%DRV%:] リトライ上限 再挿入で再実行します
    ) else (
        ping -n 6 127.0.0.1 >nul
    )
)
exit /b


REM ==============================
REM robocopy＋検証（%1=コピー元 %2=コピー先 → COPY_RESULT=COPIED/NOCHANGE/NG）
REM ==============================
:do_copy
set "COPY_RESULT=NG"
set "RC=" & set "RC2="
robocopy %1 %2 !FILE_MASKS! /S /COPY:DT /DCOPY:T /FFT /R:2 /W:3 /NP /NDL >> "!ROBOCOPY_LOG!" 2>&1
set "RC=!errorlevel!"
if !RC! GEQ 8 exit /b
set /a "COPIED=RC & 1"

REM 検証：まだコピーが必要なファイルが無いこと（RC 1/4/8 が立たない）
robocopy %1 %2 !FILE_MASKS! /S /L /FFT /NJH /NJS /NP /NDL /NFL >nul 2>&1
set "RC2=!errorlevel!"
set /a "VNG=RC2 & 13"
if !VNG! NEQ 0 exit /b

if !COPIED! EQU 1 (
    set "COPY_RESULT=COPIED"
) else (
    set "COPY_RESULT=NOCHANGE"
)
exit /b


REM ==============================
REM 探索の起点候補を収集
REM ==============================
:collect_bases
REM 手動指定（最優先）
if defined ADCS_ROOT call :add_base "%ADCS_ROOT%" 1

REM OneDriveへのショートカット追加に対応
call :add_base "%OneDriveCommercial%" 1
call :add_base "%OneDrive%" 1
for %%K in (1 2 3 4 5) do for /f "tokens=2,*" %%a in ('reg query "HKCU\Software\Microsoft\OneDrive\Accounts\Business%%K" /v UserFolder 2^>nul ^| find "UserFolder"') do call :add_base "%%b" 1

REM OneDrive同期ルートの親（ライブラリ同期フォルダは同じ階層に作られる）
set "BASE_SNAP=!BASE_N!"
for /l %%I in (1,1,!BASE_SNAP!) do call :add_parent "!BASE_%%I!"

REM ユーザープロファイル直下のライブラリ同期フォルダに対応
for /d %%S in ("%USERPROFILE%\*") do call :add_profile_dir "%%~fS"
call :add_base "%USERPROFILE%" 0
exit /b


:add_parent
for %%P in ("%~1\..") do call :add_base "%%~fP" 0
exit /b


:add_profile_dir
set "_n=%~nx1"
set "_skip="
for %%X in (
    "AppData" "Desktop" "Documents" "Downloads" "Favorites" "Links" "Contacts"
    "Searches" "Saved Games" "Music" "Pictures" "Videos" "3D Objects"
    "Application Data" "Local Settings" "NetHood" "PrintHood" "Recent"
    "SendTo" "Templates" "IntelGraphicsProfiles" "MicrosoftEdgeBackups"
) do if /i "!_n!"=="%%~X" set "_skip=1"
if defined _skip exit /b
call :add_base "%~1" 1
exit /b


REM ==============================
REM 起点候補の登録（%1=パス %2=再帰検索する場合は1）
REM ==============================
:add_base
set "_b=%~1"
if not defined _b exit /b
for %%F in ("!_b!\.") do set "_b=%%~fF"
if not exist "!_b!\" exit /b
for /l %%I in (1,1,!BASE_N!) do if /i "!BASE_%%I!"=="!_b!" exit /b
set /a BASE_N+=1
set "BASE_!BASE_N!=!_b!"
set "BASE_DEEP_!BASE_N!=%~2"
exit /b


REM ==============================
REM 既知の階層パターンで判定（%1=起点）
REM ==============================
:try_root
if defined SP_DOC_ROOT exit /b
if "%~1"=="" exit /b
for %%P in (
    "SAM_中部チーム - ドキュメント\B01_木曽川右岸管理事務所\5215木曽川右岸【契約業務】\104.運転・運用記録\02_点検、記録"
    "B01_木曽川右岸管理事務所\5215木曽川右岸【契約業務】\104.運転・運用記録\02_点検、記録"
    "5215木曽川右岸【契約業務】\104.運転・運用記録\02_点検、記録"
    "104.運転・運用記録\02_点検、記録"
    "02_点検、記録"
    "."
) do if not defined SP_DOC_ROOT call :verify_root "%~1\%%~P"
exit /b


REM ==============================
REM 03_検針 を再帰検索（%1=起点）
REM ==============================
:deep_root
if defined SP_DOC_ROOT exit /b
if "%~1"=="" exit /b
if not exist "%~1\" exit /b
for /f "delims=" %%D in ('dir /b /s /ad "%~1\03_検針" 2^>nul') do if not defined SP_DOC_ROOT call :verify_root "%%~dpD."
exit /b


REM ==============================
REM 保存先ルートの検証（%1=03_検針 の親フォルダ候補）
REM 3系統すべて揃っていれば採用。不足があれば部分同期として記録
REM ==============================
:verify_root
set "_c=%~1"
for %%F in ("!_c!\.") do set "_c=%%~fF"
if not exist "!_c!\03_検針\" exit /b
set "_miss="
if not exist "!_c!\03_検針\01_横河\" set "_miss=!_miss! 01_横河"
if not exist "!_c!\03_検針\02_Mシステム\" set "_miss=!_miss! 02_Mシステム"
if not exist "!_c!\03_検針\03_フジ\" set "_miss=!_miss! 03_フジ"
if not defined _miss (
    set "SP_DOC_ROOT=!_c!"
    exit /b
)
if not defined SP_DOC_PARTIAL (
    set "SP_DOC_PARTIAL=!_c!"
    set "SP_DOC_MISSING=!_miss!"
)
exit /b


REM ==============================
REM 日付取得（PowerShell 1回）
REM ==============================
:refresh_date
set "LOGDATE=" & set "YYYYMM=" & set "MONTH_DIR="
for /f "tokens=1,2,3" %%a in ('powershell -NoProfile -Command "(Get-Date).ToString('yyyyMMdd yyyyMM M')"') do (
    set "LOGDATE=%%a"
    set "YYYYMM=%%b"
    set "MONTH_DIR=%%c月"
)
if not defined YYYYMM exit /b 1
if not defined MONTH_DIR exit /b 1
set "LOGFILE=%LOGDIR%\ADCS_!LOGDATE!.log"
exit /b 0


REM ==============================
REM エラー通知（画面・ログ・警告音）
REM ==============================
:alert_error
echo.
echo ★★★ [エラー] %~1 ★★★
call :log [ERROR] %~1
powershell -NoProfile -Command "1..3|%%{[console]::beep(880,400);Start-Sleep -m 200}" >nul 2>&1
exit /b


REM ==============================
REM ログ（ファイル＋画面）
REM ==============================
:log
set "_msg=%*"
set "_t=%TIME: =0%"
>>"%LOGFILE%" echo [!LOGDATE! !_t:~0,8!] !_msg!
echo [!_t:~0,8!] !_msg!
goto :eof
