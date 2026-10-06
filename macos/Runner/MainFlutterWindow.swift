import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Same start size as on Windows; the layout adapts down to the minimum.
    self.setContentSize(NSSize(width: 1180, height: 760))
    self.contentMinSize = NSSize(width: 420, height: 640)
    self.title = "KaGo VPN"
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
