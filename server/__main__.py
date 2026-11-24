import socket

import uvicorn

from .config import HOST, PORT


def _lan_ip():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
    except OSError:
        return None


if __name__ == "__main__":
    ip = _lan_ip()
    print(f"\n  music is running\n  ▸ this computer: http://localhost:{PORT}")
    if ip and HOST in ("0.0.0.0", "::"):
        print(f"  ▸ phone (same wifi): http://{ip}:{PORT}")
    print()
    uvicorn.run("server.main:app", host=HOST, port=PORT, log_level="warning", proxy_headers=True)
