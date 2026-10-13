#!/bin/sh
set -eu
APP="dist/方块世界.app"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
swiftc -O -module-cache-path "$PWD/.cache/clang" -parse-as-library Sources/WorldBuilder/WorldBuilderApp.swift -o "$APP/Contents/MacOS/WorldBuilder"
cp "Worlds/三层小楼.world.json" "$APP/Contents/Resources/三层小楼.world.json"
cp "Worlds/小庭院.world.json" "$APP/Contents/Resources/小庭院.world.json"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>方块世界</string>
<key>CFBundleDisplayName</key><string>方块世界</string>
<key>CFBundleIdentifier</key><string>com.example.worldbuilder</string>
<key>CFBundleExecutable</key><string>WorldBuilder</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP"
echo "Created $APP"
