@main struct PolicyTests {
    static func main() {
        precondition(ChannelPostRecoveryPolicy.isWithinWindow(deletionTimestamp: 1000, localTimestamp: 1000, maximumAge: 100))
        precondition(ChannelPostRecoveryPolicy.isWithinWindow(deletionTimestamp: 1000, localTimestamp: 1099, maximumAge: 100))
        precondition(!ChannelPostRecoveryPolicy.isWithinWindow(deletionTimestamp: 1000, localTimestamp: 1100, maximumAge: 100))
        precondition(!ChannelPostRecoveryPolicy.isWithinWindow(deletionTimestamp: 1000, localTimestamp: 999, maximumAge: 100))
        precondition(!ChannelPostRecoveryPolicy.isWithinWindow(deletionTimestamp: 1000, localTimestamp: 1000, maximumAge: 0))
        precondition(!ChannelPostRecoveryPolicy.isWithinWindow(deletionTimestamp: 1000, localTimestamp: Int64.max, maximumAge: 100))
        print("Native recovery policy: 6 boundary checks passed")
    }
}
