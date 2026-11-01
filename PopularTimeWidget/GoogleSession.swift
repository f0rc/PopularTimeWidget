//
//  GoogleSession.swift
//  PopularTimeWidget
//
//  Created by xbox on 10/31/26.
//

import Combine
import Foundation
import Security
import WebKit

@MainActor
class GoogleMapsCookieSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
  enum Connection {
    case disconnected, available, verified
    var label: String {
      switch self {
      case .disconnected: return "Not connected"
      case .available: return "Session saved · not yet verified"
      case .verified: return "Connected · popular times verified"
      }
    }
  }

  @Published var presented = false
  @Published var connection: Connection = .disconnected
  @Published private(set) var loading = false
  @Published var busy = false
  @Published var status = "Connect Google Maps to save a session on this device."
  var cookies: [HTTPCookie] = []
  var operation: Task<Void, Never>?
  private var generation = UUID()
  private(set) var restored = false
  private var pendingConnection = false
  private var captureInProgress = false

  lazy var webView: WKWebView = {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = self
    view.uiDelegate = self
    view.allowsBackForwardNavigationGestures = true
    return view
  }()

  func restore() {
    guard !restored else { return }
    restored = true
    do {
      cookies = try MapsSessionKeychain.load()
      if hasMapsSessionCookies(cookies) {
        connection = .available
        status = "Saved Google session restored; not yet verified."
      }
    } catch { status = error.localizedDescription }
  }

  func connect() {
    guard !busy else { return }
    pendingConnection = true
    presented = true
  }

  func appeared() {
    guard pendingConnection else { return }
    pendingConnection = false
    webView.load(URLRequest(url: URL(string: "https://www.google.com/maps/")!))
    status = "Sign in on Google's page, then tap Use this session."
  }

  func useSession() {
    guard !busy else { return }
    let attempt = beginOperation()
    captureInProgress = true
    operation = Task {
      let captured = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
      guard isCurrent(attempt), presented else { return }
      captureInProgress = false
      let applicable = applicableMapsCookies(captured)
      guard hasMapsSessionCookies(applicable) else {
        status =
          "No signed-in session found. Finish signing in on Google's page. If Google blocks this browser, this connection method cannot continue."
        busy = false
        return
      }
      do {
        try MapsSessionKeychain.save(applicable)
        cookies = applicable
        connection = .available
        busy = false
        presented = false
        status = "Google session saved on this device; not yet verified."
        didSaveSession()
      } catch {
        status = error.localizedDescription
        busy = false
      }
    }
  }

  func didSaveSession() {}

  func disconnect() {
    captureInProgress = false
    let attempt = beginOperation()
    cookies = []
    connection = .disconnected
    status = "Removing this app's Maps session…"
    presented = false
    operation = Task {
      do {
        try MapsSessionKeychain.clear()
        let store = WKWebsiteDataStore.default()
        let all = await store.httpCookieStore.allCookies()
        for cookie in all where Self.isGoogleDomain(cookie.domain) {
          await store.httpCookieStore.deleteCookie(cookie)
        }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let google = records.filter { Self.isGoogleDomain($0.displayName) }
        await store.removeData(ofTypes: types, for: google)
        guard isCurrent(attempt) else { return }
        status = "Disconnected. This app's saved Google session was removed."
      } catch {
        guard isCurrent(attempt) else { return }
        status =
          "Could not finish removing the connection. \(error.localizedDescription) Tap Disconnect to retry."
      }
      if isCurrent(attempt) { busy = false }
    }
  }

  func close() {
    pendingConnection = false
    webView.stopLoading()
    loading = false
    presented = false
    if captureInProgress {
      captureInProgress = false
      operation?.cancel()
      generation = UUID()
      busy = false
    }
  }

  func beginOperation() -> UUID {
    operation?.cancel()
    generation = UUID()
    busy = true
    return generation
  }

  func isCurrent(_ attempt: UUID) -> Bool {
    generation == attempt && !Task.isCancelled
  }

  private static func isGoogleDomain(_ value: String) -> Bool {
    let domain = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return domain == "google.com" || domain.hasSuffix(".google.com")
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    loading = true
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    failed(error)
  }
  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) { failed(error) }
  private func failed(_ error: Error) {
    loading = false
    guard presented, (error as? URLError)?.code != .cancelled else { return }
    status = error.localizedDescription
  }

  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    if navigationAction.targetFrame == nil, navigationAction.request.url?.scheme == "https" {
      webView.load(navigationAction.request)
    }
    return nil
  }
}

enum MapsKeychainError: LocalizedError {
  case failure(OSStatus)
  case invalidData
  var errorDescription: String? {
    switch self {
    case .failure:
      return
        "The device could not access your saved Maps connection. Unlock the device and try again."
    case .invalidData: return "The saved Maps connection could not be read. Reconnect Google Maps."
    }
  }
}

enum MapsSessionKeychain {
  private static let service = "com.example.PopularTimeWidget.maps-session"
  private static var query: [String: Any] {
    let attributes: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "google-maps",
    ]
    return attributes
  }

  static func load() throws -> [HTTPCookie] {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &item)
    if status == errSecItemNotFound { return [] }
    guard status == errSecSuccess else { throw MapsKeychainError.failure(status) }
    guard let data = item as? Data else { throw MapsKeychainError.invalidData }
    return try decodeCookies(data)
  }

  static func save(_ cookies: [HTTPCookie]) throws {
    let data = try encodeCookies(cookies)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var entry = query
      attributes.forEach { entry[$0.key] = $0.value }
      let added = SecItemAdd(entry as CFDictionary, nil)
      guard added == errSecSuccess else { throw MapsKeychainError.failure(added) }
    } else if status != errSecSuccess {
      throw MapsKeychainError.failure(status)
    }
  }

  static func clear() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw MapsKeychainError.failure(status)
    }
  }

  static func encodeCookies(_ cookies: [HTTPCookie]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(applicableMapsCookies(cookies).map { SavedCookie($0) })
  }

  static func decodeCookies(_ data: Data) throws -> [HTTPCookie] {
    let saved: [SavedCookie]
    do { saved = try JSONDecoder().decode([SavedCookie].self, from: data) } catch {
      throw MapsKeychainError.invalidData
    }
    return applicableMapsCookies(saved.compactMap { $0.cookie })
  }

  private struct SavedCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: Date?
    let secure: Bool
    let httpOnly: Bool

    init(_ cookie: HTTPCookie) {
      name = cookie.name
      value = cookie.value
      domain = cookie.domain
      path = cookie.path
      expires = cookie.expiresDate
      secure = cookie.isSecure
      httpOnly = cookie.isHTTPOnly
    }

    var cookie: HTTPCookie? {
      var properties: [HTTPCookiePropertyKey: Any] = [
        .name: name, .value: value, .domain: domain, .path: path,
        .secure: secure ? "TRUE" : "FALSE",
      ]
      if let expires { properties[.expires] = expires }
      if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
      return HTTPCookie(properties: properties)
    }
  }
}

enum MapsSessionError: LocalizedError {
  case missingSession, unavailableCookieStore
  var errorDescription: String? {
    switch self {
    case .missingSession:
      return
        "No signed-in Google session was found in this app. Connect through Google's page first."
    case .unavailableCookieStore: return "An isolated cookie store could not be created."
    }
  }
}

func makeAuthenticatedMapsSession(cookies: [HTTPCookie]) throws -> URLSession {
  let applicable = applicableMapsCookies(cookies)
  let sessionNames: Set<String> = ["SID", "__Secure-1PSID", "__Secure-3PSID"]
  guard applicable.contains(where: { sessionNames.contains($0.name) }) else {
    throw MapsSessionError.missingSession
  }
  let configuration = URLSessionConfiguration.ephemeral
  configuration.timeoutIntervalForRequest = 25
  configuration.timeoutIntervalForResource = 30
  configuration.httpShouldSetCookies = true
  guard let jar = configuration.httpCookieStorage else {
    throw MapsSessionError.unavailableCookieStore
  }
  applicable.forEach { jar.setCookie($0) }
  return URLSession(
    configuration: configuration, delegate: GoogleMapsRedirectPolicy(), delegateQueue: nil)
}

private final class GoogleMapsRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable
{
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

func attachMapsCookies(to request: inout URLRequest, from session: URLSession) throws {
  guard let url = request.url, url.scheme == "https", url.host == "www.google.com",
    url.port == nil || url.port == 443,
    ["/maps/preview/place", "/search"].contains(url.path)
  else { throw PopularTimesError.invalidURL }
  guard let cookies = session.configuration.httpCookieStorage?.cookies(for: url), !cookies.isEmpty,
    let header = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
  else {
    throw MapsSessionError.missingSession
  }
  request.setValue(header, forHTTPHeaderField: "Cookie")
  request.httpShouldHandleCookies = true
}

func applicableMapsCookies(_ cookies: [HTTPCookie], now: Date = Date()) -> [HTTPCookie] {
  cookies.filter { cookie in
    let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return ["google.com", "www.google.com"].contains(domain)
      && (cookie.expiresDate.map { $0 > now } ?? true)
  }
}

func hasMapsSessionCookies(_ cookies: [HTTPCookie]) -> Bool {
  let names: Set<String> = ["SID", "__Secure-1PSID", "__Secure-3PSID"]
  return applicableMapsCookies(cookies).contains { names.contains($0.name) }
}
