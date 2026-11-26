import SwiftUI
import UIKit

struct SharePayload: Identifiable {
    let id = UUID()
    let file: URL
    var caption: String? = nil
}

enum ShareFile {
    static func create(_ data: Data, name: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(name)
            do { try data.write(to: target, options: .atomic) }
            catch {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
            return target
        }.value
    }

    static func remove(_ file: URL) {
        let directory = file.deletingLastPathComponent()
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: directory) }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let payload: SharePayload
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [payload.file]
        if let caption = payload.caption { items.append(caption) }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            Task { @MainActor in onComplete(completed) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SharePresentation: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @Binding var payload: SharePayload?

    func body(content: Content) -> some View {
        content.sheet(item: $payload, onDismiss: { model.shareBegan() }) { item in
            ShareSheet(payload: item) { completed in
                ShareFile.remove(item.file)
                payload = nil
                model.shareFinished(completed: completed)
            }
            .interactiveDismissDisabled()
        }
    }
}

struct ShareTestNotice: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if model.test && model.shareRequested {
            Note(text: L.t("share.prepared")).accessibilityIdentifier("share.requested")
        }
    }
}

struct CardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let timing: DinnerMath.Result?
    let prep: [MealPrep]
    let onClose: (() -> Void)?
    let autoShare: Bool
    @State private var didAutoShare = false
    @State private var showTimes = false
    @State private var artifact: CardArtifact?
    @State private var payload: SharePayload?
    @State private var copied = false
    @State private var issue: String?
    @State private var generating = false

    struct CardArtifact {
        let content: ShareCard.Content
        let data: Data
        let image: UIImage
    }

    init(timing: DinnerMath.Result? = nil, prep: [MealPrep] = [],
         onClose: (() -> Void)? = nil, autoShare: Bool = false) {
        self.timing = timing
        self.prep = prep
        self.onClose = onClose
        self.autoShare = autoShare
    }

    private var content: ShareCard.Content {
        if let timing { return .plan(timing, showTimes: showTimes, zone: model.zone) }
        return .milestone
    }

    private var transferItems: [PrepTransferItem] {
        prep.map { PrepTransferItem(name: $0.displayName, minutes: $0.minutes) }
    }

    var body: some View {
        Page(L.t(timing == nil ? "share.milestone" : "share.plan"), close: "action.close",
             closeID: "share.close", onClose: { if let onClose { onClose() } else { dismiss() } }) {
            if let artifact, artifact.content == content {
                Image(uiImage: artifact.image)
                    .resizable().scaledToFit()
                    .frame(maxWidth: 325)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(cardDescription)
                    .accessibilityIdentifier("share.card")
            } else if issue == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 100)
            }
            if timing != nil {
                Toggle(L.t("share.showTimes"), isOn: $showTimes)
                    .accessibilityIdentifier("share.showTimes")
                Note(text: L.t("share.privacy"))
            }
            Button(L.t("share.image")) { Task { await share() } }
                .buttonStyle(DinnerButtonStyle(primary: true))
                .disabled(artifact?.content != content || generating)
                .accessibilityIdentifier("share.image")
            if !transferItems.isEmpty {
                Button(L.t("share.copyCode")) { copyPrep() }
                    .buttonStyle(DinnerButtonStyle())
                    .accessibilityIdentifier("share.copyCode")
                Note(text: L.t("share.codeContains"))
                ForEach(prep) { item in
                    Note(text: L.f("share.item", item.displayName, L.minutes(item.minutes)))
                }
            }
            Button(L.t("share.copyCaption")) {
                if !model.test { UIPasteboard.general.string = L.t("share.caption") }
                copied = true
            }
            .buttonStyle(LinkButtonStyle())
            .accessibilityIdentifier("share.copyCaption")
            if copied { Note(text: L.t("share.copied")).accessibilityIdentifier("share.copied") }
            if let issue { Note(text: issue) }
            ShareTestNotice()
        }
        .modifier(SharePresentation(payload: $payload))
        .task(id: content) {
            await render(content)
            if autoShare && !didAutoShare && !Task.isCancelled {
                didAutoShare = true
                await share()
            }
        }
    }

    private var cardDescription: String {
        guard let timing else { return L.t("share.milestoneAccessible") }
        let total = L.f("share.accessible", L.minutes(timing.total))
        return showTimes ? total + " " + L.f("share.times", L.time(timing.start, zone: model.zone),
                                                    L.time(timing.dinner, zone: model.zone)) : total
    }

    private func render(_ content: ShareCard.Content) async {
        let storeID = Launch.storeID
        let result = await Task.detached(priority: .userInitiated) { () -> CardArtifact? in
            guard let data = ShareCard.png(for: content, storeID: storeID),
                  let image = UIImage(data: data) else { return nil }
            return CardArtifact(content: content, data: data, image: image.preparingForDisplay() ?? image)
        }.value
        guard !Task.isCancelled else { return }
        if let result {
            artifact = result
            issue = nil
        } else {
            issue = L.t("share.failed")
        }
    }

    private func share() async {
        guard !generating, let artifact, artifact.content == content else { return }
        generating = true
        defer { generating = false }
        model.shareBegan()
        do {
            let file = try await ShareFile.create(artifact.data, name: "dinner-prep.png")
            if model.test {
                ShareFile.remove(file)
                model.shareFinished(completed: true)
            } else {
                payload = SharePayload(file: file, caption: L.t("share.caption"))
            }
        } catch {
            issue = L.t("share.failed")
        }
    }

    private func copyPrep() {
        do {
            let code = try PrepCode.encode(transferItems)
            if !model.test { UIPasteboard.general.string = code }
            copied = true
        } catch {
            issue = L.t("share.codeTooLarge")
        }
    }
}
