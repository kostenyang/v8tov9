import http.server, ssl, os
os.chdir('E:/')
h = http.server.HTTPServer(('0.0.0.0', 8443), http.server.SimpleHTTPRequestHandler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain('E:/repo-cert.pem', 'E:/repo-key.pem')
h.socket = ctx.wrap_socket(h.socket, server_side=True)
print('HTTPS repo serving E:/ on :8443')
h.serve_forever()
