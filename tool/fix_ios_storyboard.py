#!/usr/bin/env python3
"""Restore Main.storyboard (the scene's root FlutterViewController) into FinFlow.

The earlier storyboard-free migration left the scene config without a root
view controller, so the app shows a blank window and Dart never starts on
iOS/simulator. This restores the standard Flutter wiring while keeping the
branded UILaunchScreen colour.
"""

import os
import re
import shutil

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RUNNER = os.path.join(ROOT, "ios", "Runner")
PBX = os.path.join(ROOT, "ios", "Runner.xcodeproj", "project.pbxproj")
PLIST = os.path.join(RUNNER, "Info.plist")
STOCK = "/tmp/stockapp/ios/Runner/Base.lproj/Main.storyboard"

# 1. Copy the storyboard into Base.lproj
dst = os.path.join(RUNNER, "Base.lproj", "Main.storyboard")
os.makedirs(os.path.dirname(dst), exist_ok=True)
shutil.copy(STOCK, dst)
print("copied Main.storyboard")

# 2. Patch project.pbxproj
with open(PBX) as f:
    pbx = f.read()

build_file = '\t\t97C146FC1CF9000F007C117D /* Main.storyboard in Resources */ = {isa = PBXBuildFile; fileRef = 97C146FA1CF9000F007C117D /* Main.storyboard */; };'
file_ref = '\t\t97C146FB1CF9000F007C117D /* Base */ = {isa = PBXFileReference; lastKnownFileType = file.storyboard; name = Base; path = Base.lproj/Main.storyboard; sourceTree = "<group>"; };'
variant = '''/* Begin PBXVariantGroup section */
		97C146FA1CF9000F007C117D /* Main.storyboard */ = {
			isa = PBXVariantGroup;
			children = (
				97C146FB1CF9000F007C117D /* Base */,
			);
			name = Main.storyboard;
			sourceTree = "<group>";
		};
/* End PBXVariantGroup section */'''

checks = []

def patch(text, pattern, repl, label, required=True):
    if not re.search(pattern, text, re.MULTILINE):
        checks.append(f"MISSING anchor for {label}")
        return text
    text = re.sub(pattern, repl, text, count=1, flags=re.MULTILINE)
    return text

# PBXBuildFile: insert after Assets.xcassets in Resources
pbx = patch(
    pbx,
    r"(97C146FE1CF9000F007C117D /\* Assets\.xcassets in Resources \*/ = \{isa = PBXBuildFile; fileRef = 97C146FD1CF9000F007C117D /\* Assets\.xcassets \*/; \};)",
    r"\1\n" + build_file,
    "PBXBuildFile",
)

# PBXFileReference: insert after Assets.xcassets file ref
pbx = patch(
    pbx,
    r"(97C146FD1CF9000F007C117D /\* Assets\.xcassets \*/ = \{isa = PBXFileReference; lastKnownFileType = folder\.assetcatalog; path = Assets\.xcassets; sourceTree = \"<group>\"; \};)",
    r"\1\n" + file_ref,
    "PBXFileReference",
)

# Runner group children: after Assets.xcassets,
pbx = patch(
    pbx,
    r"(97C146FD1CF9000F007C117D /\* Assets\.xcassets \*/,)",
    r"\1\n\t\t\t\t97C146FA1CF9000F007C117D /* Main.storyboard */,",
    "group children",
)

# Resources phase: after Assets.xcassets in Resources,
pbx = patch(
    pbx,
    r"(97C146FE1CF9000F007C117D /\* Assets\.xcassets in Resources \*/,)",
    r"\1\n\t\t\t\t97C146FC1CF9000F007C117D /* Main.storyboard in Resources */,",
    "resources phase",
)

# PBXVariantGroup (currently empty)
pbx = patch(
    pbx,
    r"/\* Begin PBXVariantGroup section \*/\n/\* End PBXVariantGroup section \*/",
    variant.replace("\\", "\\\\"),
    "variant group",
)

with open(PBX, "w") as f:
    f.write(pbx)
print("patched project.pbxproj")

# 3. Patch Info.plist: UISceneStoryboardFile + UIMainStoryboardFile
with open(PLIST) as f:
    plist = f.read()

if "<key>UISceneStoryboardFile</key>" not in plist:
    plist = plist.replace(
        "\t\t\t\t\t<key>UISceneDelegateClassName</key>\n\t\t\t\t\t<string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>",
        "\t\t\t\t\t<key>UISceneDelegateClassName</key>\n\t\t\t\t\t<string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>\n\t\t\t\t\t<key>UISceneStoryboardFile</key>\n\t\t\t\t\t<string>Main</string>",
    )
else:
    checks.append("UISceneStoryboardFile already present")

if "<key>UIMainStoryboardFile</key>" not in plist:
    plist = plist.replace(
        "\t<key>UILaunchScreen</key>",
        "\t<key>UIMainStoryboardFile</key>\n\t<string>Main</string>\n\t<key>UILaunchScreen</key>",
    )
else:
    checks.append("UIMainStoryboardFile already present")

with open(PLIST, "w") as f:
    f.write(plist)
print("patched Info.plist")

print("CHECKS:", checks if checks else "all anchors matched")
