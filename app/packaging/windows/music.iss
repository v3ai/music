; Windows installer for music (Inno Setup 6).
; Built in CI: iscc /DAppVersion=1.2.3 /DSourceDir=<release folder> /O<out dir> music.iss
; Installs for the current user only, so it never asks for admin rights.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{5B8E2D4A-7C1F-4E8B-9A3D-6F2C1B0E9D47}
AppName=music
AppVersion={#AppVersion}
AppVerName=music {#AppVersion}
AppPublisher=v3ai
AppPublisherURL=https://v3ai.github.io/music/
AppSupportURL=https://github.com/v3ai/music
DefaultDirName={localappdata}\Programs\music
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=music-windows-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\music.exe
UninstallDisplayName=music
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
CloseApplications=force
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Add a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\music"; Filename: "{app}\music.exe"
Name: "{autodesktop}\music"; Filename: "{app}\music.exe"; Tasks: desktopicon

[Registry]
; v3ai-music:// links, so the website can open the app
Root: HKCU; Subkey: "Software\Classes\v3ai-music"; ValueType: string; ValueData: "URL:music"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\v3ai-music"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\v3ai-music\shell\open\command"; ValueType: string; ValueData: """{app}\music.exe"" ""%1"""

[Run]
Filename: "{app}\music.exe"; Description: "Open music"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
