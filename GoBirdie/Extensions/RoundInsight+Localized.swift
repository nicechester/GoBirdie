//
//  RoundInsight+Localized.swift
//  GoBirdie
//

import Foundation
import GoBirdieCore

extension RoundInsight {
    /// Returns the localized message for this insight, substituting parameters.
    var localizedMessage: String {
        let template = localizationKey.localized
        
        // Order of parameters varies by insight code
        switch code {
        case "SG_PUTTING_CRITICAL", "SG_APPROACH_CRITICAL", "SG_OFF_TEE_CRITICAL",
             "SG_SHORT_GAME_CRITICAL", "SG_PUTTING_STRONG", "SG_APPROACH_STRONG",
             "SG_SHORT_GAME_STRONG", "SG_OFF_TEE_STRONG", "SG_TOTAL_POSITIVE":
            return String(format: template, params["sg"] ?? "")
            
        case "HIGH_FIR_LOW_GIR", "LOW_FIR_HIGH_GIR":
            return String(format: template, params["fir"] ?? "", params["gir"] ?? "")
            
        case "THREE_PUTTS_CRITICAL", "THREE_PUTTS_WARNING", "CONSECUTIVE_BOGEYS",
             "ONE_PUTTS_HIGH", "HIGH_HR_LATE_ROUND":
            return String(format: template, params["count"] ?? params["diff"] ?? "")
            
        case "GOOD_SCRAMBLING":
            return String(format: template, params["gir"] ?? "", params["scramble"] ?? "")
            
        case "POOR_SCRAMBLING":
            return String(format: template, params["missedGir"] ?? "", params["scramble"] ?? "")
            
        case "FRONT_BACK_WORSE":
            return String(format: template, params["front"] ?? "", params["back"] ?? "", params["diff"] ?? "")
            
        case "FRONT_BACK_BETTER":
            return String(format: template, params["diff"] ?? "", params["front"] ?? "", params["back"] ?? "")
            
        case "PAR3_STRUGGLES", "PAR5_SCORING", "PAR5_BIRDIE_MACHINE":
            return String(format: template, params["avg"] ?? "")
            
        case "WORST_CLUB_SG":
            return String(format: template, params["club"] ?? "", params["shots"] ?? "", params["sg"] ?? "")
            
        case "BEST_CLUB_SG":
            return String(format: template, params["club"] ?? "", params["sg"] ?? "", params["shots"] ?? "")
            
        case "DRIVER_INCONSISTENT":
            return String(format: template, params["std"] ?? "")
            
        case "ZERO_THREE_PUTTS":
            return template
            
        case "LONGEST_DRIVE", "DRIVER_DOWN_VS_HISTORY", "DRIVER_UP_VS_HISTORY",
             "APPROACH_WORSE_VS_HISTORY", "APPROACH_BETTER_VS_HISTORY":
            return String(format: template, params["yards"] ?? params["diff"] ?? "")
            
        case "ROUND_DURATION_LONG":
            return String(format: template, params["mins"] ?? "")
            
        default:
            return template
        }
    }
}
