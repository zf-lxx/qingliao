; 轻聊 per-user Windows installer.
;
; Required preprocessor values are supplied by
; scripts/build-windows-installer.ps1 so the same definition packages x64 and
; ARM64 release bundles locally and in GitHub Actions.

#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef Architecture
  #error Architecture is required
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef OutputBaseFilename
  #error OutputBaseFilename is required
#endif
#ifndef RepoRoot
  #error RepoRoot is required
#endif

#define AppId "6B5C51B6-9551-4E46-A685-10B2A974AD6A"

[Setup]
AppId={{{#AppId}}
AppName=轻聊
AppVersion={#AppVersion}
AppVerName=轻聊 {#AppVersion}
AppPublisher=iebb
AppPublisherURL=https://github.com/zf-lxx/qingliao
AppSupportURL=https://github.com/zf-lxx/qingliao/issues
AppUpdatesURL=https://github.com/zf-lxx/qingliao/releases/latest
DefaultDirName={localappdata}\Programs\Qingliao
DefaultGroupName=轻聊
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
SetupIconFile={#RepoRoot}\windows\runner\resources\app_icon.ico
LicenseFile={#RepoRoot}\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes
UninstallDisplayIcon={app}\qingliao.exe
; The in-app updater atomically replaces {app}. Keep uninstall metadata beside
; it so updating cannot delete Add/Remove Programs support.
UninstallFilesDir={localappdata}\Programs\Qingliao Uninstall

#if Architecture == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
; ARM64 has a native package. Do not silently install the emulated x64 build.
ArchitecturesAllowed=x64compatible and not arm64
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[InstallDelete]
; Flutter's generated asset names change between versions. Clearing this tree
; prevents removed assets from surviving a manual installer upgrade.
Type: filesandordirs; Name: "{app}\data\flutter_assets"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "*.exp,*.ilk,*.lib,*.pdb"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\轻聊"; Filename: "{app}\qingliao.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\轻聊"; Filename: "{app}\qingliao.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\qingliao.exe"; Description: "Launch 轻聊"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Portable auto-updates can introduce files that were not present when this
; uninstall log was created, so remove the owned install directory as a unit.
Type: filesandordirs; Name: "{app}"
