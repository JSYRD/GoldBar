import Cocoa

/// A formatter that strips all newline and carriage-return characters,
/// enforcing single-line input. Works for both typed and pasted text.
final class SingleLineFormatter: Formatter {

    override func string(for obj: Any?) -> String? {
        obj as? String
    }

    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        let cleaned = string.components(separatedBy: CharacterSet.newlines).joined()
        obj?.pointee = cleaned as AnyObject
        return true
    }

    override func isPartialStringValid(
        _ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
        proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
        originalString origString: String,
        originalSelectedRange origSelRange: NSRange,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        let partial = partialStringPtr.pointee as String
        let cleaned = partial.components(separatedBy: CharacterSet.newlines).joined()

        if cleaned != partial {
            partialStringPtr.pointee = cleaned as NSString
        }
        return true
    }
}
