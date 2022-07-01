const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = std.builtin.Mode.Debug;

    const lib = b.addStaticLibrary("server", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    const local_tests = b.addTest("src/LocalCache.zig");
    local_tests.setBuildMode(mode);

    const server_tests = b.addTest("src/RemoteCacheInstance.zig");
    server_tests.setBuildMode(mode);

    const client_tests = b.addTest("src/CacheClient.zig");
    client_tests.setBuildMode(mode);

    const net_proto_tests = b.addTest("src/netProtocol.zig");
    net_proto_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&local_tests.step);
    test_step.dependOn(&server_tests.step);
    test_step.dependOn(&client_tests.step);
    test_step.dependOn(&net_proto_tests.step);

    const integration_push_test = b.addExecutable("pushTest", "integration-tests/pushTest.zig");
    integration_push_test.addPackagePath("src", "src/main.zig");
    integration_push_test.setBuildMode(mode);
    integration_push_test.install();
    const integration_pull_test = b.addExecutable("pullTest", "integration-tests/pullTest.zig");
    integration_pull_test.addPackagePath("src", "src/main.zig");
    integration_pull_test.setBuildMode(mode);
    integration_pull_test.install();
    const integration_pull_push_os_test = b.addExecutable("pushPullNoAllocTest", "integration-tests/pushPullOnStackTest.zig");
    integration_pull_push_os_test.addPackagePath("src", "src/main.zig");
    integration_pull_push_os_test.setBuildMode(mode);
    integration_pull_push_os_test.install();

    const itest_step = b.step("itest", "Run library integration tests");
    itest_step.dependOn(&integration_pull_push_os_test.run().step);
    itest_step.dependOn(&integration_pull_test.run().step);
    itest_step.dependOn(&integration_push_test.run().step);

    // adding integration tests to standard test
    test_step.dependOn(itest_step);
}
