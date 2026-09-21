; Offline, per-user Fritzing installer.
; Required ISCC defines: MyAppVersion, StageDir, OutputDir

#ifndef MyAppVersion
  #error MyAppVersion is required
#endif
#ifndef StageDir
  #error StageDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif

[Setup]
AppId={{6E045B86-4297-4B67-A30A-899B822C6798}
AppName=Fritzing (Community Windows Build)
AppVersion={#MyAppVersion}
AppVerName=Fritzing {#MyAppVersion} (Community Windows Build)
AppPublisher=Unofficial Fritzing Windows Build
AppPublisherURL=https://github.com/fritzing/fritzing-app
AppSupportURL=https://github.com/fritzing/fritzing-app/issues
DefaultDirName={localappdata}\Programs\Fritzing
DefaultGroupName=Fritzing
LicenseFile={#StageDir}\LICENSE.GPL2
OutputDir={#OutputDir}
OutputBaseFilename=Fritzing-{#MyAppVersion}-Windows-x64-Setup
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\Fritzing.exe
ChangesAssociations=yes
CloseApplications=yes
RestartApplications=no
WizardStyle=modern
SetupLogging=yes

[Tasks]
Name: desktopicon; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: associatefiles; Description: "Associate .fzz and .fzpz files with Fritzing"; GroupDescription: "File associations:"; Flags: unchecked

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Registry]
Root: HKCU; Subkey: "Software\Classes\.fzz"; ValueType: string; ValueData: "FritzingCommunity.Project"; Flags: uninsdeletevalue; Tasks: associatefiles
Root: HKCU; Subkey: "Software\Classes\.fzpz"; ValueType: string; ValueData: "FritzingCommunity.Part"; Flags: uninsdeletevalue; Tasks: associatefiles
Root: HKCU; Subkey: "Software\Classes\FritzingCommunity.Project"; ValueType: string; ValueData: "Fritzing Sketch"; Flags: uninsdeletekey; Tasks: associatefiles
Root: HKCU; Subkey: "Software\Classes\FritzingCommunity.Project\DefaultIcon"; ValueType: string; ValueData: "{app}\Fritzing.exe,0"; Tasks: associatefiles
Root: HKCU; Subkey: "Software\Classes\FritzingCommunity.Project\shell\open\command"; ValueType: string; ValueData: """{app}\Fritzing.exe"" ""%1"""; Tasks: associatefiles
Root: HKCU; Subkey: "Software\Classes\FritzingCommunity.Part"; ValueType: string; ValueData: "Fritzing Part"; Flags: uninsdeletekey; Tasks: associatefiles
Root: HKCU; Subkey: "Software\Classes\FritzingCommunity.Part\DefaultIcon"; ValueType: string; ValueData: "{app}\Fritzing.exe,0"; Tasks: associatefiles
Root: HKCU; Subkey: "Software\Classes\FritzingCommunity.Part\shell\open\command"; ValueType: string; ValueData: """{app}\Fritzing.exe"" ""%1"""; Tasks: associatefiles

[Icons]
Name: "{group}\Fritzing"; Filename: "{app}\Fritzing.exe"
Name: "{autodesktop}\Fritzing"; Filename: "{app}\Fritzing.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Fritzing.exe"; Description: "{cm:LaunchProgram,Fritzing}"; Flags: nowait postinstall skipifsilent

