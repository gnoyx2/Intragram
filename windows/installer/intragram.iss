; Intragram Windows 설치 프로그램 (Inno Setup 6.6+). release.yml이 flutter build windows Release 폴더로 만듦
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
; 시작 -> 설치 옵션 -> 설치 중 -> 완료 4단계 마법사로 구성
DisableWelcomePage=no
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
ShowLanguageDialog=no
LanguageDetectionMethod=uilanguage
WizardStyle=modern
WizardImageFile=wizard-welcome.png,wizard-welcome@150.png,wizard-welcome@200.png
WizardImageStretch=yes
WizardImageBackColor=#525f7a
WizardSmallImageFile=wizard-small.png,wizard-small@150.png,wizard-small@200.png
WizardSmallImageBackColor=white
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\intragram.exe
UninstallDisplayName=Intragram
OutputBaseFilename=intragram-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "ko"; MessagesFile: "compiler:Languages\Korean.isl"

[Messages]
en.SetupWindowTitle=Intragram {#AppVersion} Setup
ko.SetupWindowTitle=Intragram {#AppVersion} 설치
en.WelcomeLabel1=Welcome to Intragram Setup
ko.WelcomeLabel1=Intragram 설치를 시작합니다
en.WelcomeLabel2=This wizard will install Intragram {#AppVersion} on your computer.%n%nChat and share files directly over your local Wi-Fi or wired LAN with no cloud server.%n%n• Installs for your account without administrator rights.%n• Remove anytime from Windows Settings › Apps.
ko.WelcomeLabel2=이 마법사는 내 컴퓨터에 Intragram {#AppVersion}을(를) 설치합니다.%n%n같은 Wi-Fi 또는 유선 LAN에 있는 기기끼리 서버 없이 바로 대화하고 파일을 주고받을 수 있습니다.%n%n• 관리자 권한 없이 현재 사용자 계정에 설치됩니다.%n• Windows 설정 › 앱에서 언제든 제거할 수 있습니다.
en.WizardSelectTasks=Installation Options
ko.WizardSelectTasks=설치 옵션
en.SelectTasksDesc=Choose optional shortcuts and review installation details.
ko.SelectTasksDesc=추가 바로 가기를 선택하고 설치 정보를 확인하세요.
en.SelectTasksLabel2=Select the additional options you want, then click Install:
ko.SelectTasksLabel2=원하는 추가 옵션을 선택한 뒤 [설치]를 클릭하세요:
en.WizardInstalling=Installing Intragram
ko.WizardInstalling=Intragram 설치 중
en.InstallingLabel=Please wait while Intragram {#AppVersion} is installed on your computer.
ko.InstallingLabel=잠시만 기다려 주세요. Intragram {#AppVersion}을(를) 컴퓨터에 설치하고 있습니다.
en.FinishedHeadingLabel=Intragram is ready to use
ko.FinishedHeadingLabel=Intragram 설치가 완료되었습니다
en.FinishedLabel=Intragram {#AppVersion} has been installed on your computer.%n%nOpen the app to automatically discover devices on your local network.
ko.FinishedLabel=Intragram {#AppVersion}이(가) 컴퓨터에 성공적으로 설치되었습니다.%n%n앱을 실행하면 같은 네트워크에 연결된 기기를 자동으로 찾을 수 있습니다.
en.FinishedLabelNoIcons=Intragram {#AppVersion} has been installed on your computer.%n%nOpen the app to automatically discover devices on your local network.
ko.FinishedLabelNoIcons=Intragram {#AppVersion}이(가) 컴퓨터에 성공적으로 설치되었습니다.%n%n앱을 실행하면 같은 네트워크에 연결된 기기를 자동으로 찾을 수 있습니다.

[CustomMessages]
en.WelcomeFooter=Version {#AppVersion} · Windows x64
ko.WelcomeFooter=버전 {#AppVersion} · Windows x64
en.InstallButton=&Install
ko.InstallButton=설치(&I)
en.SummaryHeading=Installation summary
ko.SummaryHeading=설치 정보
en.SummaryPathLabel=Location
ko.SummaryPathLabel=설치 위치
en.SummaryScopeLabel=Scope
ko.SummaryScopeLabel=설치 범위
en.SummaryScopeUser=Current user (no administrator rights required)
ko.SummaryScopeUser=현재 사용자 (관리자 권한 불필요)
en.SummaryScopeAll=All users (/ALLUSERS)
ko.SummaryScopeAll=모든 사용자 (/ALLUSERS)
en.SummaryExtrasLabel=Includes
ko.SummaryExtrasLabel=포함 항목
en.SummaryExtrasValue=Start menu shortcut · Removable in Settings › Apps
ko.SummaryExtrasValue=시작 메뉴 바로 가기 · 설정 › 앱에서 제거 가능
en.InstallingFootnote=No administrator rights needed · Removable anytime in Settings › Apps
ko.InstallingFootnote=관리자 권한 없이 내 계정에 설치됩니다 · 설정 › 앱에서 언제든 제거 가능

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; 설치 중·완료 화면용 브랜드 그래픽(설치 폴더에는 복사하지 않고 임시 폴더에서만 읽음)
Source: "wizard-finish.png"; Flags: dontcopy
Source: "wizard-finish@150.png"; Flags: dontcopy
Source: "wizard-finish@200.png"; Flags: dontcopy
Source: "wizard-installing.png"; Flags: dontcopy
Source: "wizard-installing@150.png"; Flags: dontcopy
Source: "wizard-installing@200.png"; Flags: dontcopy

[Icons]
Name: "{autoprograms}\Intragram"; Filename: "{app}\intragram.exe"
Name: "{autodesktop}\Intragram"; Filename: "{app}\intragram.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\intragram.exe"; Description: "{cm:LaunchProgram,Intragram}"; Flags: nowait postinstall skipifsilent

[Code]
var
  SummaryPathValueLabel: TLabel;
  SummaryScopeValueLabel: TLabel;

function PickDpiAsset(const BaseName: String): String;
begin
  if ScaleX(100) >= 175 then
    Result := BaseName + '@200.png'
  else if ScaleX(100) >= 125 then
    Result := BaseName + '@150.png'
  else
    Result := BaseName + '.png';
end;

procedure AddSummaryRow(Parent: TWinControl; TopPos, RowHeight: Integer;
  const KeyText, ValueText: String; out ValueCtrl: TLabel);
var
  KeyLabel: TLabel;
begin
  KeyLabel := TLabel.Create(WizardForm);
  KeyLabel.Parent := Parent;
  KeyLabel.AutoSize := False;
  KeyLabel.Transparent := True;
  KeyLabel.Left := ScaleX(18);
  KeyLabel.Top := TopPos;
  KeyLabel.Width := ScaleX(82);
  KeyLabel.Height := ScaleY(20);
  KeyLabel.Font.Style := [fsBold];
  KeyLabel.Font.Color := $00756052; { #526075 }
  KeyLabel.Caption := KeyText;

  ValueCtrl := TLabel.Create(WizardForm);
  ValueCtrl.Parent := Parent;
  ValueCtrl.AutoSize := False;
  ValueCtrl.Transparent := True;
  ValueCtrl.ShowAccelChar := False;
  ValueCtrl.Left := ScaleX(104);
  ValueCtrl.Top := TopPos;
  ValueCtrl.Width := Parent.Width - ScaleX(120);
  ValueCtrl.Height := RowHeight;
  ValueCtrl.Font.Color := $00241B16; { #161b24 }
  ValueCtrl.WordWrap := True;
  ValueCtrl.Caption := ValueText;
end;

procedure BuildTasksSummaryCard();
var
  BorderPanel: TPanel;
  CardPanel: TPanel;
  AccentBar: TPanel;
  HeadingLabel: TLabel;
  ExtrasValueLabel: TLabel;
  CardTop: Integer;
begin
  WizardForm.TasksList.Height := ScaleY(84);
  CardTop := WizardForm.TasksList.Top + WizardForm.TasksList.Height + ScaleY(14);

  BorderPanel := TPanel.Create(WizardForm);
  BorderPanel.Parent := WizardForm.SelectTasksPage;
  BorderPanel.Left := 0;
  BorderPanel.Top := CardTop;
  BorderPanel.Width := WizardForm.SelectTasksPage.Width;
  BorderPanel.Height := ScaleY(138);
  BorderPanel.BevelOuter := bvNone;
  BorderPanel.Color := $00E6DBD3; { #d3dbe6 }
  BorderPanel.ParentBackground := False;

  CardPanel := TPanel.Create(WizardForm);
  CardPanel.Parent := BorderPanel;
  CardPanel.Left := 1;
  CardPanel.Top := 1;
  CardPanel.Width := BorderPanel.Width - 2;
  CardPanel.Height := BorderPanel.Height - 2;
  CardPanel.BevelOuter := bvNone;
  CardPanel.Color := $00F8F6F5; { #f5f6f8 }
  CardPanel.ParentBackground := False;

  AccentBar := TPanel.Create(WizardForm);
  AccentBar.Parent := CardPanel;
  AccentBar.Left := 0;
  AccentBar.Top := 0;
  AccentBar.Width := ScaleX(4);
  AccentBar.Height := CardPanel.Height;
  AccentBar.BevelOuter := bvNone;
  AccentBar.Color := $0082675A; { #5a6782 }
  AccentBar.ParentBackground := False;

  HeadingLabel := TLabel.Create(WizardForm);
  HeadingLabel.Parent := CardPanel;
  HeadingLabel.AutoSize := False;
  HeadingLabel.Transparent := True;
  HeadingLabel.Left := ScaleX(18);
  HeadingLabel.Top := ScaleY(14);
  HeadingLabel.Width := CardPanel.Width - ScaleX(34);
  HeadingLabel.Height := ScaleY(20);
  HeadingLabel.Font.Style := [fsBold];
  HeadingLabel.Font.Color := $00241B16; { #161b24 }
  HeadingLabel.Caption := ExpandConstant('{cm:SummaryHeading}');

  AddSummaryRow(CardPanel, ScaleY(44), ScaleY(22),
    ExpandConstant('{cm:SummaryPathLabel}'), '', SummaryPathValueLabel);
  AddSummaryRow(CardPanel, ScaleY(74), ScaleY(22),
    ExpandConstant('{cm:SummaryScopeLabel}'), '', SummaryScopeValueLabel);
  AddSummaryRow(CardPanel, ScaleY(104), ScaleY(22),
    ExpandConstant('{cm:SummaryExtrasLabel}'),
    ExpandConstant('{cm:SummaryExtrasValue}'), ExtrasValueLabel);
end;

procedure BuildInstallingArtwork();
var
  AssetName: String;
  Banner: TBitmapImage;
  Footnote: TNewStaticText;
begin
  AssetName := PickDpiAsset('wizard-installing');
  ExtractTemporaryFile(AssetName);

  Banner := TBitmapImage.Create(WizardForm);
  Banner.Parent := WizardForm.InstallingPage;
  Banner.Left := 0;
  Banner.Top := 0;
  Banner.Width := WizardForm.InstallingPage.Width;
  Banner.Height := ScaleY(168);
  Banner.Stretch := True;
  Banner.BackColor := WizardForm.InnerPage.Color;
  Banner.PngImage.LoadFromFile(ExpandConstant('{tmp}\') + AssetName);

  WizardForm.StatusLabel.Top := ScaleY(184);
  WizardForm.StatusLabel.Font.Style := [fsBold];
  WizardForm.StatusLabel.Font.Color := $00241B16; { #161b24 }

  WizardForm.ProgressGauge.Top := ScaleY(208);
  WizardForm.ProgressGauge.Height := ScaleY(22);

  WizardForm.FilenameLabel.Top := ScaleY(240);
  WizardForm.FilenameLabel.Font.Color := $00756052; { #526075 }

  Footnote := TNewStaticText.Create(WizardForm);
  Footnote.Parent := WizardForm.InstallingPage;
  Footnote.Left := 0;
  Footnote.Top := ScaleY(274);
  Footnote.Width := WizardForm.InstallingPage.Width;
  Footnote.Font.Color := $008E786B; { #6b788e }
  Footnote.Caption := ExpandConstant('{cm:InstallingFootnote}');
end;

procedure InitializeWizard();
var
  FinishAsset: String;
  WelcomeFooter: TNewStaticText;
  FinishFooter: TNewStaticText;
begin
  { 시작/완료 화면 제목과 본문 대비를 또렷하게 정리 }
  WizardForm.WelcomeLabel1.Font.Color := $00241B16; { #161b24 }
  WizardForm.WelcomeLabel2.Font.Color := $0058463B; { #3b4658 }
  WizardForm.FinishedHeadingLabel.Font.Color := $00241B16; { #161b24 }
  WizardForm.FinishedLabel.Font.Color := $0058463B; { #3b4658 }

  WelcomeFooter := TNewStaticText.Create(WizardForm);
  WelcomeFooter.Parent := WizardForm.WelcomePage;
  WelcomeFooter.Left := WizardForm.WelcomeLabel2.Left;
  WelcomeFooter.Top := WizardForm.WelcomePage.Height - ScaleY(28);
  WelcomeFooter.Width := WizardForm.WelcomeLabel2.Width;
  WelcomeFooter.Font.Color := $008E786B; { #6b788e }
  WelcomeFooter.Caption := ExpandConstant('{cm:WelcomeFooter}');

  FinishFooter := TNewStaticText.Create(WizardForm);
  FinishFooter.Parent := WizardForm.FinishedPage;
  FinishFooter.Left := WizardForm.FinishedLabel.Left;
  FinishFooter.Top := WizardForm.FinishedPage.Height - ScaleY(28);
  FinishFooter.Width := WizardForm.FinishedLabel.Width;
  FinishFooter.Font.Color := $008E786B; { #6b788e }
  FinishFooter.Caption := ExpandConstant('{cm:WelcomeFooter}');

  { 완료 화면에는 별도의 완료 축하 사이드바 그래픽을 적용 }
  FinishAsset := PickDpiAsset('wizard-finish');
  ExtractTemporaryFile(FinishAsset);
  WizardForm.WizardBitmapImage2.PngImage.LoadFromFile(
    ExpandConstant('{tmp}\') + FinishAsset);

  BuildTasksSummaryCard();
  BuildInstallingArtwork();
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpSelectTasks then begin
    { DisableReadyPage=yes일 때 바로 설치로 넘어가므로 버튼 이름을 명확히 표시 }
    WizardForm.NextButton.Caption := ExpandConstant('{cm:InstallButton}');
    SummaryPathValueLabel.Caption := MinimizePathName(
      WizardDirValue, SummaryPathValueLabel.Font, SummaryPathValueLabel.Width);
    if IsAdminInstallMode then
      SummaryScopeValueLabel.Caption := ExpandConstant('{cm:SummaryScopeAll}')
    else
      SummaryScopeValueLabel.Caption := ExpandConstant('{cm:SummaryScopeUser}');
  end else if CurPageID = wpFinished then begin
    WizardForm.RunList.Top :=
      WizardForm.FinishedLabel.Top + WizardForm.FinishedLabel.Height + ScaleY(22);
  end;
end;
