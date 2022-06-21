const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("server", "src/server.zig");
    lib.addObjectFile("src/local.zig");
    lib.addObjectFile("src/client.zig");
    lib.addObjectFile("src/netProtocol.zig");
    lib.setBuildMode(mode);
    lib.install();

    const local_tests = b.addTest("src/local.zig");
    local_tests.setBuildMode(mode);

    const server_tests = b.addTest("src/server.zig");
    server_tests.setBuildMode(mode);

    const client_tests = b.addTest("src/client.zig");
    client_tests.setBuildMode(mode);

    const net_proto_tests = b.addTest("src/netProtocol.zig");
    net_proto_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&local_tests.step);
    test_step.dependOn(&server_tests.step);
    test_step.dependOn(&client_tests.step);
    test_step.dependOn(&net_proto_tests.step);
}
