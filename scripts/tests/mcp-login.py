#!/usr/bin/env python3
"""Run real Claude MCP OAuth locally and through an in-process paired host, without a browser.

Usage: python3 scripts/tests/mcp-login.py /absolute/path/to/claude [claude-code|codex]
Only the loopback fixture is contacted. Credentials use a unique temporary namespace, removed on exit.
HOME stays intact because macOS credential access depends on it; no real agent configuration is read.
"""

import base64
import hashlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse


class OAuthFixture(http.server.BaseHTTPRequestHandler):
    challenges = {}
    exchanges = 0
    authenticated_requests = 0

    def log_message(self, *_):
        pass

    @property
    def base(self):
        return f"http://127.0.0.1:{self.server.server_port}"

    def reply(self, value, status=200, headers=None):
        data = json.dumps(value).encode()
        self.send_response(status)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        request = urllib.parse.urlsplit(self.path)
        if "oauth-protected-resource" in request.path:
            self.reply({"resource": self.base + "/mcp", "authorization_servers": [self.base]})
        elif "oauth-authorization-server" in request.path:
            self.reply({
                "issuer": self.base,
                "authorization_endpoint": self.base + "/authorize",
                "token_endpoint": self.base + "/token",
                "registration_endpoint": self.base + "/register",
                "response_types_supported": ["code"],
                "grant_types_supported": ["authorization_code", "refresh_token"],
                "token_endpoint_auth_methods_supported": ["none"],
                "code_challenge_methods_supported": ["S256"],
            })
        elif request.path == "/authorize":
            query = urllib.parse.parse_qs(request.query)
            if query.get("code_challenge_method") != ["S256"]:
                self.reply({}, 400)
                return
            code = "fixture-code-" + str(len(self.challenges))
            self.challenges[code] = query["code_challenge"][0]
            redirect = query["redirect_uri"][0] + "?" + urllib.parse.urlencode({
                "code": code, "state": query["state"][0],
            })
            self.reply({"redirect": redirect})
        else:
            self.reply({}, 404)

    def do_POST(self):
        data = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if self.path == "/register":
            self.reply(json.loads(data) | {
                "client_id": "fixture-client", "client_secret": "fixture-client-secret",
                "client_secret_expires_at": 0, "client_id_issued_at": int(time.time()),
            }, 201)
        elif self.path == "/token":
            query = urllib.parse.parse_qs(data.decode())
            verifier = query.get("code_verifier", [""])[0]
            challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
            if self.challenges.pop(query.get("code", [""])[0], None) != challenge:
                self.reply({"error": "invalid_grant"}, 400)
                return
            OAuthFixture.exchanges += 1
            self.reply({
                "access_token": "fixture-access", "refresh_token": "fixture-refresh",
                "token_type": "Bearer", "expires_in": 3600,
            })
        elif self.path == "/mcp":
            if self.headers.get("Authorization") != "Bearer fixture-access":
                self.reply({}, 401, {
                    "WWW-Authenticate": f'Bearer resource_metadata="{self.base}/.well-known/oauth-protected-resource"',
                })
                return
            OAuthFixture.authenticated_requests += 1
            request = json.loads(data)
            if "id" not in request:
                self.reply({}, 202)
            else:
                result = {"tools": []}
                if request.get("method") == "initialize":
                    result = {"protocolVersion": "2025-03-26", "capabilities": {"tools": {}},
                              "serverInfo": {"name": "fixture", "version": "1"}}
                self.reply({"jsonrpc": "2.0", "id": request["id"], "result": result})
        else:
            self.reply({}, 404)


def main():
    executable = Path(sys.argv[1]).resolve(strict=True)
    agent = sys.argv[2] if len(sys.argv) > 2 else "claude-code"
    repo = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="native-mcp-login-") as temporary:
        config = Path(temporary).resolve()
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), OAuthFixture)
        endpoint = f"http://127.0.0.1:{server.server_port}/mcp"
        (config / ".claude.json").write_text(json.dumps({
            "mcpServers": {"fixture": {"type": "http", "url": endpoint}},
        }))
        (config / "config.toml").write_text(
            'mcp_oauth_credentials_store = "file"\n[mcp_servers.fixture]\nurl = ' + json.dumps(endpoint) + '\n'
        )
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            result = subprocess.run(
                ["nice", "-n", "10", "swift", "test", "-j", "4", "--filter", "HostMCPLoginTests"],
                cwd=repo / "Packages/NativeHost",
                env=os.environ | {
                    "NATIVE_MCP_LOGIN_CLI": str(executable), "NATIVE_MCP_LOGIN_CONFIG": str(config),
                    "NATIVE_MCP_LOGIN_ENDPOINT": endpoint,
                    "NATIVE_MCP_LOGIN_FORMAT": agent,
                },
            )
            if result.returncode:
                return result.returncode
            if OAuthFixture.exchanges != 2 or (agent == "claude-code" and OAuthFixture.authenticated_requests < 2):
                print("FAIL: expected two PKCE-validated token exchanges and authenticated reconnects")
                return 1
            print(f"PASS: {agent} local loopback and paired-host paste completed OAuth and saved sign-in")
            return 0
        finally:
            server.shutdown()
            server.server_close()
            service = "Claude Code-credentials-" + hashlib.sha256(str(config).encode()).hexdigest()[:8]
            subprocess.run(
                ["/usr/bin/security", "delete-generic-password", "-s", service],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
            )


if __name__ == "__main__":
    sys.exit(main())
