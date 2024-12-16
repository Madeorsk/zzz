const std = @import("std");
const _Route = @import("route.zig").Route;

/// Routes group builder.
pub fn RoutesGroup(comptime Server: type, comptime AppState: type, comptime _routes: []const _Route(Server, AppState)) type {
    return struct {
        const Self = @This();
        const Route = _Route(Server, AppState);

        _prefix: ?[]const u8 = null,

        /// Add a prefix to the defined routes.
        pub fn prefix(_: *const Self, __prefix: ?[]const u8) Self {
            return Self{
                ._prefix = __prefix,
            };
        }

        /// Get built routes.
        pub fn routes(self: *const Self) []const Route {
            var new_routes: [_routes.len]Route = undefined;

            if (self._prefix) |path_prefix| {
                for (&new_routes, _routes) |*route, original_route| {
                    route.* = original_route.set_path(
                        // Build the new path from path prefix and route path, separated by a slash.
                        std.mem.trim(u8, path_prefix, "/") ++ "/" ++ std.mem.trimLeft(u8, original_route.path, "/")
                    );
                }
            }

            return &new_routes;
        }
    };
}
