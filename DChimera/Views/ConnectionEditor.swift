import SwiftUI
import UniformTypeIdentifiers

struct ConnectionEditor: View {
    let request: EditorRequest
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var config: ConnectionConfig
    @State private var password = ""
    @State private var passwordTouched = false
    @State private var hasSavedPassword = false
    @State private var test: TestState = .idle
    @State private var shake: CGFloat = 0
    @State private var avatarBounce = 0

    enum TestState: Equatable {
        case idle, testing, ok(String), failed(String)
    }

    init(request: EditorRequest) {
        self.request = request
        _config = State(initialValue: request.config)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    kindPicker
                    fields
                    colorPicker
                    Toggle(isOn: $config.readOnly) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Read-only").font(.system(size: 13, weight: .semibold))
                            Text("The server rejects writes in this session. Good for production.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .toggleStyle(.switch)
                    testResult
                }
                .padding(20)
            }
            HairlineDivider()
            footer
        }
        .frame(width: 540, height: 640)
        .skinPanel(Theme.sidebar)
        .onAppear {
            hasSavedPassword = !request.isNew && Keychain.hasPassword(for: config.id)
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: 8) {
            AvatarView(initials: config.initials, colorIndex: config.colorIndex, size: 68)
                .shadow(color: Theme.avatarGradients[config.colorIndex % Theme.avatarGradients.count].1.opacity(0.4), radius: 14, y: 6)
                .scaleEffect(avatarBounce % 2 == 0 ? 1 : 1.08)
                .animation(Theme.bouncy, value: avatarBounce)
                .animation(Theme.spring, value: config.colorIndex)
            Text(request.isNew ? "New connection" : "Edit connection")
                .font(.system(size: 17, weight: .bold))
            TextField("Name (optional)", text: $config.name)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
                .frame(width: 260)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.field))
        }
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }

    private var kindPicker: some View {
        HStack(spacing: 10) {
            ForEach(DBKind.allCases) { kind in
                let active = config.kind == kind
                Button {
                    withAnimation(Theme.bouncy) {
                        if config.port == config.kind.defaultPort || config.port == 0 { config.port = kind.defaultPort }
                        config.kind = kind
                        test = .idle
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .symbolEffect(.bounce, value: active)
                        Text(kind.title).font(.system(size: 12, weight: .semibold))
                        if kind == .mysql {
                            Text("beta").font(.system(size: 9, weight: .heavy)).opacity(0.7)
                        }
                    }
                    .foregroundStyle(active ? Theme.onAccent : .primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 78)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(active ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Theme.field))
                            .shadow(color: active ? palette.accent.opacity(0.35) : .clear, radius: 10, y: 4)
                    )
                    .scaleEffect(active ? 1.02 : 1)
                }
                .buttonStyle(SpringButtonStyle(scale: 0.95))
            }
        }
    }

    @ViewBuilder
    private var fields: some View {
        if config.kind == .sqlite {
            FieldGroup {
                FieldRow(label: "File") {
                    HStack {
                        TextField("~/path/to/database.sqlite", text: $config.filePath)
                            .textFieldStyle(.plain)
                            .font(Theme.mono(12.5))
                        Button("Choose…") { chooseFile() }
                        Button("New…") { createFile() }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            FieldGroup {
                FieldRow(label: "Host") {
                    TextField("localhost", text: $config.host).textFieldStyle(.plain)
                }
                FieldRow(label: "Port") {
                    TextField("\(config.kind.defaultPort)", value: $config.port, format: .number.grouping(.never))
                        .textFieldStyle(.plain)
                }
                FieldRow(label: "Database") {
                    TextField(config.kind == .postgres ? "postgres" : "optional", text: $config.database).textFieldStyle(.plain)
                }
                FieldRow(label: "User") {
                    TextField(config.kind == .postgres ? "postgres" : "root", text: $config.user).textFieldStyle(.plain)
                }
                FieldRow(label: "Password", last: false) {
                    SecureField(hasSavedPassword && !passwordTouched ? "•••••••• saved in Keychain" : "password", text: $password)
                        .textFieldStyle(.plain)
                        .onChange(of: password) { _, _ in passwordTouched = true }
                }
                FieldRow(label: "SSL", last: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $config.sslMode) {
                            ForEach(SSLMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(config.sslMode.hint)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 10) {
            Text("Color").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.secondaryText)
            ForEach(0..<Theme.avatarGradients.count, id: \.self) { i in
                Circle()
                    .fill(Theme.avatarGradient(i))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.primary.opacity(config.colorIndex % Theme.avatarGradients.count == i ? 0.8 : 0), lineWidth: 2).padding(-4))
                    .scaleEffect(config.colorIndex % Theme.avatarGradients.count == i ? 1.1 : 1)
                    .onTapGesture {
                        withAnimation(Theme.bouncy) { config.colorIndex = i }
                        avatarBounce += 1
                    }
            }
        }
    }

    @ViewBuilder
    private var testResult: some View {
        switch test {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 10) {
                TypingDots()
                Text("Connecting…").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
            }
            .transition(.opacity)
        case .ok(let version):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.success)
                    .symbolEffect(.bounce, value: version)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connected").font(.system(size: 13, weight: .semibold))
                    Text(version).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.success.opacity(0.1)))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        case .failed(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.danger)
                Text(message)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.danger.opacity(0.1)))
            .modifier(ShakeEffect(travel: shake))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private var footer: some View {
        HStack {
            PillButton(title: test == .testing ? "Testing…" : "Test connection", symbol: "bolt.horizontal.fill") { runTest() }
            Spacer()
            PillButton(title: "Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            PillButton(title: request.isNew ? "Save & open" : "Save", symbol: "checkmark", prominent: true) { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.5)
        }
        .padding(14)
    }

    // MARK: Actions

    private var isValid: Bool {
        config.kind == .sqlite ? !config.filePath.trimmingCharacters(in: .whitespaces).isEmpty
            : !config.host.trimmingCharacters(in: .whitespaces).isEmpty && config.port > 0
    }

    private var effectivePassword: String? {
        if passwordTouched { return password }
        return request.isNew ? nil : Keychain.password(for: config.id)
    }

    private func normalized() -> ConnectionConfig {
        var c = config
        c.host = c.host.trimmingCharacters(in: .whitespaces)
        c.filePath = (c.filePath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        if c.kind == .postgres && c.user.isEmpty { c.user = "postgres" }
        if c.kind == .mysql && c.user.isEmpty { c.user = "root" }
        return c
    }

    private func runTest() {
        withAnimation(Theme.spring) { test = .testing }
        let c = normalized()
        let pw = effectivePassword
        Task {
            do {
                let driver = try await DriverFactory.connect(c, password: pw)
                let version = (try? await driver.serverVersion()) ?? c.kind.title
                await driver.close()
                withAnimation(Theme.bouncy) { test = .ok(version) }
            } catch {
                withAnimation(Theme.spring) { test = .failed(error.localizedDescription) }
                withAnimation(.linear(duration: 0.45)) { shake += 1 }
            }
        }
    }

    private func save() {
        guard isValid else { return }
        let c = normalized()
        app.upsert(c, password: c.kind == .sqlite ? nil : (passwordTouched ? password : nil))
        dismiss()
        if request.isNew {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { app.open(c.id) }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        config.filePath = url.path
        if config.name.isEmpty { config.name = url.deletingPathExtension().lastPathComponent }
    }

    private func createFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "database.sqlite"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try SQLiteDriver(path: url.path, readOnly: false, create: true)
            config.filePath = url.path
            if config.name.isEmpty { config.name = url.deletingPathExtension().lastPathComponent }
        } catch {
            test = .failed(error.localizedDescription)
        }
    }
}

struct FieldGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.field))
    }
}

struct FieldRow<Content: View>: View {
    let label: String
    var last = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 74, alignment: .leading)
            content
                .font(.system(size: 13))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 100) }
        }
    }
}

struct ShakeEffect: GeometryEffect {
    var travel: CGFloat
    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(travel * .pi * 6), y: 0))
    }
}
