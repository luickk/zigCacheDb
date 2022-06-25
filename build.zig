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

    const integration_test = b.addExecutable("itest", "src/integrationTest.zig");
    integration_test.setBuildMode(mode);
    integration_test.install();
    const run_integration_test = integration_test.run();

    const itest_step = b.step("itest", "Run library integration tests");
    itest_step.dependOn(&run_integration_test.step);
}
