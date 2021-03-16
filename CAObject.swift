import Foundation

public class CAObject: Codable {

    public var info: [String: Any] = [:]
    
    init(info: [String: Any]) {
        self.info = info
    }
    
    public required init(from decoder: Decoder) throws {
        self.info = decodeUnknownKeys(from: decoder)
    }
    
    public func encode(to encoder: Encoder) throws {
        encodeUnknownKeys(to: encoder)
    }
    
    // MARK: - Private
    
    private func decodeUnknownKeys(from decoder: Decoder) -> [String: Any] {
        guard let container = try? decoder.container(keyedBy: UnknownCodingKey.self) else { return [:] }
        var unknownKeyValues: [String: Any] = [:]

        for key in container.allKeys {
            func decodeUnknownValue<T: Decodable>(_ type: T.Type) -> Bool {
                if let value = try? container.decode(type, forKey: key) {
                    unknownKeyValues[key.stringValue] = value.removedCAObject
                    return true
                } else if let values = try? container.decode([T].self, forKey: key) {
                    unknownKeyValues[key.stringValue] = values.removedCAObject
                    return true
                }
                return false
            }
            
            if decodeUnknownValue(String.self) { continue }
            if decodeUnknownValue(Bool.self) { continue }
            if decodeUnknownValue(Int.self)    { continue }
            if decodeUnknownValue(Double.self) { continue }
            
            if decodeUnknownValue([CAObject].self) { continue }
            if decodeUnknownValue(CAObject.self) { continue }
        }

        return unknownKeyValues
    }
    
    private func encodeUnknownKeys(to encoder: Encoder) {
        var container = encoder.container(keyedBy: UnknownCodingKey.self)
 
        for (key, value) in info {
            func encodeUnknownValue<T: Encodable>(_ type: T.Type, encodableValue: T? = nil) -> Bool {
                guard let codingKey = UnknownCodingKey(stringValue: key) else { return false }
                
                if let encodableValue = encodableValue ?? value as? T, (try? container.encode(encodableValue, forKey: codingKey)) != nil {
                    return true
                } else if let encodableArray = value as? [T], (try? container.encode(encodableArray, forKey: codingKey)) != nil {
                    return true
                }
        
                return false
            }
            
            if encodeUnknownValue(String.self) { continue }
            if encodeUnknownValue(Bool.self) { continue }
            if encodeUnknownValue(Int.self) { continue }
            if encodeUnknownValue(Double.self) { continue }
            
            if let array = value as? [[String: Any]], encodeUnknownValue([CAObject].self, encodableValue: array.map(CAObject.init(info:))) { continue }
            if let info = value as? [String: Any], encodeUnknownValue(CAObject.self, encodableValue: CAObject(info: info)) { continue }
        }
    }
}

private struct UnknownCodingKey: CodingKey {
    
    let stringValue: String
    var intValue: Int? { nil }
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init?(intValue: Int) { nil }

}

private extension Decodable {
    
    var removedCAObject: Any {
        switch self {
        case let object as CAObject:
            return object.info
        case let array as [CAObject]:
            return array.map(\.info)
        default:
            return self
        }
    }
    
}
