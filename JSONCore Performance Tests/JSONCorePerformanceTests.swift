//
//  JSONCorePerformanceTests.swift
//  JSONCore
//
//  Created by Tyrone Trevorrow on 27/10/2015.
//  Copyright © 2015 Tyrone Trevorrow. All rights reserved.
//

import XCTest
import JSONCore

class JSONCorePerformanceTests: XCTestCase {
    
    let jsonString: String = {
        let bundle = NSBundle(forClass: JSONCorePerformanceTests.self)
        let path = bundle.pathForResource("1", ofType: "json")
        let data = NSData(contentsOfFile: path!)!
        let jsonString = String.fromCString(unsafeBitCast(data.bytes, UnsafePointer<CChar>.self))!
        
        return jsonString
    }()
    
    var json: JSON?
    
    func testParsePerformanceWithTwoHundredMegabyteFile() {
        measureBlock {
            do {
                self.json = try JSONParser.parse(self.jsonString.unicodeScalars)
                let coordinates = self.json!.object!["coordinates"]!.array!
                let len = coordinates.count
                var x = 0.0; var y = 0.0; var z = 0.0
                
                for coord in coordinates {
                    x = x + (coord.object!["x"]!.double!)
                    y = y + (coord.object!["y"]!.double!)
                    z = z + (coord.object!["z"]!.double!)
                }
                print("\(x / Double(len))")
                print("\(y / Double(len))")
                print("\(z / Double(len))")
            } catch let err {
                if let printableError = err as? CustomStringConvertible {
                    XCTFail("JSON parse error: \(printableError)")
                }
            }
        }
    }
    
    func testSerializerSpeed() {
        if json == nil {
            json = try! JSONParser.parse(self.jsonString)
        }
        
        measureBlock {
            try! JSONSerializer.serializeValue(self.json!)
        }
    }
    
    func testSerializerSpeedPrettyPrinting() {
        if json == nil {
            json = try! JSONParser.parse(self.jsonString)
        }
        
        measureBlock {
            try! JSONSerializer.serializeValue(self.json!, prettyPrint: true)
        }
    }
}
