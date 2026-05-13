import Foundation

/// Parses iCalendar (.ics) format calendar events
struct ICSParser {
    /// Parses .ics calendar data and returns an array of CalendarEvent objects
    static func parseEvents(from data: Data) -> [CalendarEvent] {
        guard let icsContent = String(data: data, encoding: .utf8) else {
            return []
        }
        
        return parseEvents(from: icsContent)
    }
    
    /// Parses .ics calendar data (as string) and returns an array of CalendarEvent objects
    static func parseEvents(from icsContent: String) -> [CalendarEvent] {
        var events: [CalendarEvent] = []
        
        // Split the content into individual VEVENT blocks
        let lines = icsContent.components(separatedBy: .newlines)
        var currentEvent: [String] = []
        var inEvent = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine == "BEGIN:VEVENT" {
                inEvent = true
                currentEvent = []
            } else if trimmedLine == "END:VEVENT" {
                inEvent = false
                if let event = parseEvent(from: currentEvent) {
                    events.append(event)
                }
                currentEvent = []
            } else if inEvent {
                currentEvent.append(line)
            }
        }
        
        // Sort events by start date
        return events.sorted { $0.startDate < $1.startDate }
    }
    
    /// Parses a single VEVENT block and returns a CalendarEvent if valid
    private static func parseEvent(from lines: [String]) -> CalendarEvent? {
        var title: String?
        var startDate: Date?
        var endDate: Date?
        var location: String?
        
        for line in lines {
            let components = parseLine(line)
            guard let (key, value) = components else { continue }
            
            switch key {
            case "SUMMARY":
                title = decodeICSText(value)
            case "DTSTART":
                startDate = parseICSDate(value)
            case "DTEND":
                endDate = parseICSDate(value)
            case "LOCATION":
                location = decodeICSText(value)
            default:
                break
            }
        }
        
        // Event must have at least a title and start date
        guard let title = title, let startDate = startDate else {
            return nil
        }
        
        return CalendarEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            location: location
        )
    }
    
    /// Parses a single iCalendar line and returns (key, value)
    private static func parseLine(_ line: String) -> (String, String)? {
        // Handle line folding (lines starting with space/tab are continuations)
        let unfoldedLine = line.replacingOccurrences(of: "\r", with: "")
        
        // Split on the first colon to separate key from value
        let colonIndex = unfoldedLine.firstIndex(of: ":")
        guard let colonIndex = colonIndex else { return nil }
        
        let keyPart = String(unfoldedLine[..<colonIndex])
        let valuePart = String(unfoldedLine[unfoldedLine.index(after: colonIndex)...])
        
        // Extract just the key (ignore parameters like TZID)
        let keyComponents = keyPart.components(separatedBy: ";")
        guard let key = keyComponents.first else { return nil }
        
        return (key, valuePart)
    }
    
    /// Parses iCalendar date format: YYYYMMDD[Thhmmss[Z]]
    private static func parseICSDate(_ dateString: String) -> Date? {
        let dateString = dateString.trimmingCharacters(in: .whitespaces)
        
        // Try parsing with time component
        if dateString.contains("T") {
            // Format: YYYYMMDDTHHMMSSZ or YYYYMMDDTHHMMSS
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            formatter.timeZone = TimeZone(abbreviation: "UTC")
            
            // Remove Z if present
            let cleanString = dateString.replacingOccurrences(of: "Z", with: "")
            if let date = formatter.date(from: cleanString) {
                return date
            }
        }
        
        // Try parsing date only (all-day event)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        return nil
    }
    
    /// Decodes iCalendar text encoding (handles escape sequences)
    private static func decodeICSText(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "\\,", with: ",")
        result = result.replacingOccurrences(of: "\\;", with: ";")
        result = result.replacingOccurrences(of: "\\\\", with: "\\")
        result = result.replacingOccurrences(of: "\\n", with: "\n")
        result = result.replacingOccurrences(of: "\\N", with: "\n")
        return result
    }
}
