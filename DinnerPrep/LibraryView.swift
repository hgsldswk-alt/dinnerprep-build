import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var screen: Screen
    @State private var notice: String?
    @State private var payload: SharePayload?
    @State private var chooseFile = false
    @State private var working = false

    private enum Screen {
        case list, edit(PrepItem?), manual, preview([PrepTransferItem], fromHome: Bool), paywall
    }

    init(importing values: [PrepTransferItem]? = nil) {
        _screen = State(initialValue: values.map { .preview($0, fromHome: true) } ?? .list)
    }

    var body: some View {
        Group {
            switch screen {
            case .list: library
            case .edit(let item): edit(item)
            case .manual: ManualCodeView(onClose: back, onPreview: showPreview)
            case .preview(let values, let fromHome):
                PrepImportPreview(incoming: values, plan: model.importPlan(values), onClose: {
                    if fromHome { dismiss() } else { back() }
                }) { count in
                    notice = L.f(count == 1 ? "import.doneOne" : "import.done", count)
                    screen = .list
                }
            case .paywall: PaywallView(onClose: back)
            }
        }
        .modifier(PrepFilePicker(isPresented: $chooseFile, reading: $working, onRead: showPreview,
                                 onError: { notice = L.t("import.invalidFile") }))
        .modifier(SharePresentation(payload: $payload))
    }

    private var library: some View {
        Page(L.t("library.title"), detail: L.t("library.subtitle"), closeID: "library.done",
             onClose: { dismiss() }) {
            if let notice { Note(text: notice).accessibilityIdentifier("library.notice") }
            if !model.data.items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(model.data.items) { item in
                        if item.id != model.data.items.first?.id { Divider() }
                        libraryRow(item)
                    }
                }
                .panel()
            } else {
                Note(text: L.t("library.empty"))
            }
            Button(L.t("library.add")) {
                screen = model.canAdd ? .edit(nil) : .paywall
            }
            .buttonStyle(DinnerButtonStyle(primary: true))
            .accessibilityIdentifier("library.add")
            pasteButton
            Button(L.t("library.enterCode")) { screen = .manual }
                .buttonStyle(LinkButtonStyle())
                .accessibilityIdentifier("library.enterCode")
            Button(L.t("library.importFile")) {
                notice = nil
                chooseFile = true
            }
            .buttonStyle(DinnerButtonStyle())
            .disabled(working)
            .accessibilityIdentifier("library.importFile")
            Button(L.t("library.export")) { Task { await export() } }
                .buttonStyle(DinnerButtonStyle())
                .disabled(model.libraryExport.isEmpty || working)
                .accessibilityIdentifier("library.export")
            ShareTestNotice()
        }
    }

    private func libraryRow(_ item: PrepItem) -> some View {
        HStack(spacing: 0) {
            Button {
                screen = model.canEdit(item) ? .edit(item) : .paywall
            } label: {
                DetailRow(title: item.displayName,
                          detail: item.pinned && model.homeItems.prefix(3).contains(where: { $0.id == item.id })
                              ? L.t("library.pinned") : (item.minutes == nil ? L.t("library.estimate") : nil),
                          value: item.minutes.map(L.minutes) ?? L.t("library.setTime"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library.edit." + item.id)
            if item.minutes != nil || model.meal.prep.contains(where: { $0.id == item.id }) {
                let selected = model.meal.prep.contains { $0.id == item.id }
                Button {
                    model.togglePrep(item)
                } label: {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Palette.accentText)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.f("library.selectLabel", item.displayName))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("library.toggle." + item.id)
            }
        }
    }

    @ViewBuilder private var pasteButton: some View {
        if model.test {
            Button(L.t("library.paste")) {
                readCode(ProcessInfo.processInfo.environment["DINNER_TEST_PREP_CODE"] ?? "")
            }
            .buttonStyle(DinnerButtonStyle())
            .accessibilityIdentifier("library.paste")
        } else {
            PasteButton(payloadType: String.self) { values in
                guard let value = values.first else { return }
                readCode(value)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityLabel(L.t("library.paste"))
            .accessibilityIdentifier("library.paste")
        }
    }

    private func edit(_ item: PrepItem?) -> some View {
        PrepEditor(item: item, onClose: back, onSave: { saved in
            if model.saveItem(saved) { back() } else { screen = .paywall }
        }, onDelete: { removed in
            model.removeItem(removed)
            back()
        })
    }

    private func back() {
        notice = nil
        screen = .list
    }

    private func readCode(_ value: String) {
        do {
            showPreview(try PrepCode.decode(value))
        } catch {
            notice = L.t("import.invalid")
        }
    }

    private func showPreview(_ values: [PrepTransferItem]) {
        notice = nil
        screen = .preview(values, fromHome: false)
    }

    private func export() async {
        guard !working else { return }
        working = true
        defer { working = false }
        notice = nil
        model.shareBegan()
        let items = model.libraryExport
        do {
            let bytes = try await Task.detached(priority: .userInitiated) {
                let data = Data(try PrepCode.codes(for: items).joined(separator: "\n").utf8)
                guard data.count <= PrepCode.maxFile else { throw PrepCode.Invalid.limit }
                return data
            }.value
            let file = try await ShareFile.create(bytes, name: "dinner-prep-library.txt")
            if model.test {
                ShareFile.remove(file)
                model.shareFinished(completed: true)
            } else { payload = SharePayload(file: file) }
        } catch {
            notice = L.t("share.failed")
        }
    }
}

private struct PrepImportPreview: View {
    @EnvironmentObject private var model: AppModel
    @State private var plan: PrepImport
    @State private var notice: String?
    let incoming: [PrepTransferItem]
    let onClose: () -> Void
    let onImported: (Int) -> Void

    init(incoming: [PrepTransferItem], plan: PrepImport, onClose: @escaping () -> Void,
         onImported: @escaping (Int) -> Void) {
        self.incoming = incoming
        self.onClose = onClose
        self.onImported = onImported
        _plan = State(initialValue: plan)
    }

    var body: some View {
        Page(L.t("import.title"), detail: L.t("import.subtitle"), close: "action.cancel",
             closeID: "import.cancel", onClose: onClose) {
            let count = plan.accepted.count
            VStack(spacing: 0) {
                ForEach(plan.rows) { row in
                    if row.id > 0 { Divider() }
                    DetailRow(title: row.item.name, detail: status(row.status), value: L.minutes(row.item.minutes))
                }
            }
            .panel()
            Note(text: L.t("import.scope"))
            if plan.skippedLimit > 0 {
                Note(text: L.f("import.limit", count, plan.skippedLimit))
                    .accessibilityIdentifier("import.limited")
            }
            if let notice { Note(text: notice).accessibilityIdentifier("import.notice") }
            Button(L.f(count == 1 ? "import.confirmOne" : "import.confirm", count)) {
                if model.applyImport(plan, incoming: incoming) {
                    onImported(count)
                } else {
                    plan = model.importPlan(incoming)
                    notice = L.t("import.changed")
                }
            }
            .buttonStyle(DinnerButtonStyle(primary: true))
            .disabled(count == 0)
            .accessibilityIdentifier("import.confirm")
        }
    }

    private func status(_ status: PrepImport.Status) -> String? {
        switch status {
        case .available: nil
        case .sameName: L.t("import.sameName")
        case .duplicate: L.t("import.duplicate")
        case .overLimit: L.t("import.overLimit")
        }
    }
}

struct PrepFilePicker: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @Binding var reading: Bool
    let onRead: ([PrepTransferItem]) -> Void
    let onError: () -> Void

    func body(content: Content) -> some View {
        if model.test, let text = ProcessInfo.processInfo.environment["DINNER_TEST_PREP_FILE"] {
            content.onChange(of: isPresented) { _, open in
                guard open else { return }
                isPresented = false
                do { onRead(try PrepCode.decodeFile(Data(text.utf8))) }
                catch { onError() }
            }
        } else {
            content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.plainText], onCompletion: readFile)
        }
    }

    private func readFile(_ result: Result<URL, Error>) {
        let url: URL
        switch result {
        case .success(let selected):
            url = selected
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled { onError() }
            return
        }
        reading = true
        Task {
            defer { reading = false }
            do {
                let values = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    var data = Data()
                    while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
                        guard data.count + chunk.count <= PrepCode.maxFile else { throw PrepCode.Invalid.limit }
                        data.append(chunk)
                    }
                    return try PrepCode.decodeFile(data)
                }.value
                onRead(values)
            } catch {
                onError()
            }
        }
    }
}

struct PrepEditor: View {
    let item: PrepItem?
    let onClose: () -> Void
    let onSave: (PrepItem) -> Void
    let onDelete: (PrepItem) -> Void
    @State private var name: String
    @State private var minutes: String
    @State private var pinned: Bool
    @State private var confirmingDelete = false
    @FocusState private var minutesFocused: Bool

    init(item: PrepItem?, onClose: @escaping () -> Void, onSave: @escaping (PrepItem) -> Void,
         onDelete: @escaping (PrepItem) -> Void) {
        self.item = item
        self.onClose = onClose
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: item?.displayName ?? "")
        _minutes = State(initialValue: item?.minutes.map(String.init) ?? "")
        _pinned = State(initialValue: item?.pinned ?? false)
    }

    private var value: Int? { DinnerMath.parse(minutes, in: 1...DinnerMath.maxMinutes) }
    private var cleanedName: String? { PrepCode.cleanedName(name) }
    private var title: String { item == nil ? L.t("library.add") : L.t("library.edit") }

    var body: some View {
        Page(title, close: "action.cancel", closeID: "prepEdit.cancel", onClose: onClose) {
            if item?.builtIn == true {
                Text(verbatim: name).font(.headline)
            } else {
                TextField(L.t("field.name"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("prepEdit.name")
                if !name.isEmpty && cleanedName == nil { Note(text: L.t("field.nameLimit")) }
            }
            TextField(L.t("field.minutes"), text: $minutes)
                .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                .focused($minutesFocused)
                .accessibilityIdentifier("prepEdit.minutes")
            if value == nil { Note(text: L.f("field.range", 1, DinnerMath.maxMinutes)) }
            Toggle(L.t("library.pin"), isOn: $pinned).accessibilityIdentifier("prepEdit.pin")
            Button(L.t("action.save")) {
                guard let cleanedName, let value else { return }
                var saved = item ?? PrepItem(name: cleanedName)
                if !saved.builtIn { saved.name = cleanedName }
                saved.minutes = value
                saved.pinned = pinned
                onSave(saved)
            }
            .buttonStyle(DinnerButtonStyle(primary: true))
            .disabled(cleanedName == nil || value == nil)
            .accessibilityIdentifier("prepEdit.save")
            if item != nil {
                Button(L.t("action.delete"), role: .destructive) { confirmingDelete = true }
                    .buttonStyle(DinnerButtonStyle())
                    .accessibilityIdentifier("prepEdit.delete")
            }
        }
        .alert(L.t("library.deleteTitle"), isPresented: $confirmingDelete, presenting: item) { item in
            Button(L.t("action.delete"), role: .destructive) { onDelete(item) }
            Button(L.t("action.cancel"), role: .cancel) {}
        } message: { _ in
            Text(L.t("library.deleteHint"))
        }
        .task { if item != nil { minutesFocused = true } }
    }
}

struct ManualCodeView: View {
    let onClose: () -> Void
    let onPreview: ([PrepTransferItem]) -> Void
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        Page(L.t("library.enterCode"), detail: L.t("import.manualHint"), close: "action.cancel",
             closeID: "manual.cancel", onClose: onClose) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(minHeight: 110)
                .padding(6)
                .panel()
                .accessibilityLabel(L.t("import.codeLabel"))
                .accessibilityIdentifier("manual.code")
                .focused($focused)
                .onChange(of: text) { _, value in
                    invalid = false
                    if let values = try? PrepCode.decode(value) { onPreview(values) }
                }
            if invalid { Note(text: L.t("import.invalid")).accessibilityIdentifier("manual.validation") }
            Button(L.t("import.openPreview")) {
                if let values = try? PrepCode.decode(text) { onPreview(values) }
                else { invalid = true }
            }
                .buttonStyle(DinnerButtonStyle(primary: true))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("manual.preview")
        }
        .task { focused = true }
    }
}
