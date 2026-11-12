; SecureID Windows installer (NSIS 3)
;
; Per-user install: no administrator rights are required. The Flutter engine
; and all runtime DLLs are bundled, so the target machine does not need Flutter
; installed. The user's encrypted vault lives in %APPDATA% and is intentionally
; left untouched by uninstall.

Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma
SetCompressorDictSize 64

!define PRODUCT_NAME "SecureID"
!define PRODUCT_PUBLISHER "SecureID"
!ifndef PRODUCT_VERSION
  !define PRODUCT_VERSION "1.2.51"
!endif
!define PRODUCT_EXE "secure_id.exe"

!define RELEASE_DIR "F:\SecureID\build\windows\x64\runner\Release"
!define APP_ICON "F:\SecureID\windows\runner\resources\app_icon.ico"
!define OUT_FILE "F:\SecureID\dist\SecureID-Setup-${PRODUCT_VERSION}.exe"

Name "${PRODUCT_NAME}"
Caption "${PRODUCT_NAME} ${PRODUCT_VERSION} Setup"
OutFile "${OUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\SecureID"
InstallDirRegKey HKCU "Software\SecureID" "InstallDir"
RequestExecutionLevel user
BrandingText "${PRODUCT_NAME} ${PRODUCT_VERSION}"

VIProductVersion "${PRODUCT_VERSION}.0"
VIAddVersionKey "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "FileDescription" "${PRODUCT_NAME} Setup"
VIAddVersionKey "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey "LegalCopyright" "${PRODUCT_PUBLISHER}"

Icon "${APP_ICON}"
UninstallIcon "${APP_ICON}"

!include "MUI2.nsh"
!include "FileFunc.nsh"

!define MUI_ABORTWARNING
!define MUI_ICON "${APP_ICON}"
!define MUI_UNICON "${APP_ICON}"
!define MUI_WELCOMEPAGE_TITLE "Install ${PRODUCT_NAME}"
!define MUI_WELCOMEPAGE_TEXT "This wizard will install ${PRODUCT_NAME} on this computer.$\r$\n$\r$\n${PRODUCT_NAME} is a local-first vault for passwords, passkeys and authenticator codes. The Flutter runtime is included, so nothing else needs to be installed.$\r$\n$\r$\nThe installer uses your user profile and does not require administrator rights."
!define MUI_FINISHPAGE_RUN "$INSTDIR\${PRODUCT_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch ${PRODUCT_NAME}"
!define MUI_FINISHPAGE_TITLE "${PRODUCT_NAME} is ready"
!define MUI_FINISHPAGE_TEXT "${PRODUCT_NAME} has been installed. Your vault is stored in your user profile and is never uploaded unless you sign in to account sync."

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\SecureID"

Function .onInit
  ; A previous per-user install may already exist.
  ReadRegStr $0 HKCU "Software\SecureID" "InstallDir"
  ${If} $0 != ""
    StrCpy $INSTDIR $0
  ${EndIf}
FunctionEnd

Section "${PRODUCT_NAME}" SecMain
  SetShellVarContext current

  ; Replace a running copy so files are not locked. The vault saves atomically,
  ; so closing the app this way cannot leave a half-written file.
  nsExec::ExecToLog 'taskkill /IM ${PRODUCT_EXE} /F'
  Pop $0

  SetOutPath "$INSTDIR"
  File /r "${RELEASE_DIR}\*.*"

  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\SecureID"
  CreateShortcut "$SMPROGRAMS\SecureID\SecureID.lnk" "$INSTDIR\${PRODUCT_EXE}" "" "$INSTDIR\${PRODUCT_EXE}" 0
  CreateShortcut "$SMPROGRAMS\SecureID\Uninstall SecureID.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$DESKTOP\SecureID.lnk" "$INSTDIR\${PRODUCT_EXE}" "" "$INSTDIR\${PRODUCT_EXE}" 0

  WriteRegStr HKCU "Software\SecureID" "InstallDir" "$INSTDIR"

  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\${PRODUCT_EXE},0"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1

  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" "$0"
SectionEnd

Section "Uninstall"
  SetShellVarContext current

  nsExec::ExecToLog 'taskkill /IM ${PRODUCT_EXE} /F'
  Pop $0

  Delete "$DESKTOP\SecureID.lnk"
  Delete "$SMPROGRAMS\SecureID\SecureID.lnk"
  Delete "$SMPROGRAMS\SecureID\Uninstall SecureID.lnk"
  RMDir "$SMPROGRAMS\SecureID"

  DeleteRegKey HKCU "${UNINST_KEY}"
  DeleteRegKey HKCU "Software\SecureID"

  RMDir /r "$INSTDIR"
SectionEnd
