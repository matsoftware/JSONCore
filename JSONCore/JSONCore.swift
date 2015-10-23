//
//  JSONCore.swift
//  JSONCore
//
//  Created by Tyrone Trevorrow on 23/10/2015.
//  Copyright © 2015 Tyrone Trevorrow. All rights reserved.
//

// JSONCore: A totally native Swift JSON engine
// Does NOT use NSJSONSerialization. In fact, does not require `import Foundation` at all!

public typealias JSONObject = [String : JSONValue]

public enum JSONNumberType {
    case JSONIntegral(Int64)
    case JSONFloat(Double)
}

public enum JSONValue {
    case JSONNumber(JSONNumberType)
    case JSONNull
    case JSONString(String)
    case JSONObject([String:JSONValue])
    case JSONBool(Bool)
    case JSONArray([JSONValue])
    
    public var string: String? {
        get {
            switch self {
            case .JSONString(let s):
                return s
            default:
                return nil
            }
        }
    }
    
    public var object: [String : JSONValue]? {
        get {
            switch self {
            case .JSONObject(let o):
                return o
            default:
                return nil
            }
        }
    }
    
    public var bool: Bool? {
        get {
            switch self {
            case .JSONBool(let b):
                return b
            default:
                return nil
            }
        }
    }
    
    public var array: [JSONValue]? {
        get {
            switch self {
            case .JSONArray(let a):
                return a
            default:
                return nil
            }
        }
    }
    
    public var int: Int64? {
        get {
            switch self {
            case .JSONNumber(let num):
                switch num {
                case .JSONIntegral(let i):
                    return i
                default:
                    return nil
                }
            default:
                return nil
            }
        }
    }
    
    public var double: Double? {
        get {
            switch self {
            case .JSONNumber(let num):
                switch num {
                case .JSONFloat(let f):
                    return f
                default:
                    return nil
                }
            default:
                return nil
            }
        }
    }
}

public enum JSONParseError: ErrorType, CustomStringConvertible {
    case Unknown
    case EmptyInput
    case UnexpectedCharacter(lineNumber: UInt, characterNumber: UInt)
    case UnterminatedString
    case InvalidUnicode
    case UnexpectedKeyword(lineNumber: UInt, characterNumber: UInt)
    case EndOfFile
    
    public var description: String {
        switch self {
        case .Unknown:
            return "Unknown error"
        case .EmptyInput:
            return "Empty input"
        case .UnexpectedCharacter(let lineNumber, let charNum):
            return "Unexpected character at \(lineNumber):\(charNum)"
        case .UnterminatedString:
            return "Unterminated string"
        case .InvalidUnicode:
            return "Invalid unicode"
        case .UnexpectedKeyword(let lineNumber, let characterNumber):
            return "Unexpected keyword at \(lineNumber):\(characterNumber)"
        default:
            return "Unknown error"
        }
    }
}

private let leftSquareBracket = UnicodeScalar(0x005b)
private let leftCurlyBracket = UnicodeScalar(0x007b)
private let rightSquareBracket = UnicodeScalar(0x005d)
private let rightCurlyBracket = UnicodeScalar(0x007d)
private let colon = UnicodeScalar(0x003A)
private let comma = UnicodeScalar(0x002C)
private let zeroScalar = "0".unicodeScalars.first!
private let negativeScalar = "-".unicodeScalars.first!
private let plusScalar = "+".unicodeScalars.first!
private let decimalScalar = ".".unicodeScalars.first!
private let quotationMark = UnicodeScalar(0x0022)
private let carriageReturn = UnicodeScalar(0x000D)
private let lineFeed = UnicodeScalar(0x000A)
private let whitespace: Set = [UnicodeScalar(0x0009),
    UnicodeScalar(0x000A), UnicodeScalar(0x000D), UnicodeScalar(0x0020)]

// String escapes
private let reverseSolidus = UnicodeScalar(0x005C)
private let solidus = UnicodeScalar(0x002F)
private let backspace = UnicodeScalar(0x0008)
private let formFeed = UnicodeScalar(0x000C)
private let tabCharacter = UnicodeScalar(0x0009)

private let trueToken = [UnicodeScalar]("true".unicodeScalars)
private let falseToken = [UnicodeScalar]("false".unicodeScalars)
private let nullToken = [UnicodeScalar]("null".unicodeScalars)

private let numberScalarSet = Set([UnicodeScalar]("0123456789-.".unicodeScalars))
private let exponentSymbolScalarSet = Set([UnicodeScalar]("eE".unicodeScalars))

private let escapeMap = [
    "/".unicodeScalars.first!: solidus,
    "b".unicodeScalars.first!: backspace,
    "f".unicodeScalars.first!: formFeed,
    "n".unicodeScalars.first!: lineFeed,
    "r".unicodeScalars.first!: carriageReturn,
    "t".unicodeScalars.first!: tabCharacter
]

/*! Turns a JSON data stream into a nested graph of JSONValues
*/

// The structure of this parser is inspired by the great (and slightly insane) NextiveJson parser:
// https://github.com/nextive/NextiveJson
public class JSONParser {
    var generator: String.UnicodeScalarView.Generator
    let data: String.UnicodeScalarView
    var scalar: UnicodeScalar!
    var lineNumber: UInt = 0
    var charNumber: UInt = 0
    
    var crlfHack = false
    
    init(data: String.UnicodeScalarView) {
        generator = data.generate()
        self.data = data
    }
    
    public class func parseData(data: String.UnicodeScalarView) throws -> JSONValue {
        let parser = JSONParser(data: data)
        return try parser.parse()
    }
    
    func parse() throws -> JSONValue {
        do {
            try nextScalar()
        } catch JSONParseError.EndOfFile {
            throw JSONParseError.EmptyInput
        }
        return try nextValue()
    }
    
    func nextScalar() throws {
        if let sc = generator.next() {
            scalar = sc
            charNumber = charNumber + 1
            if crlfHack == true && sc != lineFeed {
                crlfHack = false
            }
        } else {
            throw JSONParseError.EndOfFile
        }
    }
    
    func skipToNextToken() throws {
        if !whitespace.contains(scalar) {
            throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
        }
        
        while whitespace.contains(scalar) {
            try nextScalar()
            if scalar == carriageReturn || scalar == lineFeed {
                if crlfHack == true && scalar == lineFeed {
                    crlfHack = false
                    charNumber = 0
                } else {
                    if (scalar == carriageReturn) {
                        crlfHack = true
                    }
                    lineNumber = lineNumber + 1
                    charNumber = 0
                }
            }
        }
    }
    
    func nextScalars(count: UInt) throws -> [UnicodeScalar] {
        var values = [UnicodeScalar]()
        for _ in 0..<count {
            try nextScalar()
            values.append(scalar)
        }
        return values
    }
    
    func nextValue() throws -> JSONValue {
        if whitespace.contains(scalar) {
            try skipToNextToken()
        }
        switch scalar {
        case leftCurlyBracket:
            return try nextObject()
        case leftSquareBracket:
            return try nextArray()
        case quotationMark:
            return try nextString()
        case trueToken[0], falseToken[0]:
            return try nextBool()
        case nullToken[0]:
            return try nextNull()
        case let s where numberScalarSet.contains(s):
            return try nextNumber()
        default:
            throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
        }
    }
    
    func nextObject() throws -> JSONValue {
        if scalar != leftCurlyBracket {
            throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
        }
        var dictBuilder = [String : JSONValue]()
        try nextScalar()
        if scalar == rightCurlyBracket {
            // Empty object
            return JSONValue.JSONObject(dictBuilder)
        }
        outerLoop: repeat {
            if whitespace.contains(scalar) {
                try skipToNextToken()
            }
            let jsonString = try nextString()
            try nextScalar() // Skip the quotation character
            if whitespace.contains(scalar) {
                try skipToNextToken()
            }
            if scalar != colon {
                throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
            }
            try nextScalar() // Skip the ':'
            let value = try nextValue()
            switch value {
                // Skip the closing character for all values except number, which doesn't have one
            case .JSONNumber:
                break
            default:
                try nextScalar()
            }
            if whitespace.contains(scalar) {
                try skipToNextToken()
            }
            let key = jsonString.string! // We're pretty confident it's a string since we called nextString() above
            dictBuilder[key] = value
            switch scalar {
            case rightCurlyBracket:
                break outerLoop
            case ",".unicodeScalars.first!:
                try nextScalar()
            default:
                throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
            }
            
        } while true
        return JSONValue.JSONObject(dictBuilder)
    }
    
    func nextArray() throws -> JSONValue {
        if scalar != leftSquareBracket {
            throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
        }
        var arrBuilder = [JSONValue]()
        try nextScalar()
        if scalar == rightSquareBracket {
            // Empty array
            return JSONValue.JSONArray(arrBuilder)
        }
        outerLoop: repeat {
            let value = try nextValue()
            arrBuilder.append(value)
            switch value {
                // Skip the closing character for all values except number, which doesn't have one
            case .JSONNumber:
                break
            default:
                try nextScalar()
            }
            if whitespace.contains(scalar) {
                try skipToNextToken()
            }
            switch scalar {
            case rightSquareBracket:
                break outerLoop
            case ",".unicodeScalars.first!:
                try nextScalar()
            default:
                throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
            }
        } while true
        
        return JSONValue.JSONArray(arrBuilder)
    }
    
    func nextString() throws -> JSONValue {
        if scalar != quotationMark {
            throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
        }
        try nextScalar() // Skip pas the quotation character
        var strBuilder = ""
        var escaping = false
        outerLoop: repeat {
            // First we should deal with the escape character and the terminating quote
            switch scalar {
            case reverseSolidus:
                // Escape character
                if escaping {
                    // Escaping the escape char
                    strBuilder.append(reverseSolidus)
                }
                escaping = !escaping
                try nextScalar()
            case quotationMark:
                if escaping {
                    strBuilder.append(quotationMark)
                    escaping = false
                    try nextScalar()
                } else {
                    break outerLoop
                }
            default:
                // Now the rest
                if escaping {
                    // Handle all the different escape characters
                    if let s = escapeMap[scalar] {
                        strBuilder.append(s)
                        try nextScalar()
                    } else if scalar == "u".unicodeScalars.first! {
                        let escapedUnicodeScalar = try nextUnicodeEscape()
                        strBuilder.append(escapedUnicodeScalar)
                        try nextScalar()
                    }
                } else {
                    // Simple append
                    strBuilder.append(scalar)
                    try nextScalar()
                }
            }
        } while true
        return JSONValue.JSONString(strBuilder)
    }
    
    func nextUnicodeEscape() throws -> UnicodeScalar {
        if scalar != "u".unicodeScalars.first! {
            throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
        }
        var readScalar = UInt32(0)
        for _ in 0...3 {
            try nextScalar()
            if ("0".unicodeScalars.first!..."9".unicodeScalars.first!).contains(scalar) {
                readScalar = readScalar + UInt32(scalar.value - "0".unicodeScalars.first!.value)
            } else if ("a".unicodeScalars.first!..."f".unicodeScalars.first!).contains(scalar) {
                let aScalarVal = "a".unicodeScalars.first!.value
                let hexScalarVal = aScalarVal + 10
                let hexVal = scalar.value - hexScalarVal
                readScalar = readScalar + hexVal
            } else if ("A".unicodeScalars.first!..."F".unicodeScalars.first!).contains(scalar) {
                let aScalarVal = "A".unicodeScalars.first!.value
                let hexScalarVal = aScalarVal + 10
                let hexVal = scalar.value - hexScalarVal
                readScalar = readScalar + hexVal
            } else {
                throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
            }
        }
        return UnicodeScalar(readScalar)
    }
    
    func nextNumber() throws -> JSONValue {
        var isNegative = false
        var hasDecimal = false
        var hasDigits = false
        var hasExponent = false
        var positiveExponent = false
        var exponent = 0
        var integer: Int64 = 0
        var decimal: Int64 = 0
        var divisor: Double = 10
        
        outerLoop: repeat {
            switch scalar {
            case "0".unicodeScalars.first!..."9".unicodeScalars.first!:
                hasDigits = true
                if hasDecimal {
                    decimal *= 10
                    decimal += Int64(scalar.value - zeroScalar.value)
                    divisor *= 10
                } else {
                    integer *= 10
                    integer += Int64(scalar.value - zeroScalar.value)
                }
                try nextScalar()
            case negativeScalar:
                if hasDigits || hasDecimal || hasDigits || isNegative {
                    throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
                } else {
                    isNegative = true
                }
                try nextScalar()
            case decimalScalar:
                if hasDecimal {
                    throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
                } else {
                    hasDecimal = true
                }
                try nextScalar()
            case _ where exponentSymbolScalarSet.contains(scalar):
                if hasExponent {
                    throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
                } else {
                    hasExponent = true
                }
                try nextScalar()
                switch scalar {
                case _ where numberScalarSet.contains(scalar):
                    positiveExponent = true
                case plusScalar:
                    positiveExponent = true
                    try nextScalar()
                case negativeScalar:
                    positiveExponent = false
                    try nextScalar()
                default:
                    throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
                }
                exponentLoop: repeat {
                    if scalar.value >= zeroScalar.value && scalar.value <= "9".unicodeScalars.first!.value {
                        exponent *= 10
                        exponent += Int(scalar.value - zeroScalar.value)
                        try nextScalar()
                    } else {
                        break exponentLoop
                    }
                } while true
            default:
                break outerLoop
            }
        } while true
        
        if !hasDigits {
            throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
        }
        
        let sign = isNegative ? -1 : 1
        if hasDecimal {
            divisor /= 10
            var number = Double(sign) * (Double(integer) + (Double(decimal) / divisor))
            if hasExponent {
                if positiveExponent {
                    for _ in 1...exponent {
                        number *= Double(10)
                    }
                } else {
                    for _ in 1...exponent {
                        number /= Double(10)
                    }
                }
            }
            return JSONValue.JSONNumber(JSONNumberType.JSONFloat(number))
        } else {
            var number = Int64(sign) * integer
            if hasExponent {
                if positiveExponent {
                    for _ in 1...exponent {
                        number *= Int64(10)
                    }
                } else {
                    for _ in 1...exponent {
                        number /= Int64(10)
                    }
                }
            }
            return JSONValue.JSONNumber(JSONNumberType.JSONIntegral(number))
        }
    }
    
    func nextBool() throws -> JSONValue {
        var expectedWord: [UnicodeScalar]
        var expectedBool: Bool
        if scalar == trueToken[0] {
            expectedWord = trueToken
            expectedBool = true
        } else if scalar == falseToken[0] {
            expectedWord = falseToken
            expectedBool = false
        } else {
            throw JSONParseError.UnexpectedCharacter(lineNumber: lineNumber, characterNumber: charNumber)
        }
        let word = try [scalar] + nextScalars(UInt(expectedWord.count - 1))
        if word != expectedWord {
            throw JSONParseError.UnexpectedKeyword(lineNumber: lineNumber, characterNumber: charNumber - UInt(expectedWord.count))
        }
        return JSONValue.JSONBool(expectedBool)
    }
    
    func nextNull() throws -> JSONValue {
        let word = try [scalar] + nextScalars(3)
        if word != nullToken {
            throw JSONParseError.UnexpectedKeyword(lineNumber: lineNumber, characterNumber: charNumber-4)
        }
        return JSONValue.JSONNull
    }
}