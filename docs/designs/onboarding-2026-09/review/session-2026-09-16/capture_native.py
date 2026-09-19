"""Capture production Swift screens from the dedicated review simulator."""
from pathlib import Path
import argparse, json, os, subprocess, time

ROOT = Path(__file__).resolve().parent
DEVICE = '3634A858-7A50-4EC3-8C21-56E6B16A6985'
APP = 'com.grayline.wander'
ROUTES = {
    'W00': ('welcome', {'WANDER_ONBOARDING_PAUSED': '1'}),
    'W01': ('welcome', {'WANDER_ONBOARDING_PAUSED': '1', 'WANDER_ONBOARDING_START_STEP': 'places'}),
    'W02': ('welcome', {'WANDER_ONBOARDING_PAUSED': '1', 'WANDER_ONBOARDING_START_STEP': 'people'}),
    'N04': ('signup', {}), 'N06': ('login', {}), 'N08': ('identity', {}),
    'N09': ('location', {}), 'N10': ('contacts', {}), 'N11': ('friends', {}),
    'N12': ('notifications', {}),
    'N33': ('friends-empty', {}), 'N34': ('friends-failure', {}),
}
TARGETS = {
    'M01': 'mapFeatured', 'M02': 'mapFriends', 'M03': 'mapMoreFilters',
    'M04': 'mapSearch', 'M05': 'mapAdd', 'M06': 'mapPinLegend', 'N25': 'mapSendoff',
    'C01': 'addImport', 'C02': 'feedActivity', 'C03': 'listsScope', 'C04': 'placeActions',
}

def run(*args, check=True, env=None):
    return subprocess.run(['xcrun', 'simctl', *args], check=check, capture_output=True, text=True, env=env)

def launch(screen, device=DEVICE, hold=True):
    run('terminate', device, APP, check=False)
    environment = os.environ.copy()
    if screen in ROUTES:
        route, values = ROUTES[screen]
        if not hold: values = {k: v for k, v in values.items() if k != 'WANDER_ONBOARDING_PAUSED'}
        environment.update({'SIMCTL_CHILD_' + k: v for k, v in values.items()})
        arguments = ['-WanderNativeOnboardingReview', route, '-WanderUseDemoFixtures']
        if screen == 'N12': arguments.append('-WanderBypassProductUpsellFrequencyCap')
    elif screen in TARGETS:
        arguments = ['-WanderAuthenticatedUITest', '-WanderMapCapture', '-WanderUseDemoFixtures',
                     '-WanderEnableWalkthroughs', '-WanderResetWalkthroughs',
                     '-WanderWalkthroughTarget', TARGETS[screen]]
        if hold: arguments.append('-WanderHoldWalkthroughStep')
        if screen == 'M03': arguments += ['-WanderMapCaptureMode', 'friends']
        if screen == 'C04': arguments += ['-WanderMapPlace', 'Bar Nido', '-WanderMapSheetExpanded']
    elif screen == 'N27':
        arguments = ['-WanderAuthenticatedUITest', '-WanderMapCapture', '-WanderUseDemoFixtures',
                     '-WanderEnableWalkthroughs', '-WanderShowDeviceFeaturesWalkthrough',
                     '-WanderHoldWalkthroughStep']
    elif screen in ('N28', 'N29'):
        arguments = ['-WanderAuthenticatedUITest', '-WanderUseDemoFixtures',
                     '-WanderDisableWalkthroughs', '-WanderBypassProductUpsellFrequencyCap',
                     '-WanderProductUpsellTrigger', 'place_saved' if screen == 'N28' else 'follow_created']
    else:
        raise ValueError(screen)
    result = run('launch', device, APP, *arguments, env=environment)
    return arguments

def capture(screen, device=DEVICE, wait=6):
    args = launch(screen, device)
    time.sleep(wait)
    directory = ROOT / 'native-captures'
    directory.mkdir(exist_ok=True)
    filename = f'{screen}.png' if device == DEVICE else f'{screen}-compact.png'
    run('io', device, 'screenshot', str(directory / filename))
    record = {'screen': screen, 'file': filename, 'device': device, 'arguments': args,
              'captured_at': time.strftime('%Y-%m-%dT%H:%M:%S%z')}
    with (directory / 'capture-log.jsonl').open('a') as stream:
        stream.write(json.dumps(record) + '\n')
    print(f'Captured {screen}: {filename}', flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('screens', nargs='+')
    parser.add_argument('--device', default=DEVICE)
    parser.add_argument('--wait', type=float, default=6)
    parser.add_argument('--launch-only', action='store_true')
    parser.add_argument('--play', action='store_true')
    options = parser.parse_args()
    for screen in options.screens:
        if options.launch_only:
            launch(screen, options.device, hold=not options.play)
            print('Launched', screen, flush=True)
        else:
            capture(screen, options.device, options.wait)
