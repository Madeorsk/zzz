const std = @import("std");
const log = std.log.scoped(.@"zzz/http/router");
const assert = std.debug.assert;

const HTTPError = @import("lib.zig").HTTPError;

const _Route = @import("router/route.zig").Route;

const Capture = @import("router/routing_trie.zig").Capture;
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const Mime = @import("mime.zig").Mime;
const _Context = @import("context.zig").Context;

const _RoutingTrie = @import("router/routing_trie.zig").RoutingTrie;
const QueryMap = @import("router/routing_trie.zig").QueryMap;

/// Error handler type.
pub fn ErrorHandlerFn(comptime Server: type, comptime UserState: type) type {
    const Context = _Context(Server, UserState);
    return *const fn (context: *Context, err: anyerror) anyerror!void;
}

/// Create a default not found handler route.
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

/// Create a default error handler.
pub fn defaultErrorHandler(comptime Server: type, comptime UserState: type) ErrorHandlerFn(Server, UserState) {
    const Context = _Context(Server, UserState);

    return struct { fn f(ctx: *Context, err: anyerror) !void {
        // Handle all default HTTP errors.
        switch (err) {
            HTTPError.ContentTooLarge => {
                try ctx.respond(.{
                    .status = .@"Content Too Large",
                    .mime = Mime.TEXT,
                    .body = "Request was too large.",
                });
            },
            HTTPError.HTTPVersionNotSupported => {
                try ctx.respond(.{
                    .status = .@"HTTP Version Not Supported",
                    .mime = Mime.HTML,
                    .body = "HTTP version not supported.",
                });
            },
            HTTPError.InvalidMethod => {
                try ctx.respond(.{
                    .status = .@"Not Implemented",
                    .mime = Mime.TEXT,
                    .body = "Not implemented.",
                });
            },
            HTTPError.LengthRequired => {
                try ctx.respond(.{
                    .status = .@"Length Required",
                    .mime = Mime.TEXT,
                    .body = "Length required.",
                });
            },
            HTTPError.MalformedRequest => {
                try ctx.respond(.{
                    .status = .@"Bad Request",
                    .mime = Mime.TEXT,
                    .body = "Malformed request.",
                });
            },
            HTTPError.MethodNotAllowed => {
                if (ctx.route) |route| {
                    addAllowHeader: {
                        // We also need to add to Allow header.
                        // This uses the connection's arena to allocate 64 bytes.
                        const allowed = route.get_allowed(ctx.provision.arena.allocator()) catch break :addAllowHeader;
                        ctx.provision.response.headers.putAssumeCapacity("Allow", allowed);
                    }
                }

                try ctx.respond(.{
                    .status = .@"Method Not Allowed",
                    .mime = Mime.TEXT,
                    .body = "Method not allowed.",
                });
            },
            HTTPError.TooManyHeaders => {
                try ctx.respond(.{
                    .status = .@"Request Header Fields Too Large",
                    .mime = Mime.TEXT,
                    .body = "Too many headers.",
                });
            },
            HTTPError.URITooLong => {
                try ctx.respond(.{
                    .status = .@"URI Too Long",
                    .mime = Mime.TEXT,
                    .body = "URI too long.",
                });
            },
            else => {
                try ctx.respond(.{
                    .status = .@"Internal Server Error",
                    .mime = Mime.TEXT,
                    .body = "Internal server error.",
                });
            },
        }
    } }.f;
}

/// A router builder.
pub fn RouterBuilder(comptime Server: type, comptime UserState: type) type {
    return struct {
        const Self = @This();
        const Route = _Route(Server, UserState);
        const ErrorHandler = ErrorHandlerFn(Server, UserState);
        pub const _Router = Router(Server, UserState);

        /// Not found route.
        notFoundRoute: Route = Route.init("").all(defaultNotFoundHandler(Server, UserState)),

        /// Error handler.
        errorHandler: ErrorHandler = defaultErrorHandler(Server, UserState),

        /// Return a new builder with a defined not found handler.
        pub fn withNotFound(comptime self: *const Self, comptime notFoundHandler: ?Route.HandlerFn) Self {
            return Self{
                // Build the not found route: use the provided handler if there is one, or a default one otherwise.
                .notFoundRoute = comptime Route.init("").all(if (notFoundHandler) |handler| handler else defaultNotFoundHandler(Server, UserState)),
                .errorHandler = self.errorHandler,
            };
        }

        /// Return a new builder with a defined error route handler.
        pub fn withError(comptime self: *const Self, comptime errorHandler: ?Route.HandlerFn) Self {
            return Self{
                .notFoundRoute = self.notFoundRoute,
                .errorHandler = if (errorHandler) |handler|  handler else defaultErrorHandler(Server, UserState),
            };
        }

        /// Initialize a router instance.
        pub fn init(self: *const Self, state: UserState, comptime _routes: []const Route) _Router {
            return _Router.init(state, _routes, self.notFoundRoute, self.errorHandler);
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
        const ErrorHandler = ErrorHandlerFn(Server, UserState);
        const Context = _Context(Server, UserState);

        routes: RoutingTrie,
        not_found_route: Route,
        error_handler: ErrorHandler,
        state: UserState,

        pub fn init(state: UserState, comptime _routes: []const Route, notFoundRoute: Route, errorHandler: ErrorHandler) Self {
            const self = Self{
                // Initialize the routing tree from the given routes.
                .routes = comptime RoutingTrie.init(_routes),
                .not_found_route = notFoundRoute,
                .error_handler = errorHandler,
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
