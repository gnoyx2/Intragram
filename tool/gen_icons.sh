#!/usr/bin/env bash
# macOS sips·Swift·Dart로 아이콘과 실행 화면 표시를 만듦.
# 원본은 tool/icon_source.png 하나이고, 바꾸면 이 스크립트를 다시 실행함.
# Android 배경색(ic_launcher_background, launch_mark_plate)은 마스터 스크립트가 출력한 배경색과 맞출 것
set -euo pipefail
cd "$(dirname "$0")/.."

swift tool/make_icon_masters.swift tool/icon_source.png build/icon_master
for size in 16 24 32; do
  sips -z "$size" "$size" build/icon_master/master_windows.png \
    --out "build/icon_master/small_$size.png" >/dev/null
done

MASTER=build/icon_master/master_full.png
MASTER_MACOS=build/icon_master/master_macos.png
MASTER_WINDOWS=build/icon_master/master_windows.png
CUTOUT=build/icon_master/cutout.png
FOREGROUND=build/icon_master/foreground.png
MONOCHROME=build/icon_master/monochrome.png
LAUNCH_MARK=build/icon_master/launch_mark.png
NOTIFICATION=build/icon_master/notification.png

SMALL=(build/icon_master/small_16.png build/icon_master/small_24.png build/icon_master/small_32.png)

for f in "$MASTER" "$MASTER_MACOS" "$MASTER_WINDOWS" "$CUTOUT" "$FOREGROUND" "$MONOCHROME" "$LAUNCH_MARK" "$NOTIFICATION" "${SMALL[@]}"; do
  if [ ! -f "$f" ]; then
    echo "Missing $f — check tool/make_icon_masters.swift" >&2
    exit 1
  fi
done

SRGB_PROFILE="/System/Library/ColorSync/Profiles/sRGB Profile.icc"

echo "== sRGB color-match masters =="
for master in "$MASTER" "$MASTER_MACOS" "$MASTER_WINDOWS" "$CUTOUT" "$FOREGROUND" "$MONOCHROME" "$LAUNCH_MARK" "$NOTIFICATION" "${SMALL[@]}"; do
  sips --matchTo "$SRGB_PROFILE" "$master" >/dev/null
done

echo "== Android legacy mipmaps =="
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density=${pair%%:*}; size=${pair##*:}
  sips -z "$size" "$size" "$MASTER" \
    --out "android/app/src/main/res/mipmap-$density/ic_launcher.png" >/dev/null
done

echo "== Android adaptive foreground + monochrome (108dp canvas / density) =="
for pair in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
  density=${pair%%:*}; size=${pair##*:}
  mkdir -p "android/app/src/main/res/mipmap-$density"
  sips -z "$size" "$size" "$FOREGROUND" \
    --out "android/app/src/main/res/mipmap-$density/ic_launcher_foreground.png" >/dev/null
  sips -z "$size" "$size" "$MONOCHROME" \
    --out "android/app/src/main/res/mipmap-$density/ic_launcher_monochrome.png" >/dev/null
done

echo "== Android launch mark =="
for pair in mdpi:200 hdpi:300 xhdpi:400 xxhdpi:600 xxxhdpi:800; do
  density=${pair%%:*}; size=${pair##*:}
  sips -z "$size" "$size" "$LAUNCH_MARK" \
    --out "android/app/src/main/res/mipmap-$density/ic_launch_mark.png" >/dev/null
done

echo "== Android notification small icon (24dp, white silhouette) =="
for pair in mdpi:24 hdpi:36 xhdpi:48 xxhdpi:72 xxxhdpi:96; do
  density=${pair%%:*}; size=${pair##*:}
  mkdir -p "android/app/src/main/res/drawable-$density"
  sips -z "$size" "$size" "$NOTIFICATION" \
    --out "android/app/src/main/res/drawable-$density/ic_stat_intragram.png" >/dev/null
done

echo "== Linux hicolor icons (512 master from macOS plate, 48~256 scaled, 16~32 small mark) =="
# GNOME 앱 아이콘 격자의 판 비율(약 81%)이 macOS 템플릿과 같아서 macOS 마스터를 씀
mkdir -p linux/icons/hicolor/512x512/apps
sips -z 512 512 "$MASTER_MACOS" --out "linux/icons/hicolor/512x512/apps/intragram.png" >/dev/null
for size in 16 24 32; do
  mkdir -p "linux/icons/hicolor/${size}x${size}/apps"
  cp "build/icon_master/small_$size.png" "linux/icons/hicolor/${size}x${size}/apps/intragram.png"
done
for size in 48 64 128 256; do
  mkdir -p "linux/icons/hicolor/${size}x${size}/apps"
  sips -z "$size" "$size" linux/icons/hicolor/512x512/apps/intragram.png \
    --out "linux/icons/hicolor/${size}x${size}/apps/intragram.png" >/dev/null
done

echo "== iOS·macOS Icon Composer layer =="
# Xcode가 AppIcon.icon 하나로 모든 버전의 아이콘을 만듦: 26 이상은 기본·다크·모노(투명·틴트),
# 그 전 버전과 App Store용은 같은 파일에서 만든 대체 이미지. 배경색과 다크 배경색은 각 icon.json에 있음
for dir in ios/Runner/AppIcon.icon macos/Runner/AppIcon.icon; do
  mkdir -p "$dir/Assets"
  cp "$CUTOUT" "$dir/Assets/pigeon.png"
done

echo "== Windows .ico source PNGs + pack =="
# 16~32px는 픽셀 격자에 맞춰 그린 단순 마크를 그대로 쓰고, 48px부터 스퀘어클 판 마스터를 줄임
mkdir -p build/icon_master/windows
for size in 16 24 32; do
  cp "build/icon_master/small_$size.png" "build/icon_master/windows/icon_$size.png"
done
for size in 48 64 128 256; do
  sips -z "$size" "$size" "$MASTER_WINDOWS" \
    --out "build/icon_master/windows/icon_$size.png" >/dev/null
done
dart run tool/pack_ico.dart

echo "== iOS launch mark =="
# 라이트 외형은 둥근 판이 있는 macOS 마스터를, 다크 외형은 원형 실행 화면 마크를 씀
LAUNCH_DIR="ios/Runner/Assets.xcassets/LaunchImage.imageset"
for pair in ":168" "@2x:336" "@3x:504"; do
  suffix=${pair%%:*}; size=${pair##*:}
  sips -z "$size" "$size" "$MASTER_MACOS" --out "$LAUNCH_DIR/LaunchImage$suffix.png" >/dev/null
  sips -z "$size" "$size" "$LAUNCH_MARK" --out "$LAUNCH_DIR/LaunchImageDark$suffix.png" >/dev/null
done

echo "Done."
