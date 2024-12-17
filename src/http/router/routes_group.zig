const std = @import("std");
const _Route = @import("route.zig").Route;
const _MiddlewareFn = @import("middleware.zig").MiddlewareFn;

/// Routes group builder.
pub fn RoutesGroup(comptime Server: type, comptime AppState: type, comptime _routes: []const _Route(Server, AppState)) type {
    return struct {
        const Self = @This();
        const Route = _Route(Server, AppState);
        const MiddlewareFn = _MiddlewareFn(Server, AppState);

        /// A prefix to use for the routes.
        prefix: ?[]const u8 = null,

        /// The middlewares functions to call.
        middlewares: []const MiddlewareFn = &[0]MiddlewareFn{},

        /// Add a prefix to the defined routes.
        pub fn set_prefix(self: *const Self, new_prefix: ?[]const u8) Self {
            return Self{
                .prefix = new_prefix,
                .middlewares = self.middlewares,
            };
        }

        /// Set the middlewares to apply on the defined routes.
        /// The last middleware will be called first.
        pub fn set_middlewares(self: *const Self, routes_middlewares: []const MiddlewareFn) Self {
            return Self{
                .prefix = self.prefix,
                .middlewares = routes_middlewares,
            };
        }

        /// Add a middleware to the defined routes.
        /// The lastly added middleware will be called first.
        pub fn add_middleware(self: *const Self, middleware: MiddlewareFn) Self {
            return self.set_middlewares(self.middlewares ++ .{middleware});
        }

        /// Get built routes.
        pub fn routes(self: *const Self) []const Route {
            // Prepare new routes array.
            var new_routes: [_routes.len]Route = comptime copy_routes: {
                var new_routes: [_routes.len]Route = undefined;

                for (&new_routes, _routes) |*route, original_route| {
                    route.* = original_route;
                }

                break :copy_routes new_routes;
            };

            // Set the defined prefix.
            if (self.prefix) |path_prefix| {
                for (&new_routes) |*route| {
                    route.* = route.set_path(
                        // Build the new path from path prefix and route path, separated by a slash.
                        std.mem.trim(u8, path_prefix, "/") ++ "/" ++ std.mem.trimLeft(u8, route.path, "/")
                    );
                }
            }

            // Apply all the defined middlewares.
            if (self.middlewares.len > 0) {
                for (&new_routes) |*route| {
                    route.* = route.apply_middlewares(self.middlewares);
                }
            }

            // Return built routes.
            return &new_routes;
        }
    };
}
