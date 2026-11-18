; Intragram Windows 설치 프로그램 (Inno Setup 6.3+). release.yml이 flutter build windows Release 폴더로 만듦
; 사용자 단위 설치: 관리자 권한·UAC 없이 %LOCALAPPDATA%\Programs\Intragram에 깔리고 설정 > 앱에서 지움
; AppId는 절대 바꾸지 않음: 바뀌면 기존 설치를 업데이트하지 못하고 두 번째 사본이 깔림

#ifndef SourceDir
  #error Pass /DSourceDir=<build\windows\x64\runner\Release>
#endif
#ifndef AppVersion
  #error Pass /DAppVersion=<x.y.z>
#endif
#ifndef FileVersion
  #error Pass /DFileVersion=<x.y.z.build>
#endif

[Setup]
AppId={{2EA84494-9B4A-48D2-93CC-3A08EED7E51A}
AppName=Intragram
AppVersion={#AppVersion}
AppPublisher=Intragram contributors
AppPublisherURL=https://github.com/gnoyx2/Intragram
AppSupportURL=https://github.com/gnoyx2/Intragram/issues
AppUpdatesURL=https://github.com/gnoyx2/Intragram/releases
VersionInfoVersion={#FileVersion}
DefaultDirName={autopf}\Intragram
PrivilegesRequired=lowest
; 관리자는 /ALLUSERS로 모든 사용자에게 설치할 수 있음
PrivilegesRequiredOverridesAllowed=commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; 화면은 추가 작업(바탕화면 아이콘) 한 장과 완료(바로 실행) 한 장만 남김
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
ShowLanguageDialog=no
LanguageDetectionMethod=uilanguage
WizardStyle=modern
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\intragram.exe
UninstallDisplayName=Intragram
OutputBaseFilename=intragram-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "ko"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Intragram"; Filename: "{app}\intragram.exe"
Name: "{autodesktop}\Intragram"; Filename: "{app}\intragram.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\intragram.exe"; Description: "{cm:LaunchProgram,Intragram}"; Flags: nowait postinstall skipifsilent
