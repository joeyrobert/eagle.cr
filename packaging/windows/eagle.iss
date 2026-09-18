; Inno Setup script for eagle-setup.exe. Built by .github/workflows/release.yml:
;   iscc /DAppVersion=0.1.0 /DStageDir=C:\path\to\eagle-windows-x86_64 /DOutDir=C:\path\to\dist packaging\windows\eagle.iss
; StageDir holds bin\eagle.exe, bin\SDL2.dll, lib\SDL2.lib and src\ (the engine source).
; Installs per user (no admin prompt) into %LOCALAPPDATA%\eagle, like install.ps1, and adds bin\ to the user PATH.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef StageDir
  #define StageDir "..\..\dist\eagle-windows-x86_64"
#endif
#ifndef OutDir
  #define OutDir "..\..\dist"
#endif

[Setup]
AppId={{6E1A9F4C-3B7D-4C2E-9A51-EA61E0C0D2B7}
AppName=Eagle
AppVersion={#AppVersion}
AppVerName=Eagle {#AppVersion}
AppPublisher=Joey Robert
AppPublisherURL=https://github.com/joeyrobert/eagle.cr
AppSupportURL=https://github.com/joeyrobert/eagle.cr/issues
DefaultDirName={localappdata}\eagle
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
ChangesEnvironment=yes
LicenseFile=..\..\COPYING.LESSER
OutputDir={#OutDir}
OutputBaseFilename=eagle-setup
UninstallDisplayIcon={app}\bin\eagle.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "{#StageDir}\bin\*"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#StageDir}\lib\*"; DestDir: "{app}\lib"; Flags: ignoreversion
Source: "{#StageDir}\src\*"; DestDir: "{app}\src"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Replace the engine source wholesale on upgrade so deleted files don't linger.
Type: filesandordirs; Name: "{app}\src"

[Registry]
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}\bin"; Check: NeedsAddPath(ExpandConstant('{app}\bin'))

[Messages]
FinishedLabel=Eagle is installed. Open a new terminal and run "eagle init mygame". Building games also needs Crystal 1.21 or newer: https://crystal-lang.org/install/on_windows/

[Code]
function NeedsAddPath(Dir: string): Boolean;
var
  Paths: string;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', Paths) then
  begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(Paths) + ';') = 0;
end;

procedure RemoveFromPath(Dir: string);
var
  Paths: string;
  P: Integer;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', Paths) then
    exit;
  Paths := ';' + Paths + ';';
  P := Pos(';' + Uppercase(Dir) + ';', Uppercase(Paths));
  if P = 0 then
    exit;
  Delete(Paths, P, Length(Dir) + 1);
  Paths := Copy(Paths, 2, Length(Paths) - 2);
  RegWriteExpandStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', Paths);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    RemoveFromPath(ExpandConstant('{app}\bin'));
end;
