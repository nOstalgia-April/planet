"""Serve the exported game locally. Close this window or press Ctrl+C to stop."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import webbrowser


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".pck": "application/octet-stream",
        ".bank": "application/octet-stream",
    }


if __name__ == "__main__":
    root = Path(__file__).resolve().parent
    # A stable origin preserves Godot's browser save. Fail visibly if already in use.
    with ThreadingHTTPServer(("127.0.0.1", 8765), partial(Handler, directory=str(root))) as server:
        address = "http://127.0.0.1:8765/"
        print("Planet web: " + address, flush=True)
        print("Keep this window open while playing. Press Ctrl+C to stop.", flush=True)
        webbrowser.open(address)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
