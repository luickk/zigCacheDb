const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub fn memToSlice(comptime T: type, ptr: [*]T, len: usize) []T {
    return @ptrCast(*[]T, &.{ .ptr = ptr, .len = len }).*;
}

pub fn reverse_string(str: [*]u8, len: usize) void {
    var start: usize = 0;
    var end: usize = len - 1;
    var temp: u8 = 0;

    while (end > start) {
        temp = str[start];
        str[start] = str[end];
        str[end] = temp;

        start += 1;
        end -= 1;
    }
}

// 20 is u64 max len in u8
pub fn uitoa(num: u64) [20]u8 {
    var str = [_]u8{0} ** 20;

    if (num == 0) {
        str[0] = '0';
        return str;
    }

    var rem: u64 = 0;
    var i: u8 = 0;
    var num_i = num;
    while (num_i != 0) {
        rem = @mod(num_i, 10);
        if (rem > 9) {
            str[i] = @truncate(u8, (rem - 10) + 'a');
        } else {
            str[i] = @truncate(u8, rem + '0');
        }
        i += 1;

        num_i = num_i / 10;
    }
    reverse_string(&str, i);
    return str;
}
