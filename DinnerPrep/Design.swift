import SwiftUI

enum Palette {
    static let paper = Color(red: 246 / 255, green: 243 / 255, blue: 234 / 255)
    static let surface = Color(red: 255 / 255, green: 253 / 255, blue: 248 / 255)
    static let ink = Color(red: 31 / 255, green: 35 / 255, blue: 38 / 255)
    static let muted = Color(red: 97 / 255, green: 88 / 255, blue: 74 / 255)
    static let line = Color(red: 229 / 255, green: 218 / 255, blue: 202 / 255)
    static let accent = Color(red: 217 / 255, green: 162 / 255, blue: 26 / 255)
    static let accentText = Color(red: 128 / 255, green: 86 / 255, blue: 7 / 255)
    static let tint = Color(red: 251 / 255, green: 240 / 255, blue: 213 / 255)
    static let mid = Color(red: 145 / 255, green: 97 / 255, blue: 33 / 255)
    static let soft = Color(red: 166 / 255, green: 122 / 255, blue: 54 / 255)
}

extension View {
    func panel(fill: Color = Palette.surface, radius: CGFloat = 18) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.line, lineWidth: 1).allowsHitTesting(false))
    }

    func pageSurface() -> some View {
        foregroundStyle(Palette.ink)
            .tint(Palette.accentText)
            .background(Palette.paper.ignoresSafeArea())
    }
}

struct DinnerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: primary ? 48 : 44)
            .padding(.horizontal, 12)
            .foregroundStyle(primary && enabled ? Palette.ink : (enabled ? Palette.ink : Palette.muted))
            .background(primary && enabled ? Palette.accent : (primary ? Palette.tint : Palette.surface),
                        in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(primary && enabled ? Palette.accentText : Palette.line))
            .opacity(configuration.isPressed ? 0.95 : 1)
            .contentShape(Rectangle())
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.accentText)
            .padding(.horizontal, 4)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.95 : 1)
    }
}

struct Page<Content: View>: View {
    let title: String
    let detail: String?
    let close: String
    let closeID: String
    let onClose: () -> Void
    let content: () -> Content

    init(_ title: String, detail: String? = nil, close: String = "action.done",
         closeID: String = "page.done", onClose: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.detail = detail
        self.close = close
        self.closeID = closeID
        self.onClose = onClose
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title).font(.title.bold()).accessibilityAddTraits(.isHeader)
                    if let detail { Note(text: detail) }
                }
                Spacer(minLength: 0)
                Button(L.t(close), action: onClose)
                    .buttonStyle(LinkButtonStyle())
                    .accessibilityIdentifier(closeID)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            ScrollView {
                VStack(alignment: .leading, spacing: 14, content: content)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .pageSurface()
    }
}

struct Note: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.footnote)
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct DetailRow: View {
    let title: String
    var detail: String? = nil
    var value: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title).font(.subheadline.weight(.semibold))
                if let detail { Note(text: detail) }
            }
            Spacer(minLength: 6)
            if let value {
                Text(verbatim: value).font(.footnote.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Palette.accentText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
