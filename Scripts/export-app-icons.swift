import AppKit
import WebKit
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
final class Exporter: NSObject, WKNavigationDelegate {
    func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
        view.evaluateJavaScript("JSON.stringify(variants.map(v => { const c=canvas(1024); paintIcon(c,v.draw,false); return {id:v.id, png:c.toDataURL('image/png').split(',')[1]}; }))") { value, error in
            guard error == nil, let text = value as? String,
                  let rows = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String:String]] else {
                fputs("Cannot render app icons\n", stderr); exit(1)
            }
            do {
                for row in rows {
                    guard let id=row["id"], let base64=row["png"], let data=Data(base64Encoded:base64) else { exit(1) }
                    try data.write(to: destination.appendingPathComponent("Icon-\(id).png"))
                    print("Rendered \(id)")
                }
            } catch { fputs("Cannot save app icons\n", stderr); exit(1) }
            NSApplication.shared.terminate(nil)
        }
    }
}
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let delegate = Exporter()
let view = WKWebView(frame: NSRect(x:0,y:0,width:1400,height:1200))
view.navigationDelegate = delegate
let input = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Design/AppIcon.html")
view.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())
application.run()
