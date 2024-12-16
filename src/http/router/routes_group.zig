const std = @import("std");
const _Route = @import("route.zig").Route;

/// Routes group builder.
pub fn RoutesGroup(comptime Server: type, comptime UserState: type, comptime _routes: []const _Route(Server, UserState)) type {
    return struct {
        const Self = @This();
        const Route = _Route(Server, UserState);

        _prefix: ?[]const u8 = null,

        /// Add a prefix to the defined routes.
        pub fn prefix(_: *const Self, __prefix: ?[]const u8) Self {
            return Self{
                ._prefix = __prefix,
            };
        }

        /// Get built routes.
        pub fn routes(self: *const Self) []const Route {
            var newRoutes: [_routes.len]Route = undefined;

            if (self._prefix) |pathPrefix| {
                for (&newRoutes, _routes) |*route, originalRoute| {
                    route.* = originalRoute.set_path(
                        // Build the new path from path prefix and route path, separated by a slash.
                        std.mem.trim(u8, pathPrefix, "/") ++ "/" ++ std.mem.trimLeft(u8, originalRoute.path, "/")
                    );
                }
            }

            return &newRoutes;
        }
    };
}
