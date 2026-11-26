import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum ShareCard {
    enum Content: Equatable {
        case plan(DinnerMath.Result, showTimes: Bool, zone: TimeZone)
        case milestone
    }

    static let size = CGSize(width: 1080, height: 1350)
    static let previewURL = "https://example.com/dinnerprep-preview"

    static func downloadURL(storeID: String) -> String? {
        guard !storeID.isEmpty, storeID.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return "https://apps.apple.com/app/id" + storeID
    }

    static func qr(for url: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }

    static func png(for content: Content, storeID: String) -> Data? {
        let productURL = downloadURL(storeID: storeID)
        guard let code = qr(for: productURL ?? previewURL) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let ink = UIColor(red: 31 / 255, green: 35 / 255, blue: 38 / 255, alpha: 1)
        let accent = UIColor(red: 128 / 255, green: 86 / 255, blue: 7 / 255, alpha: 1)
        let paper = UIColor(red: 251 / 255, green: 240 / 255, blue: 213 / 255, alpha: 1)

        return UIGraphicsImageRenderer(size: size, format: format).pngData { canvas in
            paper.setFill()
            canvas.fill(CGRect(origin: .zero, size: size))

            func label(_ text: String, x: CGFloat = 90, y: CGFloat, width: CGFloat = 900,
                       font: UIFont, color: UIColor? = nil) {
                (text as NSString).draw(with: CGRect(x: x, y: y, width: width, height: 190),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font, .foregroundColor: color ?? ink], context: nil)
            }

            label(L.t("app.name"), y: 85, font: .systemFont(ofSize: 40, weight: .semibold), color: accent)
            switch content {
            case .plan(let result, let showTimes, let zone):
                label(L.t("share.plan"), y: 170, font: .systemFont(ofSize: 94, weight: .bold))
                label(L.minutes(result.total), y: 346, font: .monospacedDigitSystemFont(ofSize: 132, weight: .bold),
                      color: accent)
                label(L.f("share.breakdown", L.minutes(result.recipe), L.minutes(result.prep), L.minutes(result.buffer)),
                      y: 545, font: .systemFont(ofSize: 39, weight: .medium))
                if showTimes {
                    label(L.f("share.times", L.time(result.start, zone: zone), L.time(result.dinner, zone: zone)),
                          y: 740, font: .systemFont(ofSize: 39, weight: .semibold))
                }
            case .milestone:
                label(L.t("share.milestoneHeadline"), y: 200, font: .systemFont(ofSize: 88, weight: .bold))
                label(L.t("share.milestoneCount"), y: 425,
                      font: .monospacedDigitSystemFont(ofSize: 125, weight: .bold), color: accent)
            }

            accent.withAlphaComponent(0.22).setFill()
            canvas.fill(CGRect(x: 90, y: 968, width: 900, height: 3))
            label(L.t("share.hashtags"), y: 1015, width: 590,
                  font: .systemFont(ofSize: 39, weight: .bold), color: accent)
            label(L.t(productURL == nil ? "share.qrPreview" : "share.qrDownload"), y: 1198, width: 590,
                  font: .systemFont(ofSize: 33, weight: .medium))

            let module = max(1, 214 / (code.width + 8))
            let qrSide = CGFloat(code.width * module)
            let quiet = CGFloat(4 * module)
            let box = CGRect(x: 766, y: 1015, width: qrSide + 2 * quiet, height: qrSide + 2 * quiet)
            UIColor.white.setFill()
            canvas.fill(box)
            canvas.cgContext.interpolationQuality = .none
            UIImage(cgImage: code).draw(in: box.insetBy(dx: quiet, dy: quiet))
        }
    }
}
