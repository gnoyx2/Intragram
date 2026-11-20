# Intragram DMG 창 배치 (dmgbuild 1.6.7 설정 파일). release.yml이
#   dmgbuild -s macos/packaging/dmg_settings.py -D app=<Intragram.app> -D background=<tiff> Intragram <out.dmg>
# 로 부름. Finder를 조작하지 않고 .DS_Store를 직접 써서 CI에서도 같은 창이 나옴.
# 아이콘 중심 좌표는 dmg-background.png의 빈 자리(앱 180,200 · Applications 480,200)와 맞아야 함
import os.path

application = defines["app"]  # noqa: F821 (dmgbuild가 -D 값을 넣어 줌)
appname = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}
hide_extension = [appname]
icon_locations = {appname: (180, 200), "Applications": (480, 200)}

# 마운트된 볼륨에도 앱 아이콘을 씀
volume_icon = os.path.join(application, "Contents/Resources/AppIcon.icns")
if os.path.exists(volume_icon):
    icon = volume_icon

background = defines["background"]  # noqa: F821
# 창 높이 494 = 제목 막대(약 28) + 탭 막대(38) + 경로 막대(28)를 켜 둔 Finder에서도 배경 400이 다 보이는 높이.
# 막대가 없으면 배경이 470까지 보임 (배경 이미지는 660x470, 아래 70은 그라데이션만)
window_rect = ((200, 120), (660, 494))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
