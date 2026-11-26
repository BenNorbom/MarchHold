; Inno Setup script for MarchHold. Build with tools/build.ps1 (or: ISCC.exe installer\MarchHold.iss).
#ifndef AppVersion
  #define AppVersion "0.7.0"
#endif

[Setup]
AppId={{8B2F6A1C-5D3E-4F7A-9C21-6E4B2D8A9F13}
AppName=MarchHold
AppVersion={#AppVersion}
AppVerName=MarchHold {#AppVersion}
AppPublisher=MarchHold
AppPublisherURL=https://github.com/BenNorbom/MarchHold
AppSupportURL=https://github.com/BenNorbom/MarchHold/issues
DefaultDirName={autopf}\MarchHold
DefaultGroupName=MarchHold
DisableProgramGroupPage=yes
; Installs for the current user without an admin prompt; admins can choose all users.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist
OutputBaseFilename=MarchHold-Setup-{#AppVersion}
SetupIconFile=..\icon.ico
UninstallDisplayIcon={app}\MarchHold.exe
UninstallDisplayName=MarchHold
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\MarchHold.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSES\*"; DestDir: "{app}\licenses"; Flags: ignoreversion recursesubdirs
Source: "..\README.md"; DestDir: "{app}"; DestName: "README.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\MarchHold"; Filename: "{app}\MarchHold.exe"
Name: "{autodesktop}\MarchHold"; Filename: "{app}\MarchHold.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\MarchHold.exe"; Description: "{cm:LaunchProgram,MarchHold}"; Flags: nowait postinstall skipifsilent
