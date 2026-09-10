#!/usr/bin/env python3
"""Compile production header controls and tokens in a standalone SwiftUI mockup."""
import pathlib, subprocess, sys, plistlib
source = pathlib.Path(__file__).resolve().parent
root = source.parent.parent
build = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '/private/tmp/rec454-native')
app = build / 'ListHeaderPreview.app'
app.mkdir(parents=True, exist_ok=True)
theme = (root / 'Wander/DesignSystem/WanderTheme.swift').read_text()
astir = (root / 'Wander/DesignSystem/AstirVisualSystem.swift').read_text()
lists = (root / 'Wander/Features/Lists/ListsScreen.swift').read_text()
def part(text, start, end):
    return text[text.index(start):text.index(end)]
shared = '\n'.join([
    'import SwiftUI\nimport UIKit',
    part(theme, 'struct WanderColorToken', 'struct WanderMapAppearance'),
    part(theme, 'private extension Color', 'struct WanderScreenBackground'),
    part(theme, 'struct WanderSegmentOption', 'struct WanderGlassHeader'),
    part(astir, 'enum AstirBrandMode', 'private struct AstirAdaptiveBrandModeModifier'),
    lists[lists.index('// MARK: - List detail header controls'):],
    (source / 'ListHeaderPreview.swift').read_text(),
])
combined = build / 'Preview.swift'
combined.write_text(shared)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
subprocess.run(['xcrun', 'swiftc', '-sdk', sdk, '-target', 'arm64-apple-ios17.0-simulator',
               '-module-cache-path', str(build / 'module-cache'), '-parse-as-library', str(combined),
               '-o', str(app / 'ListHeaderPreview')], check=True)
with (app / 'Info.plist').open('wb') as stream:
    plistlib.dump({'CFBundleIdentifier': 'com.recme.preview.list-header', 'CFBundleName': 'ListHeaderPreview',
                  'CFBundleExecutable': 'ListHeaderPreview', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1',
                  'CFBundleShortVersionString': '1.0', 'MinimumOSVersion': '17.0', 'UIDeviceFamily': [1],
                  'UILaunchScreen': {}}, stream)
print(app)
