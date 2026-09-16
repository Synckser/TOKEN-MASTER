import Foundation

/// Traffic-light state of a source's current-window consumption vs its budget.
enum UsageStatus {
    case ok       // plenty of headroom
    case caution  // getting close
    case danger   // near the limit

    var text: String {
        switch self {
        case .ok:      return "OK"
        case .caution: return "Watch"
        case .danger:  return "Near limit"
        }
    }
}
