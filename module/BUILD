load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Copy this folder to submodules/ChannelRecoveryKit in a Telegram-iOS checkout.
swift_library(
    name = "ChannelRecoveryKit",
    module_name = "ChannelRecoveryKit",
    srcs = glob(["Sources/ChannelRecoveryKit/*.swift"]),
    copts = ["-warnings-as-errors"],
    visibility = ["//visibility:public"],
)
