const std = @import("std");
const log = std.log.scoped(.@"examples/basic");

const zzz = @import("zzz");
const http = zzz.HTTP;

const tardy = zzz.tardy;
const Tardy = tardy.Tardy(.auto);
const Runtime = tardy.Runtime;

const Server = http.Server(.plain, *const i8);
const Router = Server.Router;
const Context = Server.Context;
const Route = Server.Route;

pub fn main() !void {
    const host: []const u8 = "0.0.0.0";
    const port: u16 = 9862;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Creating our Tardy instance that
    // will spawn our runtimes.
    var t = try Tardy.init(.{
        .allocator = allocator,
        .threading = .single,
    });
    defer t.deinit();

    const num: i8 = 12;

    var router = Router.init(&num,
        &[_]Route{
            Route.init("/").get(struct {
                fn handler_fn(ctx: *Context) !void {
                    const body_fmt =
                        \\ <!DOCTYPE html>
                        \\ <html>
                        \\ <body>
                        \\ <h1>Hello, World!</h1>
                        \\ <p>id: {d}</p>
                        \\ </body>
                        \\ </html>
                    ;

                    const body = try std.fmt.allocPrint(ctx.allocator, body_fmt, .{ctx.state.*});

                    // This is the standard response and what you
                    // will usually be using. This will send to the
                    // client and then continue to await more requests.
                    try ctx.respond(.{
                        .status = .OK,
                        .mime = http.Mime.HTML,
                        .body = body[0..],
                    });
                }
            }.handler_fn),

            Route.init("/echo").post(struct {
                fn handler_fn(ctx: *Context) !void {
                    const body = if (ctx.request.body) |b|
                        try ctx.allocator.dupe(u8, b)
                    else
                        "";

                    try ctx.respond(.{
                        .status = .OK,
                        .mime = http.Mime.HTML,
                        .body = body[0..],
                    });
                }
            }.handler_fn),
        }
        ++
        Route.Group(&[_]Route{
            Route.init("bar").get(struct {
                fn handler_fn(ctx: *Context) !void {
                    try ctx.respond(.{
                        .status = .OK,
                        .mime = http.Mime.TEXT,
                        .body = "foo bar",
                    });
                }
            }.handler_fn),
            Route.init("baz").get(struct {
                fn handler_fn(ctx: *Context) !void {
                    try ctx.respond(.{
                        .status = .OK,
                        .mime = http.Mime.TEXT,
                        .body = "foo baz",
                    });
                }
            }.handler_fn),
            Route.init("%s").get(struct {
                fn handler_fn(ctx: *Context) !void {
                    try ctx.respond(.{
                        .status = .OK,
                        .mime = http.Mime.TEXT,
                        .body = ctx.captures[0].string,
                    });
                }
            }.handler_fn)
        }).set_prefix("/foo").add_middleware(struct {
            fn f(ctx: *Context, next: Server.NextMiddlewareFn) !void {
                std.debug.print("before request handler: {?s}\n", .{ctx.request.uri});
                try next(ctx);
                std.debug.print("after request handler: {?s}\n", .{ctx.request.uri});
            }
        }.f).routes(),
        .{
            .not_found_handler = struct {
                fn handler_fn(ctx: *Context) !void {
                    try ctx.respond(.{
                        .status = .@"Not Found",
                        .mime = http.Mime.HTML,
                        .body = "Not Found Handler!",
                    });
                }
            }.handler_fn,
            .error_handler = struct {
                fn handler_fn(ctx: *Context, _: anyerror) !void {
                    try ctx.respond(.{
                        .status = .@"Internal Server Error",
                        .mime = http.Mime.HTML,
                        .body = "Oh no, Internal Server Error!",
                    });
                }
            }.handler_fn,
        }
    );

    // This provides the entry function into the Tardy runtime. This will run
    // exactly once inside of each runtime (each thread gets a single runtime).
    try t.entry(
        &router,
        struct {
            fn entry(rt: *Runtime, r: *const Router) !void {
                var server = Server.init(rt.allocator, .{});
                try server.bind(.{ .ip = .{ .host = host, .port = port } });
                try server.serve(r, rt);
            }
        }.entry,
        {},
        struct {
            fn exit(rt: *Runtime, _: void) !void {
                try Server.clean(rt);
            }
        }.exit,
    );
}
