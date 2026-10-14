; Inno Setup script for Widget Bench.
; Invoked by build-installer.ps1:  ISCC /DAppVersion=0.1.0 /DArch=x64 /DSourceDir=... widget_bench.iss
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef Arch
  #define Arch "x64"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
AppId={{6F2B3E54-9C1A-4B8E-9E57-1D2C3B4A5F60}
AppName=Widget Bench
AppVersion={#AppVersion}
AppPublisher=Dev-Centr
AppPublisherURL=https://github.com/dev-centr/widget-bench
DefaultDirName={autopf}\Widget Bench
DefaultGroupName=Widget Bench
DisableProgramGroupPage=yes
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#OutputDir}
OutputBaseFilename=WidgetBench-{#AppVersion}-windows-{#Arch}-setup
SetupIconFile=..\icons\app_icon.ico
UninstallDisplayIcon={app}\widget_bench.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
LicenseFile=..\..\LICENSE
#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Widget Bench"; Filename: "{app}\widget_bench.exe"
Name: "{autodesktop}\Widget Bench"; Filename: "{app}\widget_bench.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\widget_bench.exe"; Description: "{cm:LaunchProgram,Widget Bench}"; Flags: nowait postinstall skipifsilent
