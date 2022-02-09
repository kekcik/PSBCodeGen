import Foundation
import Alamofire

public enum CommonApiError: Error {
    case invalidEnum
    case dataIsEmpty
    case mockError
    case notString
    case wrongFormat
}

extension Date {
    func toCommonApiFormat() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return dateFormatter.string(from: self)
    }
}

extension String: ParameterEncoding {
    public func encode(_ urlRequest: URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest {
        var request = try urlRequest.asURLRequest()
        request.httpBody = data(using: .utf8, allowLossyConversion: false)
        return request
    }
}

class CommonApi: SessionDelegate {
    static let shared = CommonApi()
    var serverTrustPolicy: ServerTrustPolicy?
    var serverTrustPolicies = [String: ServerTrustPolicy]()
    var manager: Alamofire.SessionManager?
    
    func configureAlamoFireSSLPinning() {
        guard manager == nil else { return }
        
        let pathToCert = Bundle(for: CommonApi.self).paths(forResourcesOfType: "cer", inDirectory: "")
        let cers = pathToCert.map({ SecCertificateCreateWithData(nil, NSData(contentsOfFile: $0)!)! })
        
        serverTrustPolicy = ServerTrustPolicy.pinCertificates(
            certificates: cers,
            validateCertificateChain: true,
            validateHost: true)

        serverTrustPolicies = ["ib.psbank.ru": self.serverTrustPolicy!]
        manager = Alamofire.SessionManager(configuration: URLSessionConfiguration.default, delegate: CommonApi(), serverTrustPolicyManager: ServerTrustPolicyManager(policies: self.serverTrustPolicies))
    }
    
    public var urlHost: String {
        guard let urlStr = SWGHostConfiguration.shared()?.currentHostUrlStr
            else { return "" }
        return [urlStr, DevService.devApi].joined(separator: "/")
    }
    
    private func applyMock<T: Decodable>(mockString: String, callback: @escaping ((Result<T>) -> Void), type: T.Type) {
        let mockString = mockString.replacingOccurrences(of: "\"\"", with: "\"").replacingOccurrences(of: "\"", with: "\"\"")
        let delay = Double.random(in: 0.5 ..< 3)
        var delayedArg: T?
        var delayedError: Error?
        if mockString == "400" {
            delayedError = CommonApiError.mockError
        } else if let data = mockString.data(using: .utf8) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let arg = try decoder.decode(type, from: data)
                delayedArg = arg
            } catch {
                delayedError = error
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let error = delayedError {
                callback(.failure(error))
            } else if let arg = delayedArg {
                callback(.success(arg))
            }
        }
    }
    
    public func request<T: Decodable>(
          _ url: String,
          method: HTTPMethod,
          body: Codable? = nil,
          callback: @escaping ((Result<T>) -> Void),
          type: T.Type,
          mock: String? = nil
      ) {
        configureAlamoFireSSLPinning()
        #if DEBUG
        if let mockString = mock {
            applyMock(mockString: mockString, callback: callback, type: type)
            return
        }
        #endif
         
        var encoding: ParameterEncoding {
            if let body = body {
                if body is [Int] || body is Bool || body is String || body is Int64 || body is Int {
                    return CustomEncoding()
                } else {
                    return JSONEncoding.default
                }
            } else {
                return URLEncoding.default
            }
        }

        let parameters = body?.asDictionary ?? [:]
        manager?
            .request(urlHost + url, method: method, parameters: parameters, encoding: encoding, headers: defaultHeaders)
            .validate()
            .responseJSON { response in
                switch response.result {
                case .failure(let error):
                    if response.response?.statusCode == 401 {
                        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "ResponseRecieveHTTPStatusCodeNotAuthorized"), object: nil)
                    } else {
                        callback(.failure(error))
                    }
                case .success:
                    guard let data = response.data else {
                        callback(.failure(CommonApiError.wrongFormat))
                        return
                    }
                    do {
                        let arg = try self.parseResponce(type: type, value: data)
                        callback(.success(arg))
                    } catch {
                        callback(.failure(error))
                    }
                }
        }
    }
    
    private func parseResponce<T>(type: T.Type, value: Data) throws -> T where T: Decodable {
        if type is Data.Type, let result = value as? T {
            return result
        } else if type is String.Type {
            let arg = String(data: value, encoding: .utf8)
            if let argTrimming = arg?.dropFirst().dropLast(), let arg = String(argTrimming) as? T {
                return arg
            } else {
                throw CommonApiError.notString
            }
        } else {
            let decoder = JSONDecoder()
            
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .iso8601)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            decoder.dateDecodingStrategy = .custom({ (decoder) -> Date in
                let container = try decoder.singleValueContainer()
                let dateStr = try container.decode(String.self)
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                if let date = formatter.date(from: dateStr) {
                    return date
                }
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                if let date = formatter.date(from: dateStr) {
                    return date
                }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected date string to be ISO8601-formatted.")
            })
            
            return try decoder.decode(type, from: value)
        }
    }

    private var defaultHeaders: HTTPHeaders {
        let token = SWGConfiguration.sharedConfig()?.accessToken ?? ""
        let agent = String(format: "Swagger-Codegen/v1/objc (%@; iOS %@; Scale/%0.2f)", UIDevice.current.model, UIDevice.current.systemVersion, UIScreen.main.scale)
        return [
            "Authorization": "Bearer \(token)",
            "User-Agent": agent
        ]
    }
    
    public func stopAllRequest() {
        Alamofire.SessionManager.default.session.invalidateAndCancel()
    }
}

public enum Result<Value> {
    case success(Value)
    case failure(Error)
}

/// Convert the parameters into a json array/String/Int/Int64/Bool, and it is added as the request body.
public struct CustomEncoding: ParameterEncoding {
    
    public static let `default` = CustomEncoding()
    
    /// The options for writing the parameters as JSON data.
    public let options: JSONSerialization.WritingOptions
    
    /// Creates a new instance of the encoding using the given options
    ///
    /// - parameter options: The options used to encode the json. Default is []
    ///
    /// - returns: The new instance
    public init(options: JSONSerialization.WritingOptions = []) {
        self.options = options
    }
    
    public func encode(_ urlRequest: Alamofire.URLRequestConvertible, with parameters: Alamofire.Parameters?) throws -> URLRequest {
        var urlRequest = try urlRequest.asURLRequest()
        
        guard
            let parameters = parameters,
            let data = parameters["customParametersKey"] as? Data else {
                print("НЕФИГА")
                return urlRequest
        }
        
        if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        urlRequest.httpBody = data
            
        return urlRequest
    }
}

extension Encodable {
    var asDictionary: [String: Any] {
        if self is [Any] || self is Bool || self is String || self is Int64 || self is Int {
            guard let preData = try? JSONEncoder().encode(self) else { return [:] }
            return ["customParametersKey": preData]
        } else {
            guard let data = try? JSONEncoder().encode(self) else { return [:] }
            return (try? JSONSerialization.jsonObject(with: data, options: .allowFragments)).flatMap { $0 as? [String: Any] } ?? [:]
        }
    }
}
