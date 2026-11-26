; Invoked by scripts/package-windows.py after deployment and validation.
Unicode true
!include "LogicLib.nsh"
!include "x64.nsh"
!ifndef MANIFEST
 !error "Use scripts/package-windows.py (a validated payload manifest is required)"
!endif
!ifndef VERSION
 !error "Missing VERSION"
!endif
!ifndef ARCH
 !error "Missing ARCH"
!endif
!ifndef OUTPUT
 !error "Missing OUTPUT"
!endif
!include "${MANIFEST}"
!ifdef SIGN_UNINSTALLER
 !uninstfinalize '${SIGN_UNINSTALLER} "%1"'
!endif
; Must match packaging/windows.wxs so the EXE can find and remove the MSI package.
!define UPGRADE_CODE "{DAF0A2B2-B00D-48A9-A57C-668B31E368A0}"
!define POWERSHELL "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe"
Name "OSMClient"
OutFile "${OUTPUT}"
!if "${ARCH}" == "amd64"
 InstallDir "$PROGRAMFILES64\OSMClient"
!else
 InstallDir "$PROGRAMFILES\OSMClient"
!endif
InstallDirRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClient" "InstallLocation"
RequestExecutionLevel admin
AutoCloseWindow true
SetCompressor /SOLID lzma
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "OSMClient"
VIAddVersionKey "FileDescription" "OSMClient Setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "FIT2CLOUD"
Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

; Close every process started from the directory on the stack (the client, its
; Go helper and PuTTY), so the old files can be removed. Processes are matched by
; full path inside that directory, never by image name alone. The calling process
; is excluded: an uninstaller started with _?= runs in place from that directory.
; Interactive runs ask
; first; silent runs close without asking. Pushes 1 to continue, 0 to stop.
!macro DefineCloseClient PREFIX
; Append one line to %TEMP%\OSMClient-setup.log (C:\Windows\Temp or SystemTemp
; when run by Windows Installer as SYSTEM). Message on the stack.
Function ${PREFIX}SetupLog
 Exch $R8
 Push $R7
 ClearErrors
 FileOpen $R7 "$TEMP\OSMClient-setup.log" a
 ${IfNot} ${Errors}
  FileSeek $R7 0 END
  FileWrite $R7 "$R8$\r$\n"
  FileClose $R7
 ${EndIf}
 Pop $R7
 Pop $R8
FunctionEnd

Function ${PREFIX}CloseClient
 Exch $R9
 Push $R0
 Push $R1
 Push $R2
 Push $R3
 Push $R4
 StrCpy $R1 1
 ${If} $R9 != ""
 ${AndIf} ${FileExists} "$R9\*.*"
 ${AndIf} ${FileExists} "${POWERSHELL}"
  ; The directory and mode go through the environment, so no path is ever quoted
  ; into the PowerShell command line. WMI reports 64-bit process paths to this
  ; 32-bit installer as well. "?" means the query failed: continue as before and
  ; let the uninstall step report locked files.
  StrCpy $R2 `$$ErrorActionPreference='Stop'; try { $$self=[int]$$env:OSM_CLIENT_SELF; $$d=[IO.Path]::GetFullPath($$env:OSM_CLIENT_DIR).TrimEnd([char]92)+[char]92; $$f={ @(Get-WmiObject Win32_Process | Where-Object { $$_.ExecutablePath -and $$_.ProcessId -ne $$self -and $$_.ExecutablePath.StartsWith($$d,[StringComparison]::OrdinalIgnoreCase) }) }; $$p=& $$f; if ($$env:OSM_CLIENT_ACTION -eq 'stop' -and $$p.Count) { $$p | ForEach-Object { Stop-Process -Id $$_.ProcessId -Force -ErrorAction SilentlyContinue }; Start-Sleep -Milliseconds 800; $$p=& $$f }; [Console]::Out.Write($$p.Count) } catch { [Console]::Out.Write('?'+$$_.Exception.Message) }`
  System::Call 'kernel32::GetCurrentProcessId() i .R0'
  System::Call 'kernel32::SetEnvironmentVariable(t "OSM_CLIENT_SELF", t "$R0")'
  System::Call 'kernel32::SetEnvironmentVariable(t "OSM_CLIENT_DIR", t "$R9")'
  System::Call 'kernel32::SetEnvironmentVariable(t "OSM_CLIENT_ACTION", t "count")'
  nsExec::ExecToStack /TIMEOUT=60000 `"${POWERSHELL}" -NoProfile -NonInteractive -Command "$R2"`
  Pop $R3
  Pop $R4
  Push "${PREFIX}CloseClient dir=$R9 self=$R0 found=$R4 exit=$R3"
  Call ${PREFIX}SetupLog
  IntOp $R0 $R4 + 0
  ${If} $R0 > 0
   ${If} ${Cmd} `MessageBox MB_OKCANCEL|MB_ICONEXCLAMATION "OSMClient is running from $R9.$\r$\n$\r$\nIt will be closed, together with any remote sessions it opened. Click OK to continue." /SD IDOK IDOK`
    System::Call 'kernel32::SetEnvironmentVariable(t "OSM_CLIENT_ACTION", t "stop")'
    nsExec::ExecToStack /TIMEOUT=60000 `"${POWERSHELL}" -NoProfile -NonInteractive -Command "$R2"`
    Pop $R3
    Pop $R4
    Push "${PREFIX}CloseClient stopped dir=$R9 remaining=$R4 exit=$R3"
    Call ${PREFIX}SetupLog
    IntOp $R0 $R4 + 0
    ${If} $R0 > 0
     MessageBox MB_ICONSTOP "OSMClient could not be closed. Quit it from the tray icon and try again." /SD IDOK
     StrCpy $R1 0
    ${EndIf}
   ${Else}
    StrCpy $R1 0
   ${EndIf}
  ${EndIf}
 ${ElseIf} $R9 != ""
  Push "${PREFIX}CloseClient skipped dir=$R9"
  Call ${PREFIX}SetupLog
 ${EndIf}
 StrCpy $R9 $R1
 Pop $R4
 Pop $R3
 Pop $R2
 Pop $R1
 Pop $R0
 Exch $R9
FunctionEnd
!macroend
!insertmacro DefineCloseClient ""
!insertmacro DefineCloseClient "un."

!macro CloseClientOrAbort DIR
 ${If} ${DIR} != ""
  Push ${DIR}
  Call CloseClient
  Pop $R0
  ${IfThen} $R0 != 1 ${|} Abort ${|}
 ${EndIf}
!macroend

Function .onInit
 SetShellVarContext all
 SetRegView 32
 !if "${ARCH}" == "amd64"
  ${IfNot} ${RunningX64}
   MessageBox MB_ICONSTOP "This package requires 64-bit Windows. Use the 386 package for 32-bit Windows."
   Abort
  ${EndIf}
 !endif
 ; Close clients of every installation this setup is going to replace.
 ReadRegStr $0 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClient" "InstallLocation"
 !insertmacro CloseClientOrAbort "$0"
 ReadRegStr $0 HKLM "Software\FIT2CLOUD\OSMClient" "WindowsInstaller"
 !insertmacro CloseClientOrAbort "$0"
 ReadRegStr $0 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClientQt" "InstallLocation"
 !insertmacro CloseClientOrAbort "$0"
FunctionEnd

Function un.onInit
 SetShellVarContext all
 SetRegView 32
 Push "$INSTDIR"
 Call un.CloseClient
 Pop $0
 ${IfThen} $0 != 1 ${|} Abort ${|}
FunctionEnd

Section "Install"
 ; 1. An old per-user EXE installation (pre-rename OSMClientQt).
 ReadRegStr $0 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClientQt" "InstallLocation"
 ${If} $0 != ""
 ${AndIf} ${FileExists} "$0\Uninstall.exe"
  DetailPrint "Removing the previous per-user OSMClient..."
  ExecWait '"$0\Uninstall.exe" /S _?=$0' $1
  ${If} $1 != 0
   Abort "The previous per-user OSMClient could not be uninstalled. Uninstall it from Windows Settings and retry."
  ${EndIf}
  Delete "$0\Uninstall.exe"
  RMDir "$0"
 ${EndIf}
 ReadRegStr $0 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClientQt" "InstallLocation"
 ${If} $0 != ""
  Abort "Uninstall the previous per-user OSMClient from Windows Settings before installing this version."
 ${EndIf}

 ; 2. MSI installations with the same UpgradeCode (per-machine, or this user's).
 ReadRegStr $0 HKLM "Software\FIT2CLOUD\OSMClient" "WindowsInstaller"
 ReadRegStr $1 HKCU "Software\FIT2CLOUD\OSMClientQt" "WindowsInstaller"
 ${If} $0 != ""
 ${OrIf} $1 != ""
  StrCpy $3 ""
  ${Do}
   System::Call 'msi::MsiEnumRelatedProductsW(w "${UPGRADE_CODE}", i 0, i 0, w .r2) i .r4'
   ${If} $4 != 0
   ${OrIf} $2 == $3
    ${ExitDo}
   ${EndIf}
   StrCpy $3 $2
   DetailPrint "Removing the installed OSMClient MSI package $2..."
   ExecWait '"$SYSDIR\msiexec.exe" /x $2 /qn /norestart' $5
   Push "Install removed MSI $2 exit=$5"
   Call SetupLog
   ${If} $5 != 0
   ${AndIf} $5 != 3010
    Abort "The installed OSMClient MSI package could not be removed (msiexec exit code $5). Uninstall it from Windows Settings and retry."
   ${EndIf}
  ${Loop}
  ReadRegStr $0 HKLM "Software\FIT2CLOUD\OSMClient" "WindowsInstaller"
  ${If} $0 != ""
   Abort "An MSI installation of OSMClient remains. Uninstall it from Windows Settings and retry."
  ${EndIf}
  ReadRegStr $1 HKCU "Software\FIT2CLOUD\OSMClientQt" "WindowsInstaller"
  ${If} $1 != ""
   Abort "A per-user MSI installation of OSMClient remains. Uninstall it from Windows Settings and retry."
  ${EndIf}
 ${EndIf}

 ; 3. A previous EXE installation: run its own uninstaller. The registry/install
 ; identity stays stable while the display name changes.
 ReadRegStr $0 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClient" "InstallLocation"
 ${If} $0 == ""
  ${If} ${FileExists} "$INSTDIR\*.*"
   Abort "The selected installation directory already exists. Choose an empty directory."
  ${EndIf}
 ${EndIf}
 ${If} $0 != ""
  ${If} ${FileExists} "$0\Uninstall.exe"
   DetailPrint "Removing the previous OSMClient..."
   ExecWait '$\"$0\Uninstall.exe$\" /S _?=$0' $1
   Push "Install ran previous uninstaller dir=$0 exit=$1"
   Call SetupLog
   ${If} $1 != 0
    Abort "The previous version could not be uninstalled. Close the client and retry."
   ${EndIf}
   ; _?= keeps the old uninstaller in place; remove it and the emptied folder.
   Delete "$0\Uninstall.exe"
   RMDir "$0"
  ${EndIf}
 ${EndIf}
 !insertmacro InstallPayload
 WriteUninstaller "$INSTDIR\Uninstall.exe"
 CreateShortcut "$SMPROGRAMS\OSMClient.lnk" "$INSTDIR\client.exe"
 CreateShortcut "$DESKTOP\OSMClient.lnk" "$INSTDIR\client.exe"
 WriteRegStr HKLM "Software\Classes\jms" "" "URL:JumpServer connection"
 WriteRegStr HKLM "Software\Classes\jms" "URL Protocol" ""
 WriteRegStr HKLM "Software\Classes\jms\DefaultIcon" "" '$\"$INSTDIR\client.exe$\",0'
 WriteRegStr HKLM "Software\Classes\jms\shell\open\command" "" '$\"$INSTDIR\client.exe$\" $\"%1$\"'
 WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClient" "DisplayName" "OSMClient"
 WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClient" "DisplayVersion" "${VERSION}"
 WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClient" "Publisher" "FIT2CLOUD"
 WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClient" "InstallLocation" "$INSTDIR"
 WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClient" "DisplayIcon" "$INSTDIR\client.exe"
 WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClient" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
 WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClient" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
 WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClient" "NoModify" 1
 WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClient" "NoRepair" 1
SectionEnd

Section "Uninstall"
 SetShellVarContext all
 SetRegView 32
 ReadRegStr $0 HKLM "Software\Classes\jms\shell\open\command" ""
 ${If} $0 == '$\"$INSTDIR\client.exe$\" $\"%1$\"'
  DeleteRegKey HKLM "Software\Classes\jms"
 ${EndIf}
 !insertmacro RemovePayload
 Delete "$INSTDIR\Uninstall.exe"
 RMDir "$INSTDIR"
 DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\OSMClient"
 Delete "$SMPROGRAMS\OSMClient.lnk"
 Delete "$DESKTOP\OSMClient.lnk"
SectionEnd
