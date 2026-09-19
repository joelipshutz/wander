"""Start the loopback review server independently of an interactive tool session."""
from pathlib import Path
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
PORT = 8766


def listening():
    try:
        with socket.create_connection(("127.0.0.1", PORT), timeout=0.3):
            return True
    except OSError:
        return False


if listening():
    print(f"Review server already available at http://127.0.0.1:{PORT}/")
    sys.exit(0)

with (ROOT / "review-server.log").open("ab") as log:
    process = subprocess.Popen(
        [sys.executable, str(ROOT / "serve_review.py"), "--port", str(PORT)],
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        stdout=log,
        stderr=log,
        start_new_session=True,
        close_fds=True,
    )

for _ in range(30):
    if process.poll() is not None:
        sys.exit("Review server stopped during startup; see review-server.log.")
    if listening():
        (ROOT / "review-server.pid").write_text(str(process.pid) + "\n")
        print(f"Review server available at http://127.0.0.1:{PORT}/ (PID {process.pid})")
        break
    time.sleep(0.1)
else:
    sys.exit("Review server did not become ready; see review-server.log.")
