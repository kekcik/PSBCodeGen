import Foundation
import Alamofire

public enum CodeGenError: Error {
    case invalidEnum
    case dataIsEmpty
    case mockError
}

extension String: ParameterEncoding {
    public func encode(_ urlRequest: URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest {
        var request = try urlRequest.asURLRequest()
        request.httpBody = data(using: .utf8, allowLossyConversion: false)
        return request
    }
}

class PSBCodeGen: SessionDelegate {
    static let shared = PSBCodeGen()
    var serverTrustPolicy: ServerTrustPolicy?
    var serverTrustPolicies = [String: ServerTrustPolicy]()
    var manager: Alamofire.SessionManager?

    func configureAlamoFireSSLPinning() {
        guard manager == nil else { return }
        let pathToCert = Bundle.main.paths(forResourcesOfType: "cer", inDirectory: nil)

        let cers = pathToCert.map({ SecCertificateCreateWithData(nil, NSData(contentsOfFile: $0)!)! })

        serverTrustPolicy = ServerTrustPolicy.pinCertificates(
            certificates: cers,
            validateCertificateChain: true,
            validateHost: true)

        serverTrustPolicies = ["ib.psbank.ru": self.serverTrustPolicy!]
        manager = Alamofire.SessionManager(configuration: URLSessionConfiguration.default, delegate: PSBCodeGen(), serverTrustPolicyManager: ServerTrustPolicyManager(policies: self.serverTrustPolicies))
    }

    public var urlHost: String {
        return (SWGHostConfiguration.shared()?.currentHostUrlStr! ?? "") + "/api"
    }
    
    private func applyMock<T: Decodable>(mockString: String, callback: @escaping ((T?, Error?) -> Void), type: T.Type) {
        let mockString = mockString.replacingOccurrences(of: "\"\"", with: "\"").replacingOccurrences(of: "\"", with: "\"\"")
        let delay = Double.random(in: 0.5 ..< 3)
        var delayedArg: T? = nil
        var delayedError: Error? = nil
        if mockString == "400" {
            delayedError = CodeGenError.invalidEnum
        } else if let data = mockString.data(using: .utf8) {
            do {
                let arg = try JSONDecoder().decode(type, from: data)
                delayedArg = arg
            } catch {
                delayedError = error
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            callback(delayedArg, delayedError)
        }
    }

    public func request<T: Decodable>(_ url: String, method: HTTPMethod, encoding: ParameterEncoding? = nil, callback: @escaping ((T?, Error?) -> Void), type: T.Type, mock: String? = nil) {
        configureAlamoFireSSLPinning()
        #if DEBUG
        if let mockString = mock {
            applyMock(mockString: mockString, callback: callback, type: type)
            return
        }
        #endif
        manager?.request(urlHost + url, method: method, headers: defaultHeaders).responseJSON { response in
            do {
                guard
                    let data = response.data
                else {
                    callback(nil, CodeGenError.dataIsEmpty)
                    return
                }

                if response.response?.statusCode == 401 {
                    NotificationCenter.default.post(name: NSNotification.Name(rawValue: "ResponseRecieveHTTPStatusCodeNotAuthorized"), object: nil)
                }
                
                if type is String.Type {
                    let arg = String(data: data, encoding: .utf8)
                    if let argTrimming = arg?.dropFirst().dropLast(), let arg = String(argTrimming) as? T {
                        callback(arg, nil)
                    } else {
//                        error
                    }
                } else {
                    let arg = try JSONDecoder().decode(type, from: data)
                    callback(arg, nil)
                }
            } catch {
                callback(nil, error)
            }
        }
    }

    private var defaultHeaders: HTTPHeaders {
        let token = SWGConfiguration.sharedConfig()?.accessToken ?? ""
        let agent = String.init(format: "Swagger-Codegen/v1/objc (%@; iOS %@; Scale/%0.2f)", [UIDevice.current.model, UIDevice.current.systemVersion, UIScreen.main.scale])
        return [
            "Authorization": "Bearer \(token)",
            "User-Agent": agent
        ]
    }

    public func stopAllRequest() {
        Alamofire.SessionManager.default.session.invalidateAndCancel()
    }
}

extension Decimal {
    public var int: Int {
        return NSDecimalNumber(decimal: self).intValue
    }

    public var double: Double {
        return NSDecimalNumber(decimal: self).doubleValue
    }

    public var number: NSNumber {
        return NSDecimalNumber(decimal: self)
    }
}
