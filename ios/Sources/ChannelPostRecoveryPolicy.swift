/// Local display gate only. The server remains authoritative about expiry.
enum ChannelPostRecoveryPolicy {
    static func isWithinWindow(deletionTimestamp: Int32, localTimestamp: Int64, maximumAge: Int32) -> Bool {
        guard maximumAge > 0, localTimestamp >= Int64(deletionTimestamp) else {
            return false
        }
        // Avoid subtraction overflow for malformed local clock values.
        return localTimestamp < Int64(deletionTimestamp) + Int64(maximumAge)
    }
}
