from pathlib import Path
import argparse, json, os, subprocess
root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--staging', action='store_true')
parser.add_argument('--seconds', type=float, default=36)
arguments = parser.parse_args()
if arguments.staging:
    (root / 'native-captures' / 'staging').mkdir(exist_ok=True)
for option in json.loads((root / "opening-options.json").read_text())["takes"]:
    env = os.environ.copy()
    env["SIMCTL_CHILD_WANDER_ONBOARDING_TICKER_WORDS"] = json.dumps(option["words"])
    env["SIMCTL_CHILD_WANDER_ONBOARDING_TICKER_DESCRIPTION"] = option["description"]
    env["SIMCTL_CHILD_WANDER_ONBOARDING_TICKER_FINAL"] = option["finalLockup"]
    env["SIMCTL_CHILD_WANDER_ONBOARDING_DELAY_DESCRIPTION"] = "1" if option["delayed"] else "0"
    filename = ('staging/' if arguments.staging else '') + f"opening-{option['id'].lower()}.mp4"
    subprocess.run(["python3", str(root / "record_native.py"), "W00", filename, "--seconds", str(arguments.seconds)], env=env, check=True)
    print("Native opening ready:", option["id"], flush=True)
