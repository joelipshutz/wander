#!/usr/bin/env python3
"""Build the native approval app with production tokens and glass implementations."""
import pathlib, subprocess, sys, plistlib, shutil
source = pathlib.Path(__file__).resolve().parent
root = source.parent.parent
build = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '/private/tmp/rec460-native')
app = build / 'GlassApprovalPreview.app'
app.mkdir(parents=True, exist_ok=True)
theme = (root / 'Wander/DesignSystem/WanderTheme.swift').read_text()
astir = (root / 'Wander/DesignSystem/AstirVisualSystem.swift').read_text()
place = (root / 'Wander/Features/Map/PlaceProfileMapSurface.swift').read_text()
def part(text, start, end):
    return text[text.index(start):text.index(end)]
shared = '\n'.join([
    'import SwiftUI\nimport UIKit',
    part(theme, 'struct WanderColorToken', 'struct WanderMapAppearance'),
    part(theme, 'private extension Color', 'struct WanderScreenBackground'),
    part(theme, 'struct WanderSegmentOption', 'struct WanderGlassHeader'),
    part(astir, 'enum AstirBrandMode', 'private struct AstirAdaptiveBrandModeModifier'),
    part(astir, 'struct AstirMastheadLockup', 'enum AstirFloatingHeaderBehavior'),
    part(astir, 'struct AstirIconActionButton', 'struct AstirPlacePhotoAsset'),
    part(place, 'private enum PlaceCardPreviewAction', 'private struct PlaceCardRatingDistanceRow'),
    (source / 'GlassApprovalPreview.swift').read_text(),
])
combined = build / 'Preview.swift'
combined.write_text(shared)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
subprocess.run(['xcrun', 'swiftc', '-sdk', sdk, '-target', 'arm64-apple-ios17.0-simulator',
                '-module-cache-path', str(build / 'module-cache'), '-parse-as-library', str(combined),
                '-o', str(app / 'GlassApprovalPreview')], check=True)
with (app / 'Info.plist').open('wb') as stream:
    plistlib.dump({'CFBundleIdentifier': 'com.recme.preview.terracotta-glass', 'CFBundleName': 'GlassApprovalPreview',
                  'CFBundleExecutable': 'GlassApprovalPreview', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1',
                  'CFBundleShortVersionString': '1.0', 'MinimumOSVersion': '17.0', 'UIDeviceFamily': [1],
                  'UILaunchScreen': {}}, stream)
shutil.copyfile(root / 'Wander/Resources/Assets.xcassets/PlaceCarouselPhotos.imageset/place-carousel-photos.png', app / 'places.png')
print(app)
