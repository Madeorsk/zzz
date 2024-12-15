const std = @import("std");
const log = std.log.scoped(.@"zzz/http/router");
const assert = std.debug.assert;

const _Route = @import("router/route.zig").Route;

const Capture = @import("router/routing_trie.zig").Capture;
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const Mime = @import("mime.zig").Mime;
const _Context = @import("context.zig").Context;

const _RoutingTrie = @import("router/routing_trie.zig").RoutingTrie;
const QueryMap = @import("router/routing_trie.zig").QueryMap;

pub fn defaultNotFoundHandler(comptime Server: type, comptime UserState: type) _Route(Server, UserState).HandlerFn {
    const Context = _Context(Server, UserState);

    return struct {
        fn not_found_handler(ctx: *Context) !void {
            try ctx.respond(.{
                .status = .@"Not Found",
                .mime = Mime.TEXT,
                .body = "Not found.",
            });
        }
    }.not_found_handler;
}

/// A router builder.
pub fn RouterBuilder(comptime Server: type, comptime UserState: type) type {
    return struct {
        const Self = @This();
        const Route = _Route(Server, UserState);
        pub const _Router = Router(Server, UserState);

        /// Not found route.
        notFoundRoute: Route = Route.init("").all(defaultNotFoundHandler(Server, UserState)),

        /// Return a new builder with a defined not found handler.
        pub fn withNotFound(comptime _: *const Self, comptime notFoundHandler: ?Route.HandlerFn) Self {
            return Self{
                // Build the not found route: use the provided handler if there is one, or a default one otherwise.
                .notFoundRoute = comptime Route.init("").all(if (notFoundHandler) |handler| handler else defaultNotFoundHandler(Server, UserState)),
            };
        }

        /// Initialize a router instance.
        pub fn init(self: *const Self, state: UserState, comptime _routes: []const Route) _Router {
            return _Router.init(state, _routes, self.notFoundRoute);
        }
    };
}

/// Get the default router builder instance.
pub fn DefaultRouterBuilder(comptime Server: type, comptime UserState: type) RouterBuilder(Server, UserState) {
    return RouterBuilder(Server, UserState){};
}

/// Initialize a router with the given routes.
pub fn Router(comptime Server: type, comptime UserState: type) type {
    return struct {
        const Self = @This();
        const RoutingTrie = _RoutingTrie(Server, UserState);
        const FoundRoute = RoutingTrie.FoundRoute;
        const Route = _Route(Server, UserState);
        const Context = _Context(Server, UserState);

        routes: RoutingTrie,
        not_found_route: Route,
        state: UserState,

        pub fn init(state: UserState, comptime _routes: []const Route, notFoundRoute: Route) Self {
            const self = Self{
                // Initialize the routing tree from the given routes.
                .routes = comptime RoutingTrie.init(_routes),
                .not_found_route = notFoundRoute,
                .state = state,
            };

            return self;
        }

        pub fn get_route_from_host(self: Self, path: []const u8, captures: []Capture, queries: *QueryMap) !FoundRoute {
            return try self.routes.get_route(path, captures, queries) orelse {
                queries.clearRetainingCapacity();
                return FoundRoute{ .route = self.not_found_route, .captures = captures[0..0], .queries = queries };
            };
        }
    };
}
