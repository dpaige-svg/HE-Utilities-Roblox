"""Local count-only endpoint; run with python -m api.detection_server."""
import argparse
import json
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from security.repository import SecurityRepository

ROOT = Path(__file__).resolve().parents[1]
MAX_BODY = 65536


class DetectionHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, repository, directory, **kwargs):
        self.repository = repository
        super().__init__(*args, directory=directory, **kwargs)

    def reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != '/detections':
            self.reply(404, {'error': 'Unknown endpoint'})
            return
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= MAX_BODY:
                raise ValueError('Invalid body size')
            self.connection.settimeout(5)
            payload = json.loads(self.rfile.read(size))
            if not isinstance(payload, dict) or set(payload) != {'detections'}:
                raise ValueError('Expected detections only')
            entries = payload['detections']
            if not isinstance(entries, list) or len(entries) > 1000:
                raise ValueError('Invalid detections list')
            # Validate the entire request before making any database changes.
            for entry in entries:
                if not isinstance(entry, dict) or set(entry) != {'ruleId', 'count'}:
                    raise ValueError('Expected ruleId and count only')
                if not isinstance(entry['ruleId'], str) or not entry['ruleId'].strip():
                    raise ValueError('Invalid ruleId')
                if type(entry['count']) is not int or not 0 < entry['count'] <= 2147483647:
                    raise ValueError('Invalid count')
        except (ValueError, UnicodeError, OSError):
            self.reply(400, {'error': 'Invalid detection payload'})
            return
        try:
            accepted = sum(self.repository.increment_detection(e['ruleId'], e['count']) for e in entries)
        except Exception:
            self.reply(503, {'error': 'Detection storage unavailable'})
            return
        self.reply(200, {'accepted': accepted, 'unknown': len(entries) - accepted})

    def do_GET(self):
        # Preserve the existing remote loader URL without exposing the database.
        if self.path != '/active_security_library.json':
            self.send_error(404)
            return
        super().do_GET()

    def do_HEAD(self):
        if self.path != '/active_security_library.json':
            self.send_error(404)
            return
        super().do_HEAD()


def create_server(host='127.0.0.1', port=8000, database=ROOT / 'data/security.db', directory=ROOT / 'data'):
    handler = partial(DetectionHandler, repository=SecurityRepository(str(database)), directory=str(directory))
    return ThreadingHTTPServer((host, port), handler)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8000)
    args = parser.parse_args()
    with create_server(port=args.port) as server:
        print(f'Detection service listening on http://127.0.0.1:{args.port}', flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
