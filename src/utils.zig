// todo: bounds check?
pub fn memToSlice(comptime T: type, ptr: [*]T, len: usize) []T {
    return @ptrCast(*[]T, &.{ .ptr = ptr, .len = len }).*;
}
