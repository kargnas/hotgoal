import AppKit
import HotTargetCore

@MainActor
final class TemperatureLogWindowController: NSWindowController {
    private let log: TemperatureCSVLog
    private let textView: NSTextView

    init(log: TemperatureCSVLog) {
        self.log = log
        let frame = CGRect(x: 0, y: 0, width: 720, height: 480)
        textView = NSTextView(frame: frame)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)

        let scrollView = NSScrollView(frame: frame)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.documentView = textView

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Temperature Log"
        window.contentView = scrollView
        window.setFrameAutosaveName("TemperatureLogWindow")
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        do {
            let contents = try log.contents()
            textView.string = contents.isEmpty ? "No target temperature log yet." : contents
        } catch {
            textView.string = "Unable to read temperature log:\n\(error.localizedDescription)"
        }
        textView.scrollToEndOfDocument(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
