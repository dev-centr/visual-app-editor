; Inno Setup script for Visual App Editor.
; Invoked by build-installer.ps1:  ISCC /DAppVersion=0.1.0 /DArch=x64 /DSourceDir=... visual_app_editor.iss
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
AppName=Visual App Editor
AppVersion={#AppVersion}
AppPublisher=Dev-Centr
AppPublisherURL=https://github.com/dev-centr/visual-app-editor
DefaultDirName={autopf}\Visual App Editor
DefaultGroupName=Visual App Editor
DisableProgramGroupPage=yes
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#OutputDir}
OutputBaseFilename=VisualAppEditor-{#AppVersion}-windows-{#Arch}-setup
SetupIconFile=..\icons\app_icon.ico
UninstallDisplayIcon={app}\visual_app_editor.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
LicenseFile=..\..\..\..\LICENSE
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
Name: "{autoprograms}\Visual App Editor"; Filename: "{app}\visual_app_editor.exe"
Name: "{autodesktop}\Visual App Editor"; Filename: "{app}\visual_app_editor.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\visual_app_editor.exe"; Description: "{cm:LaunchProgram,Visual App Editor}"; Flags: nowait postinstall skipifsilent
