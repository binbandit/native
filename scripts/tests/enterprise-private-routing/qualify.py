#!/usr/bin/env python3
"""Local qualification of installed artifacts. Never downloads, uses user config, or enables a route.

Exit 2 means unqualified, with content-free blockers. This harness never issues a qualification receipt.
macOS sandbox-exec is mandatory. Other OS enforcement is a separate qualification job.
"""
import argparse
import hashlib
import http.server
import json
import os
import platform
from pathlib import Path
import queue
import signal
import socket
import ssl
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, timeout=45, **kwargs)


class Provider(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        self.record(None)
        self.send_error(404)

    def record(self, body):
        # Never record request bodies, headers, URLs or credentials. Fixture model only.
        self.server.observed.append({"method": self.command,
                                     "path": "/v1/responses" if self.path == "/v1/responses" else "other",
                                     "modelMatches": body is not None and body.get("model") == "fixture-model",
                                     "syntheticAuthMatches": self.headers.get("Authorization") == "Bearer fixture-only"})

    def do_POST(self):
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        except (ValueError, json.JSONDecodeError):
            body = {}
        self.record(body)
        if self.server.mode == "redirect":
            self.send_response(307)
            self.send_header("Location", self.server.redirect)
            self.end_headers()
            return
        if self.server.mode == "auth":
            self.send_error(401)
            return
        if self.server.mode == "model":
            self.send_error(404)
            return
        message = {"id": "msg_fixture", "type": "message", "role": "assistant", "status": "completed",
                   "content": [{"type": "output_text", "text": "Fixture response", "annotations": []}]}
        response = {"id": "resp_fixture", "object": "response", "status": "completed", "model": "fixture-model",
                    "output": [message], "usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2}}
        events = [
            ("response.created", {"response": {**response, "status": "in_progress", "output": []}}),
            ("response.output_item.added", {"output_index": 0, "item": {**message, "status": "in_progress", "content": []}}),
            ("response.output_text.delta", {"item_id": "msg_fixture", "output_index": 0, "content_index": 0,
                                            "delta": "Fixture response"}),
            ("response.output_item.done", {"output_index": 0, "item": message}),
            ("response.completed", {"response": response}),
        ]
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for event, data in events:
            try:
                self.wfile.write(("event: " + event + "\ndata: " + json.dumps({"type": event, **data}) + "\n\n").encode())
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                break


class FixtureServer:
    def __init__(self, context=None):
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Provider)
        self.server.observed = []
        self.server.mode = "success"
        self.server.redirect = ""
        if context:
            self.server.socket = context.wrap_socket(self.server.socket, server_side=True)
        self.port = self.server.server_port
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def profile(home, adapter, ports):
    # Only exact local fixture ports are reachable, including by descendants. No DNS, public
    # provider, updater, telemetry, browser, or arbitrary exec. Allowing an extra local port for
    # redirect observation does not grant it as an approved provider origin.
    allowed = " ".join(f'(remote ip "localhost:{port}")' for port in ports)
    grant = f"(allow network-outbound {allowed})" if ports else ""
    # Node resolves the entry path one ancestor at a time. Metadata permission for those exact
    # directories does not grant file contents or access to foreign credential stores.
    ancestors = " ".join(f"(literal {json.dumps(str(parent))})" for parent in adapter.parents)
    return f'''(version 1)(allow default)(deny network*)
{grant}
(deny file-read* (subpath {json.dumps(str(Path.home()))}))
(allow file-read-metadata {ancestors})
(allow file-read* (subpath {json.dumps(str(adapter.parent.parent))}))
(allow file-read* (subpath {json.dumps(str(home))}))
(deny process-exec)
(allow process-exec (literal {json.dumps(str(ARGS.node))}) (literal {json.dumps(str(ARGS.codex))}))'''


class ACP:
    def __init__(self, command, env, cwd):
        self.process = subprocess.Popen(command, env=env, cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, text=True, start_new_session=True)
        self.messages = queue.Queue()
        self.counter = 0
        self.failure = "unclassified"
        threading.Thread(target=self.read_errors, daemon=True).start()
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        for line in self.process.stdout:
            try:
                self.messages.put(json.loads(line))
            except json.JSONDecodeError:
                pass

        self.messages.put(None)

    def read_errors(self):
        for line in self.process.stderr:
            if "EPERM" in line or "Operation not permitted" in line:
                self.failure = "sandbox-operation-denied"
            elif "Cannot find module" in line:
                self.failure = "installed-module-unavailable"
            elif "mcp" in line.lower():
                self.failure = "mcp-configuration-rejected"

    def request(self, method, params):
        self.counter += 1
        ident = self.counter
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": ident, "method": method, "params": params}) + "\n")
        self.process.stdin.flush()
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            msg = self.messages.get(timeout=max(0.01, deadline - time.monotonic()))
            if msg is None:
                return {"error": True, "failure": self.failure}
            if msg.get("id") == ident and "method" not in msg:
                return msg
            if "id" in msg and "method" in msg:
                # Deny every tool/elicitation request, including login/browser requests.
                self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": msg["id"], "error":
                                                    {"code": -32601, "message": "Fixture denies client actions"}}) + "\n")
                self.process.stdin.flush()
        raise TimeoutError()

    def close(self):
        # Closing stdin asks the adapter to shut down its app-server. Wait before signaling so an
        # already-exited session cannot target a reused process group.
        self.process.stdin.close()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(self.process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            except PermissionError:
                if self.process.poll() is None:
                    self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()


def attempt(work, config_binary, origin, ports, extra=None, text="Say fixture."):
    home = work / ("case-" + str(time.monotonic_ns()))
    home.mkdir()
    codex_home = home / "codex"
    codex_home.mkdir()
    (codex_home / "config.toml").write_text(
        '[mcp_servers.fixture-disabled]\ncommand = "/usr/bin/false"\n')
    # Isolated fixture config, synthetic credentials only. No inherited proxy, auth, npm or Node settings.
    env = {"PATH": "/usr/bin:/bin", "HOME": str(home), "CODEX_HOME": str(codex_home), "TMPDIR": str(home),
           "CODEX_PATH": str(ARGS.codex), "NATIVE_PROVIDER_KEY": "fixture-only",
           "RUST_LOG": "off"}
    env.update(json.loads(run([str(config_binary), origin]).stdout))
    env.update(extra or {})
    command = ["/usr/bin/sandbox-exec", "-p", profile(home, ARGS.adapter, ports), str(ARGS.node), str(ARGS.adapter)]
    client = ACP(command, env, home)
    try:
        initialized = client.request("initialize", {"protocolVersion": 1, "clientCapabilities": {},
                                                    "clientInfo": {"name": "native-fixture", "version": "1"}})
        if "error" in initialized:
            return {"stage": "initialize", "succeeded": False, "failure": client.failure}
        session = client.request("session/new", {"cwd": str(home), "mcpServers": []})
        if "error" in session:
            error = session["error"]
            failure = "adapter-rejected-session"
            if isinstance(error, dict) and error.get("message") == "Authentication required":
                failure = "adapter-authentication-required"
            return {"stage": "session", "succeeded": False, "failure": failure}
        result = client.request("session/prompt", {"sessionId": session["result"]["sessionId"],
                                                  "prompt": [{"type": "text", "text": text}]})
        return {"stage": "prompt", "succeeded": "error" not in result,
                "stopReason": result.get("result", {}).get("stopReason")}
    except (queue.Empty, TimeoutError, BrokenPipeError):
        return {"stage": "timeout-or-exit", "succeeded": False}
    finally:
        client.close()


def qualify(report, work):
    if not Path("/usr/bin/sandbox-exec").exists():
        raise RuntimeError("egress-enforcement-unavailable")
    for artifact in [ARGS.codex, ARGS.adapter, ARGS.node]:
        if not artifact.is_file():
            raise RuntimeError("installed-artifact-missing")
    package = json.loads((ARGS.adapter.parent.parent / "package.json").read_text())
    if package.get("version") != "2.2.2":
        raise RuntimeError("adapter-version-mismatch")
    clean_env = {"HOME": str(work), "CODEX_HOME": str(work), "PATH": "/usr/bin:/bin"}
    # Even version probes have network denied and no access to the real user's home.
    probe_profile = profile(work, ARGS.adapter, [])
    version = run(["/usr/bin/sandbox-exec", "-p", probe_profile, str(ARGS.codex), "--version"], env=clean_env).stdout.decode().strip()
    node_version = run(["/usr/bin/sandbox-exec", "-p", probe_profile, str(ARGS.node), "--version"], env=clean_env).stdout.decode().strip()
    report["environment"] = {"system": platform.system(), "release": platform.release(), "machine": platform.machine()}
    report["artifacts"] = {"cliVersion": version, "adapterVersion": package["version"], "nodeVersion": node_version,
                           "cliSHA256": digest(ARGS.codex), "adapterSHA256": digest(ARGS.adapter),
                           "nodeSHA256": digest(ARGS.node)}
    if version != "codex-cli 0.164.0":
        raise RuntimeError("cli-version-mismatch")
    report["stage"] = "compile-translator"
    sources = ROOT / "Packages/ACP/Sources/ACP"
    binary = work / "config"
    run(["xcrun", "swiftc", "-o", str(binary), str(sources / "JSONValue.swift"),
         *[str(sources / "Adapters" / name) for name in ["AgentNetworkCapabilities.swift", "AgentRouteIdentity.swift",
           "AgentRoutePurpose.swift", "AgentPrivateRoute.swift", "AgentRouteFailure.swift", "CodexConfigOverrides.swift"]],
         str(FIXTURE / "main.swift")])
    report["stage"] = "create-local-tls-fixture"
    cert_config = work / "openssl.cnf"
    cert_config.write_text("[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n"
                           "[dn]\nCN=Native fixture\n[ext]\nsubjectAltName=IP:127.0.0.1\nbasicConstraints=critical,CA:TRUE\n")
    for name in ["valid", "invalid"]:
        run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
             "-config", str(cert_config), "-keyout", str(work / (name + ".key")),
             "-out", str(work / (name + ".pem"))], env=clean_env)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(work / "valid.pem", work / "valid.key")
    provider, redirect_target, tls = FixtureServer(), FixtureServer(), FixtureServer(context)
    try:
        report["stage"] = "egress-negative-probe"
        ports = [provider.port, redirect_target.port]
        # Verify the exact allow/deny profile against two LOCAL sockets before running the CLI.
        # An unapproved loopback port is denied; the profile has no off-machine allow rules.
        selftest = 'const net=require("net");const s=net.connect(+process.argv[1],"127.0.0.1");s.on("connect",()=>process.exit(1));s.on("error",e=>process.exit(e.code==="EPERM"?0:2));'
        denied = subprocess.run(
            ["/usr/bin/sandbox-exec", "-p", profile(work, ARGS.adapter, ports), str(ARGS.node), "-e", selftest,
             str(tls.port)], env=clean_env, capture_output=True, timeout=10)
        if denied.returncode != 0:
            raise RuntimeError("egress-negative-probe-failed")
        positive = selftest.replace('process.exit(1)', 'process.exit(0)').replace('e.code==="EPERM"?0:2', '2')
        allowed = subprocess.run(
            ["/usr/bin/sandbox-exec", "-p", profile(work, ARGS.adapter, ports), str(ARGS.node), "-e", positive,
             str(provider.port)], env=clean_env, capture_output=True, timeout=10)
        if allowed.returncode != 0:
            raise RuntimeError("egress-positive-probe-failed")
        report["egress"] = "sandbox denies network; only exact fixture loopback ports allowed; positive and negative local-port probes passed"
        report["stage"] = "actual-adapter-cases"
        origin = f"http://127.0.0.1:{provider.port}"
        for case, mode in [("allowed", "success"), ("failed-auth", "auth"), ("failed-model", "model")]:
            provider.server.mode = mode
            provider.server.observed.clear()
            result = attempt(work, binary, origin, ports)
            report["cases"][case] = {**result, "requests": list(provider.server.observed)}
            if case == "allowed" and result["stage"] != "prompt":
                report["blockers"].append(result.get("failure", "adapter-startup-blocked"))
                for pending in ["failed-auth", "failed-model", "redirect", "failed-endpoint", "proxy", "proxy-bypass",
                                "valid-ca", "invalid-ca", "title", "commit", "pull-request", "workflow", "recovery"]:
                    report["cases"][pending] = {"status": "blocked-by-session-start"}
                return
        provider.server.mode = "redirect"
        provider.server.redirect = f"http://127.0.0.1:{redirect_target.port}/v1/responses"
        result = attempt(work, binary, origin, ports)
        report["cases"]["redirect"] = {**result, "unapprovedOriginRequests": len(redirect_target.server.observed)}
        # A closed fixture endpoint cannot trigger a public fallback because all other egress is denied.
        closed = socket.socket()
        closed.bind(("127.0.0.1", 0))
        closed_port = closed.getsockname()[1]
        closed.close()
        report["cases"]["failed-endpoint"] = attempt(work, binary, f"http://127.0.0.1:{closed_port}", [closed_port])
        provider.server.mode = "success"
        for name, extra in [
            ("proxy", {"HTTP_PROXY": f"http://127.0.0.1:{redirect_target.port}",
                       "HTTPS_PROXY": f"http://127.0.0.1:{redirect_target.port}", "NO_PROXY": ""}),
            ("proxy-bypass", {"HTTP_PROXY": f"http://127.0.0.1:{redirect_target.port}",
                              "HTTPS_PROXY": f"http://127.0.0.1:{redirect_target.port}", "NO_PROXY": "127.0.0.1"})]:
            provider.server.observed.clear()
            redirect_target.server.observed.clear()
            result = attempt(work, binary, origin, ports, extra)
            report["cases"][name] = {**result, "providerRequests": len(provider.server.observed),
                                     "proxyRequests": len(redirect_target.server.observed)}
        # Trust applies to both runtimes; invalid roots must not produce an HTTP request.
        # The CLI may use a different trust store. That is a qualification result, never a reason
        # to disable certificate verification or install a root in the user's keychain.
        for name in ["valid", "invalid"]:
            tls.server.observed.clear()
            result = attempt(work, binary, f"https://127.0.0.1:{tls.port}", [tls.port],
                             {"SSL_CERT_FILE": str(work / (name + ".pem")),
                              "NODE_EXTRA_CA_CERTS": str(work / (name + ".pem"))})
            report["cases"][name + "-ca"] = {**result, "requests": list(tls.server.observed)}
        for purpose in ["title", "commit", "pull-request", "workflow", "recovery"]:
            provider.server.observed.clear()
            result = attempt(work, binary, origin, ports, text="Return fixture " + purpose + " text.")
            report["cases"][purpose] = {**result, "requests": list(provider.server.observed)}
        report["blockers"].extend(["proxy-bypass-and-ca-controls-not-qualified-by-translator",
                                   "restart-session-recovery-not-qualified", "mcp-isolation-not-qualified",
                                   "telemetry-and-self-update-not-qualified"])
        # Fixture results are partial evidence. No test output can enable the host approval list.
        if not report["cases"]["allowed"]["succeeded"]:
            report["blockers"].append("private-provider-request-did-not-complete")
        if report["cases"]["redirect"]["unapprovedOriginRequests"]:
            report["blockers"].append("redirect-left-approved-origin")
    finally:
        provider.close()
        redirect_target.close()
        tls.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex", type=Path, required=True)
    parser.add_argument("--adapter", type=Path, required=True, help="Installed codex-acp dist/index.js, never npx")
    parser.add_argument("--node", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    ARGS = parser.parse_args()
    ARGS.codex, ARGS.adapter, ARGS.node = (p.resolve() for p in [ARGS.codex, ARGS.adapter, ARGS.node])
    report = {"revision": run(["git", "rev-parse", "HEAD"], cwd=ROOT).stdout.decode().strip(),
              "diffSHA256": hashlib.sha256(run(["git", "diff", "HEAD"], cwd=ROOT).stdout).hexdigest(),
              "qualified": False, "cases": {}, "blockers": []}
    with tempfile.TemporaryDirectory(prefix="native-private-routing-") as temporary:
        try:
            qualify(report, Path(temporary).resolve())
        except Exception as error:
            # Exceptions can include paths, CLI stderr or configuration. Only the stable category escapes.
            report["blockers"].append(str(error) if isinstance(error, RuntimeError) else type(error).__name__)
    ARGS.output.write_text(json.dumps(report, indent=2) + "\n")
    print("UNQUALIFIED: " + ", ".join(report["blockers"]))
    raise SystemExit(2)
