//
//  Error+Alamofire.swift
//  SwaggerClient
//
//  Created by Igor Dvoeglazov on 06/03/2020.
//  Copyright © 2020 psb. All rights reserved.
//

import Foundation
import Alamofire

public extension Error {
    var httpResponseCode: Int? {
        guard
            let afError = self as? Alamofire.AFError,
            afError.isResponseValidationError else
        {
            return nil
        }
        return afError.responseCode
    }
}
