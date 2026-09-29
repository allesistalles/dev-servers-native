import AppKit
import ServiceManagement
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case about = "About"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var monitor: ServerMonitor
    @State private var pane: SettingsPane?

    init(monitor: ServerMonitor, initialPane: SettingsPane = .general) {
        self.monitor = monitor
        _pane = State(initialValue: initialPane)
    }

    var body: some View {
        // Sidebar labels are buttons, not a NavigationSplitView List. On macOS 26
        // an unselected NSTableCellView commits its text layer before the cell is
        // in the layer tree, so geometryFlipped is wrong and the label draws
        // upside down. The selected row is rebuilt on emphasis, which is why only
        // that one looked upright. A Canvas in the row (the old dot glyph) made
        // that first display more likely.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPane.allCases) { item in
                    Button {
                        pane = item
                    } label: {
                        Label(L10n.text(item.rawValue), systemImage: item.symbol)
                            .font(Theme.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(pane == item ? Color.accentColor.opacity(0.18) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 200, alignment: .top)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.text(pane?.rawValue ?? "Settings"))
                    .font(Theme.displaySans)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 4)
                Group {
                    switch pane ?? .general {
                    case .general: GeneralPane()
                    case .about: AboutPane()
                    }
                }
                .formStyle(.grouped)
                .font(Theme.body)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 740, height: 560)
        .background(SettingsWindowActivator())
    }
}

/// LSUIElement apps stay `.accessory`, so a SwiftUI window opened from the menu
/// bar is ordered front without becoming key. The navigation title then uses the
/// inactive color. Activate once the window exists and make it key.
private struct SettingsWindowActivator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.attach(window)
        }
    }

    final class Coordinator: NSObject {
        private var attached = false

        func attach(_ window: NSWindow) {
            guard !attached else { return }
            attached = true
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: window)
        }

        @objc private func windowWillClose(_ notification: Notification) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @AppStorage(Preferences.language) private var language = InterfaceLanguage.system.rawValue
    @AppStorage(Preferences.iconStyle) private var iconStyle = Preferences.IconStyle.colonCount.rawValue
    @AppStorage(Preferences.hotkey) private var hotkey = true
    @AppStorage(Preferences.scanInterval) private var scanInterval = 2.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker(L10n.text("Language"), selection: $language) {
                    ForEach(InterfaceLanguage.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                Text(L10n.text("Changes apply immediately."))
                    .font(Theme.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle(L10n.text("Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Picker(selection: $iconStyle) {
                    ForEach(Preferences.IconStyle.allCases, id: \.rawValue) { Text(L10n.text($0.label)).tag($0.rawValue) }
                } label: {
                    SettingLabel(L10n.text("Menu bar icon"), caption: L10n.text("Unlit dots stay hidden until there's something to show"))
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle(isOn: $hotkey) {
                    SettingLabel(L10n.text("Show popover with ⌥⌘P"), caption: L10n.text("Global shortcut"))
                }
                .onChange(of: hotkey) { _, enabled in HotKey.shared.setEnabled(enabled) }
            }
            Section(L10n.text("Scanning")) {
                Picker(L10n.text("Scan every"), selection: $scanInterval) {
                    Text(L10n.text("1 second")).tag(1.0)
                    Text(L10n.text("2 seconds")).tag(2.0)
                    Text(L10n.text("5 seconds")).tag(5.0)
                    Text(L10n.text("10 seconds")).tag(10.0)
                }
            }
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    private let links: [(label: String, value: String, url: String)] = [
        ("Upstream", "tomjohndesign/what-the-port", "https://github.com/tomjohndesign/what-the-port"),
        (L10n.text("Website"), "tomjohn.design", "https://www.tomjohn.design"),
        ("This fork", "allesistalles/dev-servers-native", "https://github.com/allesistalles/dev-servers-native"),
    ]

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { L10n.format("Version %@ (%@)", short, $0) } ?? L10n.format("Version %@", short)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    AppIconView(size: 88)
                    VStack(spacing: 4) {
                        Text("Dev Servers").font(Theme.displaySans)
                        Text(version).font(Theme.monoCaption).foregroundStyle(.secondary)
                    }
                    Text(L10n.text("Every dev server on your Mac, in the menu bar.")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section {
                ExternalLinkRow(label: L10n.text("Report a bug"), value: "GitHub Issues", url: FeedbackLink.issue(.bug))
                ExternalLinkRow(label: L10n.text("Suggest a feature"), value: "GitHub Issues", url: FeedbackLink.issue(.feature))
            } header: {
                Text(L10n.text("Feedback"))
            } footer: {
                Text(L10n.text("Opens a new issue with your app and macOS versions filled in. Nothing is sent until you submit it."))
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                ExternalLinkRow(label: L10n.text("Enjoying Dev Servers?"), value: L10n.text("Tip jar"), url: FeedbackLink.tip)
            } header: {
                Text(L10n.text("Support"))
            } footer: {
                Text(L10n.text("Dev Servers is free and open source. If it saves you time, you can leave a tip of any amount through Stripe."))
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L10n.text("Forked from WhatThePort by Tom Johnson")) {
                ForEach(links, id: \.label) { link in
                    ExternalLinkRow(label: L10n.text(link.label), value: link.value, url: URL(string: link.url)!)
                }
            }
        }
    }
}

/// Prefilled GitHub issue links, so reports arrive with the details needed to reproduce them.
enum FeedbackLink {
    enum Kind { case bug, feature }

    static let repository = "https://github.com/allesistalles/dev-servers-native"

    /// Redirects to the tip page (TIP_URL on the site), so it can change without an app update.
    static let tip = URL(string: "https://whattheport.dev/tip")!

    static func issue(_ kind: Kind) -> URL {
        let body: String
        let label: String
        switch kind {
        case .bug:
            label = "bug"
            body = """
            **What happened?**


            **What did you expect?**


            **Steps to reproduce**
            1.

            ---
            \(environment)
            """
        case .feature:
            label = "enhancement"
            body = """
            **What would you like Dev Servers to do?**


            **Why would it help?**


            ---
            \(environment)
            """
        }
        var components = URLComponents(string: repository + "/issues/new")!
        components.queryItems = [URLQueryItem(name: "labels", value: label), URLQueryItem(name: "body", value: body)]
        return components.url!
    }

    /// App version, build, macOS version and chip. No server, project or path details.
    static var environment: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let chip = "Apple silicon"
        #else
        let chip = "Intel"
        #endif
        return "Dev Servers \(short) (\(build)) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(chip)"
    }
}

// MARK: - Shared

/// Form row that opens a URL, with a secondary value and an outward arrow.
struct ExternalLinkRow: View {
    let label: String
    let value: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            LabeledContent(label) {
                HStack(spacing: 8) {
                    Text(value).font(Theme.mono)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Title with an optional caption underneath, for form rows.
struct SettingLabel: View {
    let title: String
    let caption: String?

    init(_ title: String, caption: String? = nil) {
        self.title = title
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let caption {
                Text(caption).font(Theme.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The dot-grid colon on the dark app-icon squircle.
struct AppIconView: View {
    var size: CGFloat = 88

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.165, green: 0.176, blue: 0.212), Color(red: 0.067, green: 0.075, blue: 0.094)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            .overlay(DotGridView(glyph: .colon, size: size * 0.68))
            // The app icon remains the same artwork in both appearances.
            .environment(\.colorScheme, .dark)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
    }
}

