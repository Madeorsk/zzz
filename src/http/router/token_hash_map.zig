const std = @import("std");
const Token = @import("../routing_trie.zig").Token;

/// Errors of get function.
pub const MapGetErrors = error {
    NotFound,
};

/// Type of a token hash.
pub const Hash = u64;

/// Type of a hash entry in hashed array.
pub const HashEntry = struct{Hash, usize};

/// In-place sort of the given array at compile time.
/// Implementation reference: https://github.com/Koura/algorithms/blob/b1dd07147a34554543994b2c033fae64a2202933/sorting/quicksort.zig
fn sort(A: []HashEntry, lo: usize, hi: usize) void {
    if (lo < hi) {
        const p = partition(A, lo, hi);
        sort(A, lo, @min(p, p -% 1));
        sort(A, p + 1, hi);
    }
}

fn partition(A: []HashEntry, lo: usize, hi: usize) usize {
    // Pivot can be chosen otherwise, for example try picking the first or random
    // and check in which way that affects the performance of the sorting.
    const pivot = A[hi][0];
    var i = lo;
    var j = lo;
    while (j < hi) : (j += 1) {
        if (A[j][0] <= pivot) {
            std.mem.swap(HashEntry, &A[i], &A[j]);
            i += 1;
        }
    }
    std.mem.swap(HashEntry, &A[i], &A[hi]);
    return i;
}

/// Compile-time token hash map.
pub fn TokenHashMap(V: type) type {
    return struct {
        const Self = @This();

        /// Type of a key-value tuple.
        pub const KV = struct {
            Token,
            V,
        };

        /// Sorted array of tokens keys hashes.
        /// Associate a key hash to an index in keys / values array.
        hashes: []const HashEntry,

        /// Keys of the map.
        keys: []const Token,

        /// Values of the map.
        values: []const V,

        /// Hash the given token key.
        fn hashKey(input: Token) Hash {
            const bytes = blk: {
                break :blk switch (input) {
                    .fragment => |inner| inner,
                    .match => |inner| @tagName(inner),
                };
            };

            return std.hash.Wyhash.hash(0, bytes);
        }

        /// Initialize a token hash map with the given key-value tuples.
        pub fn initComptime(comptime kvs: []const KV) Self {
            const arrays = comptime kvs: {
                // Initialize arrays.
                var result = struct {
                    hashes: [kvs.len]HashEntry = undefined,
                    keys: [kvs.len]Token = undefined,
                    values: [kvs.len]V = undefined,
                }{};

                // Add each key-value tuple to the internal map arrays.
                var index = 0;
                for (kvs) |kv| {
                    // Get the current key hash.
                    const hash = hashKey(kv[0]);
                    // Fill keys / values internal arrays.
                    result.hashes[index] = .{ hash, index };
                    result.keys[index] = kv[0];
                    result.values[index] = kv[1];
                    index += 1;
                }

                // Sort the hashes, if there is something to sort.
                if (kvs.len > 0) sort(&result.hashes, 0, kvs.len - 1);

                break :kvs result;
            };

            // Make an HashMap object from initialized arrays.
            return .{
                .hashes = &arrays.hashes,
                .keys = &arrays.keys,
                .values = &arrays.values,
            };
        }

        /// Get the index in keys / values array from the provided token key.
        pub fn getIndex(self: *const Self, key: Token) MapGetErrors!usize {
            // Get the current key hash.
            const hash = hashKey(key);

            // Search in the sorted hashes array.
            const hashIndex = std.sort.binarySearch(HashEntry, hash, self.hashes, {}, struct {
                fn f (_: void, searchedKey: Hash, mid_item: HashEntry) std.math.Order {
                    if (searchedKey < mid_item[0]) return std.math.Order.lt;
                    if (searchedKey > mid_item[0]) return std.math.Order.gt;
                    if (searchedKey == mid_item[0]) return std.math.Order.eq;

                    unreachable;
                }
            }.f);

            // No hash index has been found, return not found.
            if (hashIndex == null) return MapGetErrors.NotFound;

            // Get the index in keys / values in hashes.
            return self.hashes[hashIndex.?][1];
        }

        /// Get the value of a given token key.
        pub fn get(self: *const Self, key: Token) MapGetErrors!V {
            return self.values[try self.getIndex(key)];
        }

        /// Try to get the value of a given token key, return NULL if it doesn't exists.
        pub fn getOptional(self: *const Self, key: Token) ?V {
            return self.get(key) catch null;
        }
    };
}

test TokenHashMap {
    const map = comptime TokenHashMap([]const u8).initComptime(&[_]TokenHashMap([]const u8).KV{
        .{ Token{ .fragment = "route-fragment" }, "route" },
        .{ Token{ .match = .unsigned }, "id" },
        .{ Token{ .match = .remaining }, "remaining" },
    });

    try std.testing.expectEqualStrings("route", try map.get(Token{ .fragment = "route-fragment" }));
    try std.testing.expectEqualStrings("id", try map.get(Token{ .match = .unsigned }));
    try std.testing.expectEqualStrings("remaining", try map.get(Token{ .match = .remaining }));
    try std.testing.expectError(MapGetErrors.NotFound, map.get(Token{ .fragment = "not_found" }));
    try std.testing.expectEqual(null, map.getOptional(Token{ .fragment = "not_found" }));
}