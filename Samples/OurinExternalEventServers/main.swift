// main.swift (demo bootstrap)
import Foundation

let router = OurinSstpRouter()

let tcp = OurinSstpTcpServer()
tcp.onRequest = { router.handle(raw: $0) }
try? tcp.start(port: 9801)

let http = OurinSstpHttpServer()
http.onRequest = { router.handle(raw: $0) }
try? http.start(port: 9810)

let xpc = OurinSstpXPCListener()
xpc.onRequest = { router.handle(raw: $0) }
xpc.start()

RunLoop.main.run()
