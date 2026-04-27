
import Foundation
import UIKit
import Vision

class OCRManager: NSObject {
    static let shared = OCRManager()
    
    typealias OCRCompletion = (Result<String, Error>) -> Void
    
    // MARK: - Core OCR
    func performOCR(on image: UIImage, completion: @escaping OCRCompletion) {
        guard let cgImage = image.cgImage else {
            completion(.failure(NSError(domain: "OCRManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])))
            return
        }
        
        // Use revision 3 for iOS 16+ (better at small text)
        let request = VNRecognizeTextRequest { (request, error) in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(.success(""))
                return
            }
            
            // Get top candidate for each observation
            let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            completion(.success(recognizedText))
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false // CRITICAL: prevent "correcting" numbers to words
        if #available(iOS 16.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Validation
    private func isValidLuhn(_ number: String) -> Bool {
        let digits = number.compactMap { Int(String($0)) }
        guard digits.count >= 13 && digits.count <= 19 else { return false }
        
        var sum = 0
        let reversedDigits = digits.reversed()
        
        for (index, digit) in reversedDigits.enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }
    
    // Check if number starts with known IIN/BIN ranges (Issuer Identification Number)
    private func hasValidBIN(_ number: String) -> Bool {
        // Visa: 4
        if number.hasPrefix("4") { return true }
        // Mastercard: 51-55, 2221-2720
        if number.hasPrefix("5") || number.hasPrefix("2") { return true }
        // Amex: 34, 37
        if number.hasPrefix("34") || number.hasPrefix("37") { return true }
        // Discover: 6
        if number.hasPrefix("6") { return true }
        
        return false
    }
    
    // MARK: - Parse
    func parseCreditCard(from text: String) -> [String: String]? {
        print("🔍 === OCR PARSE START (STRICT MODE) ===")
        print(text)
        print("🔍 === OCR PARSE END ===")
        
        var cardNumber: String?
        var expiry: String?
        var name: String?
        
        let lines = text.components(separatedBy: .newlines)
        
        // ------------------------------------------------------------------
        // STEP 1: Strict Line Matching (Best Case)
        // Look for typical line: "4111 1111 1111 1111"
        // ------------------------------------------------------------------
        for line in lines {
            let cleanLine = line.replacingOccurrences(of: " ", with: "")
            let digitsOnly = cleanLine.filter { $0.isNumber }
            
            // Heuristic: Line must be mostly digits (e.g. allow a few garbage chars but not many)
            if digitsOnly.count >= 13 && digitsOnly.count <= 19 {
                 // Check if it's purely digits or close to it
                 if cleanLine.count <= digitsOnly.count + 2 { 
                     // Check BIN + Luhn
                     if hasValidBIN(digitsOnly) && isValidLuhn(digitsOnly) {
                         print("✅ STRICT MATCH (Single Line): \(digitsOnly)")
                         cardNumber = digitsOnly
                         break
                     }
                 }
            }
        }
        
        // ------------------------------------------------------------------
        // STEP 2: Adjacent Groups (for cards with wide spacing)
        // E.g.
        // 4111
        // 1111
        // ...
        // ------------------------------------------------------------------
        if cardNumber == nil {
             // Find all groups of 3-4 digits in the text
             // We flatten the text but preserve relative ordering
             let allWords = text.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
             var digitGroups: [String] = []
             
             for word in allWords {
                 let digits = word.filter { $0.isNumber }
                 // Only accept groups that look like blocks of a card number
                 if digits.count >= 3 && digits.count <= 6 {
                     digitGroups.append(digits)
                 }
             }
             
             // Try combining 3 or 4 adjacent groups
             if digitGroups.count >= 3 {
                 for i in 0...(digitGroups.count - 3) {
                     // Try 3 groups (e.g. Amex often 4-6-5)
                     let combined3 = digitGroups[i] + digitGroups[i+1] + digitGroups[i+2]
                     if combined3.count >= 13 && combined3.count <= 19 && hasValidBIN(combined3) && isValidLuhn(combined3) {
                         print("✅ STRICT MATCH (3 Groups): \(combined3)")
                         cardNumber = combined3
                         break
                     }
                     
                     // Try 4 groups (Standard)
                     if i + 3 < digitGroups.count {
                         let combined4 = combined3 + digitGroups[i+3]
                         if combined4.count >= 13 && combined4.count <= 19 && hasValidBIN(combined4) && isValidLuhn(combined4) {
                             print("✅ STRICT MATCH (4 Groups): \(combined4)")
                             cardNumber = combined4
                             break
                         }
                     }
                 }
             }
        }
        
        // NOTE: Removed "Sliding Window Brute Force" as it causes "invented" numbers
        
        guard let finalNumber = cardNumber else {
            print("❌ No strict match found")
            return nil
        }
        
        let formattedNumber = formatCardNumber(finalNumber)
        print("💳 Final Number: \(formattedNumber)")
        
        // ------------------------------------------------------------------
        // EXTRACT EXPIRY
        // ------------------------------------------------------------------
        // Look for XX/XX or XX/XXXX
        let expiryPatterns = [
            "\\b(0[1-9]|1[0-2])\\s*/\\s*(2[0-9])\\b",      // 12/25
            "\\b(0[1-9]|1[0-2])\\s*/\\s*(20[2-9][0-9])\\b"  // 12/2025
        ]
        
        for pattern in expiryPatterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                expiry = String(text[range]).replacingOccurrences(of: " ", with: "")
                print("📅 Expiry: \(expiry ?? "N/A")")
                break
            }
        }
        
        // ------------------------------------------------------------------
        // EXTRACT NAME
        // ------------------------------------------------------------------
        // Heuristic: Uppercase line, no digits, ignored words
        let skipWords = ["VISA", "MASTER", "MASTERCARD", "AMEX", "AMERICAN", "EXPRESS", "DEBIT", "CREDIT", "CARD", "VALID", "THRU", "GOOD", "MEMBER", "SINCE", "VALIDE", "VENCE", "HASTA", "DESDE", "BANK", "BANCO", "BC", "BUSINESS", "PLATINUM", "GOLD", "TITANIUM", "WORLD", "ELITE", "SIGNATURE", "INFINITE", "REWARDS", "POINTS", "CORPORATE", "ELECTRON"]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count < 4 { continue } // Too short
            
            // Must not have digits
            if trimmed.contains(where: { $0.isNumber }) { continue }
            
            // Must be largely uppercase
            let uppercaseCount = trimmed.filter { $0.isUppercase }.count
            if Double(uppercaseCount) / Double(trimmed.count) < 0.8 { continue } // Allow some spaces/dots
            
            // Check against skip words
            let upper = trimmed.uppercased()
            let containsSkipWord = skipWords.contains { word in
                upper.range(of: "\\b\(word)\\b", options: .regularExpression) != nil
            }
            
            if !containsSkipWord {
                // Must look like name (space or dot)
                if trimmed.contains(" ") || trimmed.contains(".") {
                    name = trimmed
                    print("👤 Name: \(name ?? "N/A")")
                    break
                }
            }
        }
        
        return [
            "number": formattedNumber,
            "expiry": expiry ?? "",
            "name": name ?? ""
        ]
    }
    
    private func formatCardNumber(_ number: String) -> String {
        let digits = number.filter { $0.isNumber }
        var formatted = ""
        for (index, char) in digits.enumerated() {
            if index > 0 && index % 4 == 0 {
                formatted += " "
            }
            formatted.append(char)
        }
        return formatted
    }
}
