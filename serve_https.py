#!/usr/bin/env python3
"""Simple HTTPS server for testing x-safari-https redirects."""
import http.server
import ssl

server = http.server.HTTPServer(("0.0.0.0", 8443), http.server.SimpleHTTPRequestHandler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain("cert.pem", "key.pem")
server.socket = ctx.wrap_socket(server.socket, server_side=True)
print("Serving HTTPS on https://0.0.0.0:8443 ...")
server.serve_forever()
