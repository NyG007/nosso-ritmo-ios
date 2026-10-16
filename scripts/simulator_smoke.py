"""Boot an available iPhone, launch demo in all themes and save real simulator screenshots."""
from pathlib import Path
import json
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
app = ROOT / 'build/DerivedData/Build/Products/Debug-iphonesimulator/NossoRitmo.app'
assert app.is_dir(), 'Build the app before running simulator smoke.'

def run(*args):
    return subprocess.check_output(args, text=True).strip()

devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))['devices']
phones = [d for entries in devices.values() for d in entries if d['name'].startswith('iPhone')]
assert phones, 'No iPhone simulator is installed.'
phone = next((d for d in phones if d['state'] == 'Booted'), phones[0])
device = phone['udid']
if phone['state'] != 'Booted':
    run('xcrun', 'simctl', 'boot', device)
run('xcrun', 'simctl', 'bootstatus', device, '-b')
run('xcrun', 'simctl', 'status_bar', device, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100')
run('xcrun', 'simctl', 'install', device, str(app))
output = ROOT / 'build/screenshots'
output.mkdir(parents=True, exist_ok=True)
for theme in ['light', 'dark', 'pink']:
    subprocess.run(['xcrun', 'simctl', 'terminate', device, 'com.nyg007.nossoritmo'], capture_output=True)
    run('xcrun', 'simctl', 'launch', device, 'com.nyg007.nossoritmo', '-storageMode', 'demo', '-theme', theme)
    time.sleep(8)
    # UI capture for review; launch success alone does not verify the visual result.
    run('xcrun', 'simctl', 'io', device, 'screenshot', str(output / f'today-{theme}.png'))
print(f'Captured light, dark and pink on {phone["name"]}. Review screenshot artifacts.')
