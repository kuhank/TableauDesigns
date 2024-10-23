@ECHO OFF
@SETLOCAL enableextensions enabledelayedexpansion
REM Make sure Windows binaries are on the PATH before custom ones
SET PATH=%SystemRoot%\System32;%PATH%

:check_bitness
REM Running a 32-bit shell on 64-bit systems may cause trouble when working with the Windows registry.
IF %PROCESSOR_ARCHITECTURE% == x86 (
  ECHO Warning: Running in a 32-bit shell.
  ECHO It is recommended that you start your shell by manually executing %SystemRoot%\System32\cmd.exe from Windows Explorer
)

:check_tab_root
IF "%TAB_ROOT%" NEQ "" (
:%~nx0 = script name
  ECHO Cannot run %~nx0 if %%TAB_ROOT%% is set.
  EXIT /B 1
)

:check_admin
NET SESSION >NUL 2>&1
if %ERRORLEVEL% NEQ 0 (
  ECHO This script must be run as Administrator. Cancelling.
  EXIT /B 1
)

:check_cygwin
REM Cygwin binaries should not be on the PATH before the native windows binaries, in particular find.exe
find /? >NUL 2>&1
if %ERRORLEVEL% NEQ 0 (
  ECHO The find.exe executable did not work as expected. Cancelling.
  ECHO If you are using Cygwin ensure that the Windows CLI executables, most importantly find.exe, come before Cygwin on the PATH.
  EXIT /B 1
)

SET refresh_env_script_filename=refresh-environment-variables.cmd
SET refresh_env_script_fullpath="%~dp0%refresh_env_script_filename%"

:refresh_environment_variables
CALL %refresh_env_script_fullpath%

REM script global variables
SET script_dir=%~dp0
IF %script_dir:~-1%==\ SET script_dir=%script_dir:~0,-1%
SET script_full_path=%0
SET script_filename=%~n0%~x0
SET tsm_services=tabadminagent_0 tabadmincontroller_0 tabsvc_0 clientfileservice_0 licenseservice_0 activationservice_0 appzookeeper_0 appzookeeper_1
SET tsm_env_vars=TABLEAU_SERVER_CONFIG_NAME TABLEAU_SERVER_DATA_DIR TABLEAU_SERVER_DATA_DIR_VERSION TABLEAU_SERVER_INSTALL_DIR TSM_CLEAN_INSTALL_FAILURE TABLEAU_SERVER_MSI
SET version_string=20221.22.0328.2249
SET license_removal_requested=0
SET yes=0
SET very_silent=0
SET bypass_script_dir_check=0
SET move_backups=1
SET move_logs=1
SET bin_path=%TABLEAU_SERVER_INSTALL_DIR%\packages\bin.%version_string%
SET java_path=%TABLEAU_SERVER_INSTALL_DIR%\packages\repository.%version_string%\jre\bin\java.exe
SET remove_license_jar=%TABLEAU_SERVER_INSTALL_DIR%\packages\bin.%version_string%\app-remove-license.jar
SET delete_deep_jar=%TABLEAU_SERVER_INSTALL_DIR%\packages\bin.%version_string%\app-delete-deep.jar
FOR %%a IN ("%TABLEAU_SERVER_DATA_DIR%") DO SET logdir=%%~dpa
SET logfile=%logdir%tableau-server-obliterate.log

:parse_command_line_params
IF "%1"=="" GOTO end_parse
IF "%1"=="-l" SET license_removal_requested=1
IF "%1"=="/l" SET license_removal_requested=1
IF "%1"=="-h" GOTO show_help
IF "%1"=="/h" GOTO show_help
IF "%1"=="-y" SET /A yes=%yes%+1
IF "%1"=="/y" SET /A yes=%yes%+1
IF "%1"=="-q" SET very_silent=1
IF "%1"=="/q" SET very_silent=1
IF "%1"=="-b" SET bypass_script_dir_check=1
IF "%1"=="/b" SET bypass_script_dir_check=1
IF "%1"=="-k" SET move_backups=0
IF "%1"=="/k" SET move_backups=0
IF "%1"=="-g" SET move_logs=0
IF "%1"=="/g" SET move_logs=0
IF "%1"=="-a" (
  SET move_backups=0
  SET move_logs=0
)
IF "%1"=="/a" (
  SET move_backups=0
  SET move_logs=0
)

SHIFT
GOTO parse_command_line_params
:end_parse

:confirm
IF %yes% LSS 3 (
  ECHO You must specify the '-y' flag three times to confirm running the script is desired
  ECHO.
  GOTO show_help
)

ECHO Log written to %logfile%

:check_script_dir
IF %bypass_script_dir_check% EQU 0 (
  IF /I "%script_dir%" NEQ "%TEMP%" (
    COPY !script_full_path! !TEMP!\!script_filename! /Y >NUL 2>&1
    COPY !refresh_env_script_fullpath! !TEMP!\!refresh_env_script_filename! /Y >NUL 2>&1
    START cmd /c !TEMP!\!script_filename! %*
    EXIT /B 0
  )
)

:deactivate_licenses
IF %license_removal_requested% EQU 1 (
  atrdiag -product "Tableau Server" -deleteAllATRs
  IF EXIST "%remove_license_jar%" (
    IF EXIST "%java_path%" (
      "%java_path%" -jar "%remove_license_jar%" "%bin_path%"
    ) ELSE (
      CALL :log Unable to find Java executable, skipping license deactivation.
    )
  ) ELSE (
    CALL :log Unable to find app-remove-license.jar, skipping license deactivation.
  )
)

:remove_tsm_services
FOR %%s IN (%tsm_services%) DO (
  SC QUERY %%s >NUL 2>&1
  IF !ERRORLEVEL! EQU 0 (
    FOR /F "tokens=3" %%P IN ('SC QUERYEX %%s ^| FINDSTR PID') DO (SET pid=%%P)
    IF "!pid!" NEQ "0" (
      CALL :log Service %%s is running with process ID: !pid!
      CALL :log Stopping service %%s
      NET STOP %%s >NUL 2>&1
      TASKKILL /F /PID !pid! >NUL 2>&1
    )

    CALL :log Deleting service %%s
    SC DELETE %%s >NUL 2>&1
  ) ELSE (
    CALL :log Service %%s not found. Skipping.
  )
)

:set_use_delete_deep_jar
SET use_delete_deep_jar=1
IF NOT EXIST "%java_path%" SET use_delete_deep_jar=0
IF NOT EXIST "%delete_deep_jar%" SET use_delete_deep_jar=0

:move_crucial_dirs
SET move_something=0
IF %move_backups% EQU 1 SET move_something=1
IF %move_logs% EQU 1 SET move_something=1
IF %move_something% NEQ 1 GOTO delete_data_dir
FOR %%a IN ("%TABLEAU_SERVER_DATA_DIR%") DO SET "LOGS_TEMP_DIR=%%~dpalogs-temp"
CALL :find_logs_temp_new_dir
MKDIR "%LOGS_TEMP_NEW_DIR%"
IF !ERRORLEVEL! NEQ 0 (
  CALL :log Unable to create directory "%LOGS_TEMP_NEW_DIR%".
  EXIT /B 1
)
IF %move_backups% EQU 1 (
  IF EXIST "%TABLEAU_SERVER_DATA_DIR%\data\%TABLEAU_SERVER_CONFIG_NAME%\files\backups" (
    MOVE /Y "%TABLEAU_SERVER_DATA_DIR%\data\%TABLEAU_SERVER_CONFIG_NAME%\files\backups" "%LOGS_TEMP_NEW_DIR%\backups"
    IF !ERRORLEVEL! NEQ 0 (
      CALL :log Unable to move directory "%TABLEAU_SERVER_DATA_DIR%\data\%TABLEAU_SERVER_CONFIG_NAME%\files\backups".
      EXIT /B 1
    )
  )
)
IF %move_logs% EQU 1 (
  IF EXIST "%TABLEAU_SERVER_DATA_DIR%\data\%TABLEAU_SERVER_CONFIG_NAME%\logs" (
    MOVE /Y "%TABLEAU_SERVER_DATA_DIR%\data\%TABLEAU_SERVER_CONFIG_NAME%\logs" "%LOGS_TEMP_NEW_DIR%\logs"
    IF !ERRORLEVEL! NEQ 0 (
      CALL :log Unable to move directory "%TABLEAU_SERVER_DATA_DIR%\data\%TABLEAU_SERVER_CONFIG_NAME%\logs".
      EXIT /B 1
    )
  )
  IF EXIST "%TABLEAU_SERVER_DATA_DIR%\logs" (
    IF NOT EXIST "%LOGS_TEMP_NEW_DIR%\logs" (
      MKDIR "%LOGS_TEMP_NEW_DIR%\logs"
      IF !ERRORLEVEL! NEQ 0 (
        CALL :log Unable to create directory "%LOGS_TEMP_NEW_DIR%\logs".
        EXIT /B 1
      )
    )
    MOVE /Y "%TABLEAU_SERVER_DATA_DIR%\logs" "%LOGS_TEMP_NEW_DIR%\logs\logs"
    IF !ERRORLEVEL! NEQ 0 (
      CALL :log Unable to move directory "%TABLEAU_SERVER_DATA_DIR%\logs".
      EXIT /B 1
    )
  )
)
CALL :delete_dir "%LOGS_TEMP_DIR%"
MOVE "%LOGS_TEMP_NEW_DIR%" "%LOGS_TEMP_DIR%"

:delete_data_dir
CALL :delete_dir "%TABLEAU_SERVER_DATA_DIR%\data"
CALL :delete_dir "%TABLEAU_SERVER_DATA_DIR%\logs"
CALL :delete_dir "%ALLUSERSPROFILE%\Tableau\Tableau Server"

:uninstall_packages
CALL :log Searching for pre-MSI based Tableau Servers to uninstall.
FOR /F "tokens=*" %%K IN ('reg query HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall /f TableauServer /k /reg:64 2^>NUL ^| FINDSTR /R /C:"TableauServer"') DO (
  FOR /F "tokens=2*" %%A IN ('REG Query "%%K" /F DisplayName /V /E /reg:64 ^| FIND /I " DisplayName "') DO CALL :log Uninstalling %%B
  IF %very_silent% EQU 1 (
    FOR /F "tokens=2*" %%A IN ('REG Query "%%K" /F UninstallString /V /E /reg:64 ^| FIND /I " UninstallString "') DO START "" /B %%B /VERYSILENT /SUPPRESSMSGBOXES
  ) ELSE (
    FOR /F "tokens=2*" %%A IN ('REG Query "%%K" /F UninstallString /V /E /reg:64 ^| FIND /I " UninstallString "') DO START "" /B %%B /SILENT /SUPPRESSMSGBOXES
  )
)

:uninstall_packages_wix
CALL :log Searching for MSI based Tableau Servers to uninstall.
FOR /F "tokens=*" %%G IN ('reg query HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall 2^>NUL') DO (
  FOR /F "tokens=*" %%K IN ('REG Query "%%G" /F BundleTag /V /E ^| FINDSTR /R /C:"TableauServer"') DO (
    FOR /F "tokens=2*" %%A IN ('REG Query "%%G" /F BundleTag /V /E ^| FIND /I " BundleTag "') DO CALL :log Uninstalling %%B
    IF %very_silent% EQU 1 (
      FOR /F "tokens=2*" %%A IN ('REG Query "%%G" /F UninstallString /V /E ^| FIND /I " UninstallString "') DO START "" /B /WAIT %%B /uninstall /QUIET
    ) ELSE (
      FOR /F "tokens=2*" %%A IN ('REG Query "%%G" /F UninstallString /V /E ^| FIND /I " UninstallString "') DO START "" /B /WAIT %%B /uninstall /PASSIVE
    )
  )
)

:remove_certs
certutil -delstore root TableauServerManagerCA

:remove_env_vars
CALL :log Deleting Tableau Server environment variables
FOR %%v IN (%tsm_env_vars%) DO (
  reg delete "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v %%v /f >NUL 2>&1
)

:remove_tableau_reg_keys
REG DELETE "HKEY_LOCAL_MACHINE\SOFTWARE\Tableau\Tableau Server %version_string%" /f /reg:64 >NUL

:remove_Server_ATR_reg_value
REG DELETE "HKEY_LOCAL_MACHINE\SOFTWARE\Tableau\ATR" /v ATRServer /f /reg:64 >NUL

CALL :log Tableau Server obliterated
EXIT /B 0

:find_logs_temp_new_dir
FOR /L %%i IN (1,1,999) DO (
  SET LOGS_TEMP_NEW_DIR=%LOGS_TEMP_DIR%-%%i
  IF NOT EXIST "!LOGS_TEMP_NEW_DIR!" GOTO :EOF
)
GOTO :EOF

:delete_dir
IF NOT EXIST %1 GOTO :EOF
CALL :log Deleting directory %1
FOR /L %%n IN (1,1,5) DO (
  TIMEOUT /T 1 >NUL
  IF %use_delete_deep_jar% EQU 1 (
    "%java_path%" -jar "%delete_deep_jar%" %1
  ) ELSE (
    RD /S /Q %1
  )
  IF NOT EXIST %1 (
    CALL :log Directory %1 deleted
    GOTO :EOF
  )
)
CALL :log Directory %1 could not be deleted
GOTO :EOF

:log
ECHO %*
ECHO !DATE:~10,4!-!DATE:~7,2!-!DATE:~4,2! !TIME! - %* >>"%logfile%"
GOTO :EOF

:show_help
ECHO Usage: tableau-server-obliterate [-h] [-l] [-q] [-k] [-g] [-a] -y -y -y
ECHO.
ECHO Remove Tableau Server from this computer.
ECHO.
ECHO This script will stop and remove all Tableau Services from this computer.
ECHO It also removes data, configuration files, and registry entries. It leaves
ECHO licensing in place. It also preserves logs and backup files, which are
ECHO moved to a temp directory under the Tableau data folder. You can force
ECHO removal of these files, and licensing, using optional parameters.
ECHO.
ECHO This script is destructive and not reversible. It should only
ECHO be used to clean Tableau Server from a computer. For multi-node
ECHO installations, you must run the script separately on each node.
ECHO.
ECHO This script must be run as the local administrator.
ECHO.
ECHO   -y                       Required. Yes, remove Tableau Server from this computer.
ECHO                            Must be specified three times to confirm.
ECHO   -q                       Optional. Quiet mode. Windows only. Do not display
ECHO                            progress UI when removing Tableau Server.
ECHO   -l                       Optional. Delete licensing files and data. This command
ECHO                            will attempt to deactivate licenses before deleting
ECHO                            licensing data. Internet access is required for license
ECHO                            deactivation. Offline deactivation is not supported.
ECHO                            To deactivate license before removing Tableau Server,
ECHO                            run 'tsm licenses deactivate' before running this script.
ECHO   -k                       Optional. Do not copy backups to logs-temp directory.
ECHO   -g                       Optional. Do not copy logs to logs-temp directory.
ECHO   -a                       Optional. Do not copy anything to logs-temp directory.