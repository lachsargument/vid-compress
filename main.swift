import AppKit
import UniformTypeIdentifiers

/// Accepts file drops from Finder and hands the URLs to `onDrop`.
final class DropView: NSView {
    var onDrop: ([URL]) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls =
            sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDrop(urls)
        return !urls.isEmpty
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var input: URL?
    var proc: Process?
    var cancelled = false
    var errText = ""

    let fileLabel = NSTextField(
        labelWithString: "Choose a video, or drag a video into this window.")
    let chooseButton = NSButton(title: "Choose Video…", target: nil, action: nil)
    let formatPopup = NSPopUpButton()
    let fpsPopup = NSPopUpButton()
    let resPopup = NSPopUpButton()
    let qualityPopup = NSPopUpButton()
    let hardwareBox = NSButton(checkboxWithTitle: "Use hardware encoding", target: nil, action: nil)
    let hardwareHelp = NSTextField(labelWithString: "")
    let progress = NSProgressIndicator()
    let statusLabel = NSTextField(labelWithString: "")
    let goButton = NSButton(title: "Compress…", target: nil, action: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        formatPopup.addItems(withTitles: formats.map(\.title))
        fpsPopup.addItems(withTitles: frameRates.map { $0.map { "\($0) fps" } ?? "Original" })
        resPopup.addItems(withTitles: resolutions.map { $0.map { "\($0)p" } ?? "Original" })
        qualityPopup.addItems(withTitles: qualities)
        qualityPopup.selectItem(at: 1)
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        hardwareHelp.textColor = .secondaryLabelColor
        hardwareHelp.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        // The grid hugs its content tightly, so it would clip this line.
        hardwareHelp.setContentCompressionResistancePriority(.required, for: .horizontal)
        formatChanged()
        chooseButton.target = self
        chooseButton.action = #selector(choose)
        goButton.target = self
        goButton.action = #selector(compressOrCancel)
        goButton.keyEquivalent = "\r"
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Format:"), formatPopup],
            [NSTextField(labelWithString: "Frame rate:"), fpsPopup],
            [NSTextField(labelWithString: "Resolution:"), resPopup],
            [NSTextField(labelWithString: "Quality:"), qualityPopup],
            [NSGridCell.emptyContentView, hardwareBox],
            [NSGridCell.emptyContentView, hardwareHelp],
        ])
        grid.column(at: 0).xPlacement = .trailing
        // Keep the grid at its own width. If it stretches to the stack
        // width, the trailing label column takes the extra space and
        // pushes the pop-up buttons to the right edge.
        grid.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        // The help line under the checkbox is wider than the pop-up buttons.
        // Without a fixed width, the pop-up buttons grow to its width and
        // change size when the help text changes.
        grid.column(at: 1).xPlacement = .leading
        for popup in [formatPopup, fpsPopup, resPopup, qualityPopup] {
            popup.widthAnchor.constraint(equalToConstant: 170).isActive = true
        }
        let stack = NSStackView(views: [
            NSStackView(views: [chooseButton, fileLabel]), grid, progress, statusLabel, goButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = DropView()
        root.onDrop = { [weak self] urls in
            if self?.proc == nil { self?.load(urls.first) }
        }
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            progress.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 0),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Video Compressor"
        window.contentView = root
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // ffmpeg is a separate process and would keep running after we quit.
    func applicationWillTerminate(_ notification: Notification) {
        proc?.terminate()
    }

    @objc func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        if panel.runModal() == .OK { load(panel.url) }
    }

    func load(_ url: URL?) {
        guard let url else { return }
        input = url
        fileLabel.stringValue = "\(url.lastPathComponent) (\(fileSize(url)))"
        statusLabel.stringValue = ""
        progress.doubleValue = 0
    }

    @objc func compressOrCancel() {
        if let proc {
            cancelled = true
            proc.terminate()
            return
        }
        guard let input else { return }
        guard let ffmpeg = findTool("ffmpeg"), let ffprobe = findTool("ffprobe") else {
            alert(
                "Video Compressor cannot find FFmpeg. "
                    + "To install FFmpeg, run this command in Terminal: brew install ffmpeg")
            return
        }
        let format = formats[formatPopup.indexOfSelectedItem]
        let panel = NSSavePanel()
        panel.allowedContentTypes = UTType(filenameExtension: format.ext).map { [$0] } ?? []
        panel.nameFieldStringValue =
            input.deletingPathExtension().lastPathComponent + "-compressed." + format.ext
        panel.directoryURL = input.deletingLastPathComponent()
        guard panel.runModal() == .OK, let output = panel.url else { return }
        guard output.standardizedFileURL != input.standardizedFileURL else {
            alert("The output file cannot be the input file. Select a different output file.")
            return
        }

        let duration = probeDuration(ffprobe, input.path) ?? 0
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ffmpegArgs(
            input: input.path, output: output.path, format: format,
            fps: frameRates[fpsPopup.indexOfSelectedItem],
            shortSide: resolutions[resPopup.indexOfSelectedItem],
            quality: qualityPopup.indexOfSelectedItem,
            hardware: hardwareBox.isEnabled && hardwareBox.state == .on)
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        // Both pipes must be drained, or ffmpeg blocks once a pipe buffer fills.
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let text = String(decoding: h.availableData, as: UTF8.self)
            for line in text.split(separator: "\n") where line.hasPrefix("out_time_us=") {
                guard let us = Double(line.dropFirst(12)), duration > 0 else { continue }
                DispatchQueue.main.async { self?.progress.doubleValue = us / 1e6 / duration }
            }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let text = String(decoding: h.availableData, as: UTF8.self)
            DispatchQueue.main.async { self?.errText += text }
        }
        p.terminationHandler = { [weak self] p in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { self?.finished(p.terminationStatus, output) }
        }

        cancelled = false
        errText = ""
        progress.isIndeterminate = duration <= 0
        progress.doubleValue = 0
        progress.startAnimation(nil)
        statusLabel.stringValue = "The compression started."
        do {
            try p.run()
        } catch {
            alert(error.localizedDescription)
            return
        }
        proc = p
        setRunning(true)
    }

    func finished(_ status: Int32, _ output: URL) {
        proc = nil
        setRunning(false)
        progress.stopAnimation(nil)
        progress.isIndeterminate = false
        if status == 0 && !cancelled {
            progress.doubleValue = 1
            statusLabel.stringValue =
                "Done. The size changed from \(fileSize(input!)) to \(fileSize(output))."
            NSWorkspace.shared.activateFileViewerSelecting([output])
            return
        }
        try? FileManager.default.removeItem(at: output)
        progress.doubleValue = 0
        statusLabel.stringValue = cancelled ? "The compression stopped." : "The compression failed."
        if !cancelled {
            let detail = errText.trimmingCharacters(in: .whitespacesAndNewlines)
            alert(
                detail.isEmpty
                    ? "FFmpeg stopped with status \(status)." : String(detail.suffix(800))
            )
        }
    }

    func setRunning(_ running: Bool) {
        goButton.title = running ? "Cancel" : "Compress…"
        for control in [chooseButton, formatPopup, fpsPopup, resPopup, qualityPopup] {
            control.isEnabled = !running
        }
        hardwareBox.isEnabled =
            !running && formats[formatPopup.indexOfSelectedItem].hardwareCodec != nil
    }

    @objc func formatChanged() {
        let hasHardware = formats[formatPopup.indexOfSelectedItem].hardwareCodec != nil
        hardwareBox.isEnabled = hasHardware
        hardwareHelp.stringValue =
            hasHardware
            ? "Hardware encoding is faster. The file is usually larger."
            : "This format has no hardware encoder."
    }

    func fileSize(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    func alert(_ text: String) {
        let a = NSAlert()
        a.messageText = text
        a.runModal()
    }

    func makeMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(
            withTitle: "Quit Video Compressor", action: #selector(NSApp.terminate),
            keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = app
        main.addItem(item)
        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
