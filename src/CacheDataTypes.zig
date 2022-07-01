pub fn CacheDataTypes(comptime ArgKeyValGenericFn: fn (type, type) type, comptime ArgKeyType: type, comptime ArgValType: type, comptime key_on_stack: bool, comptime val_on_stack: bool) type {
    return struct {
        pub const KeyValGenericFn = ArgKeyValGenericFn(ArgKeyType, ArgValType);
        pub const KeyType: type = ArgKeyType;
        pub const ValType: type = ArgValType;
        pub const key_is_on_stack: bool = key_on_stack;
        pub const val_is_on_stack: bool = val_on_stack;
    };
}
