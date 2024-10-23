@ECHO OFF
REM this script assumes that cmd extensions are enabled

:check_cygwin
REM Cygwin binaries should not be on the PATH before the native windows binaries, in particular find.exe
find /? >NUL 2>&1
if %ERRORLEVEL% NEQ 0 (
  ECHO The find.exe executable did not work as expected. Cancelling.
  ECHO If you are using Cygwin ensure that the Windows CLI executables, most importantly find.exe, come before Cygwin on the PATH.
  EXIT /B 2
)

REM update our local copy of the TABLEAU_SERVER_* environment variables from the registry
CALL :update_env_variable TABLEAU_SERVER_CONFIG_NAME
CALL :update_env_variable TABLEAU_SERVER_DATA_DIR
CALL :update_env_variable TABLEAU_SERVER_DATA_DIR_VERSION
CALL :update_env_variable TABLEAU_SERVER_INSTALL_DIR
EXIT /B 0

:update_env_variable
REM queries the registry for the environment variable passed to the function, and sets it if found.  If it's not found in the registry, the environment variable is cleared.
SET %1=
FOR /f "tokens=2*" %%i in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v %1 2^>^&1 ^| find "REG_"') DO SET %1=%%j
EXIT /B 0