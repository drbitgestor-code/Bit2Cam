#!/usr/bin/env python3
"""
Bit2Cam Central — servidor local
Substitui: python3 -m http.server 8080
Uso:        python3 central-server.py [porta]
"""
import json, os, sys
from http.server import HTTPServer, SimpleHTTPRequestHandler

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
BASE = os.path.dirname(os.path.abspath(__file__))
SERVERS_FILE = os.path.join(BASE, 'servers.json')

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=BASE, **kw)

    def do_POST(self):
        if self.path == '/servers.json':
            try:
                length = int(self.headers.get('Content-Length', 0))
                data   = self.rfile.read(length)
                json.loads(data)  # valida JSON antes de salvar
                with open(SERVERS_FILE, 'wb') as f:
                    f.write(data)
                self._ok({'ok': True})
            except Exception as e:
                self._err(str(e))
        else:
            self.send_error(404)

    def _ok(self, body):
        b = json.dumps(body).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(b))
        self.end_headers()
        self.wfile.write(b)

    def _err(self, msg):
        b = json.dumps({'ok': False, 'error': msg}).encode()
        self.send_response(400)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(b))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, fmt, *args):
        pass  # silencioso

if __name__ == '__main__':
    server = HTTPServer(('', PORT), Handler)
    print(f'Bit2Cam Central → http://localhost:{PORT}/bit2cam-central.html')
    print('Ctrl+C para parar')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
