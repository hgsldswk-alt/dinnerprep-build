import Foundation

enum Launch {
    static let freePeriod = false
    static let appID = "com.hgsldswk.dinnerprep"
    static var proID: String { Bundle.main.object(forInfoDictionaryKey: "DinnerProProductID") as? String ?? appID + ".pro" }
    static var trialID: String { Bundle.main.object(forInfoDictionaryKey: "DinnerTrialProductID") as? String ?? appID + ".trial" }
    static var storeID: String {
        Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String ?? ""
    }

    static func isFree(arguments: [String]) -> Bool {
        freePeriod && !(arguments.contains("-ui-testing") &&
            arguments.contains(where: ["-paid-mode", "-paywall", "-expired"].contains))
    }

    static var isFree: Bool { isFree(arguments: ProcessInfo.processInfo.arguments) }
}
