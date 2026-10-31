//
//  GoogleMapsSession.swift
//  PopularTimeWidget
//
//  Created by xbox on 10/31/26.
//

import Foundation
import WebKit

enum MapsSessionError: LocalizedError {
    case missingSession, unavailableCookieStore
    var errorDescription: String? {
        switch self {
        case .missingSession: return "No Google session was found. Connect through Google's page first."
        case .unavailableCookieStore: return "Couldn't create cookie"
        }
    }
}

