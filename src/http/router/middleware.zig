const _Context = @import("../context.zig").Context;

/// Type of the next middleware function.
pub fn NextMiddlewareFn(comptime Server: type, comptime AppState: type) type {
    return *const fn (ctx: *_Context(Server, AppState)) anyerror!void;
}

/// Type of a middleware function.
pub fn MiddlewareFn(comptime Server: type, comptime AppState: type) type {
    return *const fn (ctx: *_Context(Server, AppState), next: NextMiddlewareFn(Server, AppState)) anyerror!void;
}
