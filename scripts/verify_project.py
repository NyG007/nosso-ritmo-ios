"""Cross-platform structural checks; these do not replace xcodebuild or device tests."""
from pathlib import Path
import json
import plistlib
import re
import struct
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
project = (root / 'NossoRitmo.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
definitions = re.findall(r'^([A-F0-9]{24}) = ', project, re.M)
assert len(definitions) == len(set(definitions)), 'Duplicate project object IDs'
references = set(re.findall(r'\b[A-F0-9]{24}\b', project))
assert references == set(definitions), f'Unresolved project IDs: {references-set(definitions)}'
for path in re.findall(r'path = "([^"$]+)"; sourceTree = SOURCE_ROOT;', project):
    assert (root/path).exists(), f'Missing project input {path}'
for path in (root / 'Config').glob('*'):
    if path.suffix in ('.plist', '.entitlements'):
        with path.open('rb') as f:
            plistlib.load(f)
for path in root.rglob('*.xcscheme'):
    ET.parse(path)
for path in (root / 'App/Assets.xcassets').rglob('*.json'):
    json.loads(path.read_text())
icon = (root/'App/Assets.xcassets/AppIcon.appiconset/AppIcon.png').read_bytes()
assert icon[:8] == b'\x89PNG\r\n\x1a\n'
assert struct.unpack('>II',icon[16:24]) == (1024,1024)
assert icon[25] == 2, 'App icon must be RGB without alpha'
assert 'EventKit' not in '\n'.join(p.read_text(encoding='utf-8') for p in (root/'App').glob('*.swift'))
assert 'com.apple.widgetkit-extension' in (root/'Config/Widget-Info.plist').read_text()
assert 'CKSharingSupported' in (root/'Config/App-Info.plist').read_text()
print(f'OK: {len(definitions)} project objects; plists, entitlements, scheme, assets and references valid.')
