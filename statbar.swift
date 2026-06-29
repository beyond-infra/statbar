import Cocoa
import Darwin

class CPUView: NSView {
    var pValues: [Int] = []
    var eValues: [Int] = []
    var memPercent: Int = 0
    var showPopover: (() -> Void)?
    var hidePopover: (() -> Void)?

    override func updateTrackingAreas() {
        if let existing = trackingAreas.first { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { showPopover?() }
    override func mouseExited(with event: NSEvent) { hidePopover?() }

    let barW: CGFloat = 5, barH: CGFloat = 22
    let gap: CGFloat = 2
    let pEColors: [(NSColor, NSColor)] = [
        (NSColor.systemBlue, NSColor.systemBlue.withAlphaComponent(0.3)),
        (NSColor.systemBlue, NSColor.systemBlue.withAlphaComponent(0.3)),
        (NSColor.systemBlue, NSColor.systemBlue.withAlphaComponent(0.3)),
        (NSColor.systemBlue, NSColor.systemBlue.withAlphaComponent(0.3)),
        (NSColor.systemBlue, NSColor.systemBlue.withAlphaComponent(0.3)),
        (NSColor.systemBlue, NSColor.systemBlue.withAlphaComponent(0.3)),
        (NSColor.systemGray, NSColor.systemGray.withAlphaComponent(0.3)),
        (NSColor.systemGray, NSColor.systemGray.withAlphaComponent(0.3)),
    ]

    let memGap: CGFloat = 4, memW: CGFloat = 12

    override var intrinsicContentSize: NSSize {
        let cores = max(pValues.count + eValues.count, 8)
        return NSSize(width: CGFloat(cores) * (barW + gap) + memGap + memW, height: barH)
    }

    override func draw(_ dirtyRect: NSRect) {
        let cores = max(pValues.count + eValues.count, 8)
        if cores == 0 { return }

        for i in 0..<cores {
            let isP = i < pValues.count
            let val = isP ? pValues[i] : (i < pValues.count + eValues.count ? eValues[i - pValues.count] : 0)
            let (_, bg) = pEColors[i]
            let x = CGFloat(i) * (barW + gap)

            let rect = NSRect(x: x, y: 0, width: barW, height: barH)
            let bgPath = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
            bg.setFill()
            bgPath.fill()

            let fillHeight = barH * CGFloat(val) / 100.0
            if fillHeight > 0 {
                let color: NSColor = val > 70 ? NSColor.systemRed : val > 40 ? NSColor.systemOrange : NSColor.systemGreen
                color.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barW, height: fillHeight), xRadius: 1, yRadius: 1).fill()
            }
        }

        let mx = CGFloat(cores) * (barW + gap) + memGap
        let mRect = NSRect(x: mx, y: 0, width: memW, height: barH)
        let mPath = NSBezierPath(roundedRect: mRect, xRadius: 1, yRadius: 1)
        NSColor.systemPurple.withAlphaComponent(0.45).setFill()
        mPath.fill()

        let mFill = barH * CGFloat(memPercent) / 100.0
        if mFill > 0 {
            (memPercent > 70 ? NSColor.systemRed : NSColor.systemPurple).setFill()
            NSBezierPath(roundedRect: NSRect(x: mx, y: 0, width: memW, height: mFill), xRadius: 1, yRadius: 1).fill()
        }

        let fullW = CGFloat(cores) * (barW + gap) + memGap + memW
        let box = NSRect(x: 0, y: 0, width: fullW, height: barH)
        let boxPath = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
        NSColor.black.withAlphaComponent(0.12).setFill()
        boxPath.fill()
    }
}

class DetailPopover: NSViewController {
    let textLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 160))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        textLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textLabel)
        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            textLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            textLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])
    }

    func update(p: [Int], e: [Int], mem: Int) {
        let pLine = p.enumerated().map { "  P\($0+1) → \($1)%" }.joined(separator: "\n")
        let eLine = e.enumerated().map { "  E\($0+1) → \($1)%" }.joined(separator: "\n")
        textLabel.stringValue = "CPU\n\(pLine)\n\(eLine)\n\n内存  → \(mem)%"
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var cpuView: CPUView!
    var prevBusy: [UInt64] = [], prevIdle: [UInt64] = []
    var popover: NSPopover!
    var popoverController: DetailPopover!

    let pCoreCount: Int = {
        var val: Int32 = 0, size = MemoryLayout<Int32>.size
        sysctlbyname("hw.perflevel0.logicalcpu_max", &val, &size, nil, 0)
        return Int(val)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        popoverController = DetailPopover()
        popover = NSPopover()
        popover.contentViewController = popoverController
        popover.behavior = .transient

        cpuView = CPUView(frame: .zero)
        cpuView.translatesAutoresizingMaskIntoConstraints = false

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.addSubview(cpuView)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        cpuView.showPopover = { [weak self] in self?.showPopover() }
        cpuView.hidePopover = { [weak self] in self?.popover.close() }

        NSLayoutConstraint.activate([
            cpuView.leadingAnchor.constraint(equalTo: statusItem.button!.leadingAnchor),
            cpuView.trailingAnchor.constraint(equalTo: statusItem.button!.trailingAnchor),
            cpuView.centerYAnchor.constraint(equalTo: statusItem.button!.centerYAnchor),
            cpuView.heightAnchor.constraint(equalToConstant: 24)
        ])

        update()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.update() }
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.close()
        } else {
            openActivityMonitor()
        }
    }

    @objc func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }

    func perCoreCPU() -> ([Int], [Int]) {
        var size: mach_msg_type_number_t = 0
        var info: processor_info_array_t? = nil
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &size) == KERN_SUCCESS,
              let info = info, size >= 4 else { return ([], []) }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(size) * 4) }

        let numCores = Int(size) / 4
        let p = min(pCoreCount, numCores), e = numCores - p
        var curBusy: [UInt64] = [], curIdle: [UInt64] = []

        info.withMemoryRebound(to: UInt32.self, capacity: Int(size)) { ptr in
            for i in 0..<numCores {
                let b = i * 4
                curBusy.append(UInt64(ptr[b]) + UInt64(ptr[b + 1]))
                curIdle.append(UInt64(ptr[b + 2]))
            }
        }

        if prevBusy.count != numCores { prevBusy = curBusy; prevIdle = curIdle; return ([], []) }

        func pcts(_ start: Int, _ count: Int) -> [Int] {
            guard count > 0 else { return [] }
            var r: [Int] = []
            for i in start..<(start + count) {
                let db = curBusy[i] - prevBusy[i]
                let di = curIdle[i] - prevIdle[i]
                let t = db + di
                r.append(t > 0 ? Int(db * 100 / t) : 0)
            }
            return r
        }

        let pVals = pcts(0, p), eVals = pcts(p, e)
        prevBusy = curBusy; prevIdle = curIdle
        return (pVals, eVals)
    }

    func memPercent() -> Int {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / 4)
        var stats = vm_statistics64_data_t()
        guard host_statistics64(mach_host_self(), HOST_VM_INFO64,
                                withUnsafeMutablePointer(to: &stats) { ptr in
                                    ptr.withMemoryRebound(to: integer_t.self, capacity: 1) { $0 }
                                },
                                &size) == KERN_SUCCESS else { return 0 }
        let used = UInt64(stats.internal_page_count + stats.wire_count + stats.compressor_page_count) * UInt64(vm_kernel_page_size)
        return ProcessInfo.processInfo.physicalMemory > 0
            ? Int(used * 100 / ProcessInfo.processInfo.physicalMemory) : 0
    }

    func update() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let (p, e) = perCoreCPU()
            let mem = memPercent()
            DispatchQueue.main.async {
                self.cpuView.pValues = p
                self.cpuView.eValues = e
                self.cpuView.memPercent = mem
                self.cpuView.invalidateIntrinsicContentSize()
                self.cpuView.needsDisplay = true
                self.popoverController.update(p: p, e: e, mem: mem)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()

if CommandLine.arguments.contains("--version") {
    print("statbar 0.1.0")
    exit(0)
}

app.delegate = delegate
app.run()
