#!/usr/bin/env python3
"""
GO2RTC Monitor — Config API
GET  /config  → retorna config.json (público)
POST /config  → grava config.json (requer Authorization: Bearer <sha256>)
POST /auth    → verifica senha, retorna token
"""
import json, os, sys, time, hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer

BASE_DIR    = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, 'config.json')
AUTH_PATH   = os.path.join(BASE_DIR, 'auth.hash')
PORT        = int(os.environ.get('CONFIG_API_PORT', 1985))
EMPTY_CFG   = '{"servers":[],"cameras":[],"selectedUids":[]}'

# Rate limiting: máx 5 tentativas por IP por 60 segundos
_rate        = {}
RATE_MAX     = 5
RATE_WINDOW  = 60

CORS_HEADERS = {
    'Access-Control-Allow-Origin':  '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
}


def _load_hash():
    try:
        with open(AUTH_PATH, 'r') as f:
            return f.read().strip()
    except FileNotFoundError:
        return None


def _check_rate(ip):
    now  = time.time()
    hits = [t for t in _rate.get(ip, []) if now - t < RATE_WINDOW]
    _rate[ip] = hits
    return len(hits) < RATE_MAX


def _record_hit(ip):
    _rate.setdefault(ip, []).append(time.time())


class Handler(BaseHTTPRequestHandler):
    def _send_cors(self):
        for k, v in CORS_HEADERS.items():
            self.send_header(k, v)

    def _bearer(self):
        auth = self.headers.get('Authorization', '')
        return auth[7:].strip() if auth.startswith('Bearer ') else None

    def _is_authed(self):
        token  = self._bearer()
        stored = _load_hash()
        return bool(token and stored and token == stored)

    def do_OPTIONS(self):
        self.send_response(204)
        self._send_cors()
        self.end_headers()

    def do_GET(self):
        if self.path != '/config':
            self.send_response(404); self.end_headers(); return
        try:
            with open(CONFIG_PATH, 'rb') as f:
                data = f.read()
        except FileNotFoundError:
            data = EMPTY_CFG.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', len(data))
        self._send_cors()
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if   self.path == '/auth':   self._handle_auth()
        elif self.path == '/config':
            if not self._is_authed():
                self._respond_error(401, 'Não autorizado'); return
            self._handle_config_post()
        else:
            self.send_response(404); self.end_headers()

    def _handle_auth(self):
        ip = self.client_address[0]
        if not _check_rate(ip):
            self._respond_error(429, 'Muitas tentativas — aguarde 1 minuto'); return
        _record_hit(ip)
        try:
            length = int(self.headers.get('Content-Length', 0))
            body   = self.rfile.read(length)
            data   = json.loads(body)
            pwd    = str(data.get('password', ''))
        except Exception:
            self._respond_error(400, 'Requisição inválida'); return
        stored = _load_hash()
        if not stored:
            self._respond_error(503, 'Sistema não configurado — execute install.sh'); return
        attempt = hashlib.sha256(pwd.encode('utf-8')).hexdigest()
        if attempt != stored:
            self._respond_error(401, 'Senha incorreta'); return
        resp = json.dumps({'token': stored}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', len(resp))
        self._send_cors()
        self.end_headers()
        self.wfile.write(resp)

    def _handle_config_post(self):
        try:
            length = int(self.headers.get('Content-Length', 0))
            body   = self.rfile.read(length)
            parsed = json.loads(body)
            required = ('servers', 'cameras', 'selectedUids')
            if not all(k in parsed and isinstance(parsed[k], (list, dict)) for k in required):
                raise ValueError('estrutura inválida — campos obrigatórios ausentes')
            tmp = CONFIG_PATH + '.tmp'
            with open(tmp, 'w', encoding='utf-8') as f:
                json.dump(parsed, f, ensure_ascii=False, indent=2)
            os.replace(tmp, CONFIG_PATH)
            self.send_response(204)
            self._send_cors()
            self.end_headers()
        except json.JSONDecodeError as e:
            self._respond_error(400, f'JSON inválido: {e}')
        except ValueError as e:
            self._respond_error(400, str(e))
        except OSError as e:
            self._respond_error(500, f'Erro ao gravar arquivo: {e}')

    def _respond_error(self, code, msg):
        body = msg.encode()
        self.send_response(code)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', len(body))
        self._send_cors()
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass  # silencioso — logs via journald


if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', PORT), Handler)
    print(f'Config API ouvindo em http://0.0.0.0:{PORT}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('Encerrado.')
        sys.exit(0)
