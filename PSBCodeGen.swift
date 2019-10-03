import Foundation
import Alamofire

public enum CodeGenError: Error {
    case invalidEnum
    case dataIsEmpty
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

    public func request<T: Decodable>(_ url: String, method: HTTPMethod, encoding: ParameterEncoding? = nil, callback: @escaping ((T?, Error?) -> Void), type: T.Type) {
        configureAlamoFireSSLPinning()
        manager?.request(urlHost + url, method: method, headers: defaultHeaders).responseJSON { response in
            do {
                guard
                    let data = response.data
                else {
                    callback(nil, CodeGenError.dataIsEmpty)
//                    errorCB?(CodeGenError.dataIsEmpty)
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
