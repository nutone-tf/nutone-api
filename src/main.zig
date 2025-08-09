const std = @import("std");
const httpz = @import("httpz");
const zqlite = @import("zqlite");
const queries = @import("queries.zig");
const utility = @import("utility.zig");
const KillData = @import("types.zig").KillData;
const Filters = @import("types.zig").Filters;

const dbFlags = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode;
var connPtr: *const zqlite.Conn = undefined;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    var conn = try zqlite.open("./nutone.db", dbFlags);
    connPtr = &conn;
    const allocator = gpa.allocator();
    var server = try httpz.Server(void).init(allocator, .{ .port = 17274 }, {});
    defer {
        conn.close();
        server.stop();
        server.deinit();
    }
    try initDB();
    const cors = try server.middleware(httpz.middleware.Cors, .{
        .origin = "https://nutone.okudai.dev/",
    });
    var router = try server.router(.{ .middlewares = &.{cors} });

    router.get("/v1/players/:id", getPlayerData, .{});
    router.get("/v1/players", getAllPlayerData, .{});
    router.get("/v1/servers", getServerList, .{});
    router.post("/v1/data", insertServerData, .{});

    try server.listen();
}

fn initDB() !void {
    var conn = connPtr.*;
    try conn.exec(queries.Create.Table.Tokens, .{});
    try conn.exec(queries.Create.Table.Players, .{});
    try conn.exec(queries.Create.Table.Matches, .{});
    try conn.exec(queries.Create.Table.Servers, .{});
    try conn.exec(queries.Create.Table.KillData, .{});

    try conn.exec(queries.Create.Index.KillDataTimestamp, .{});
    try conn.exec(queries.Create.Index.KillDataServer, .{});
    try conn.exec(queries.Create.Index.KillDataAttacker, .{});
    try conn.exec(queries.Create.Index.KillDataVictim, .{});
}

fn insertServerData(req: *httpz.Request, res: *httpz.Response) !void {
    var conn = connPtr.*;
    var serverToken: ?[]const u8 = null;
    const allocator = gpa.allocator();
    var writeStream = std.json.writeStream(res.writer(), .{});
    var parsedData: ?std.json.Parsed(KillData) = null;
    defer if (parsedData) |pD| pD.deinit();

    if (try utility.isValidToken(conn, req)) {
        serverToken = req.header("token").?;
        if (req.body()) |kill| {
            parsedData = utility.readKillData(allocator, kill) catch {
                try writeStream.beginObject();
                try writeStream.objectField("info");
                try writeStream.beginObject();
                try writeStream.objectField("status");
                try writeStream.write(400);
                try writeStream.objectField("description");
                try writeStream.write("BAD REQUEST");
                try writeStream.endObject();
                try writeStream.endObject();
                res.status = 400;
                res.content_type = httpz.ContentType.JSON;
                return;
            };
        } else {
            try writeStream.beginObject();
            try writeStream.objectField("info");
            try writeStream.beginObject();
            try writeStream.objectField("status");
            try writeStream.write(418);
            try writeStream.objectField("description");
            try writeStream.write("I'M A TEAPOT");
            try writeStream.endObject();
            try writeStream.endObject();
            res.status = 418;
            res.content_type = httpz.ContentType.JSON;
            return;
        }
        if (parsedData) |pD| {
            const data = pD.value;
            if (!try utility.isValidServer(conn, serverToken.?, data.server_id)) {
                try writeStream.beginObject();
                try writeStream.objectField("info");
                try writeStream.beginObject();
                try writeStream.objectField("status");
                try writeStream.write(403);
                try writeStream.objectField("description");
                try writeStream.write("FORBIDDEN");
                try writeStream.endObject();
                try writeStream.endObject();
                res.status = 403;
                res.content_type = httpz.ContentType.JSON;
                return;
            }
            try conn.exec(
                queries.Insert.Server,
                .{ data.server_id, data.server_name, serverToken },
            );
            try conn.exec(
                queries.Insert.Player,
                .{ data.attacker_uid, data.attacker_name, data.victim_uid, data.victim_name },
            );
            try conn.exec(
                queries.Insert.Match,
                .{ data.match_id, data.server_id, data.game_mode, data.map },
            );
            try conn.exec(
                queries.Insert.Kill,
                .{ data.match_id, data.server_id, data.game_time, data.attacker_uid, data.attacker_weapon, data.attacker_titan, data.attacker_x, data.attacker_y, data.attacker_z, data.victim_uid, data.victim_weapon, data.victim_x, data.victim_y, data.victim_z, data.cause_of_death, data.distance },
            );
        } else {
            try writeStream.beginObject();
            try writeStream.objectField("info");
            try writeStream.beginObject();
            try writeStream.objectField("status");
            try writeStream.write(418);
            try writeStream.objectField("description");
            try writeStream.write("I'M A TEAPOT");
            try writeStream.endObject();
            try writeStream.endObject();
            res.status = 418;
            res.content_type = httpz.ContentType.JSON;
            return;
        }
        try writeStream.beginObject();
        try writeStream.objectField("info");
        try writeStream.beginObject();
        try writeStream.objectField("status");
        try writeStream.write(200);
        try writeStream.objectField("description");
        try writeStream.write("OK");
        try writeStream.endObject();
        try writeStream.endObject();
        res.status = 200;
        res.content_type = httpz.ContentType.JSON;
        return;
    } else {
        try writeStream.beginObject();
        try writeStream.objectField("info");
        try writeStream.beginObject();
        try writeStream.objectField("status");
        try writeStream.write(401);
        try writeStream.objectField("description");
        try writeStream.write("UNAUTHORIZED");
        try writeStream.endObject();
        try writeStream.endObject();
        res.status = 401;
        res.content_type = httpz.ContentType.JSON;
        return;
    }
}

fn getPlayerData(req: *httpz.Request, res: *httpz.Response) !void {
    var conn = connPtr.*;
    var uid: ?[]const u8 = null;
    var writeStream = std.json.writeStream(res.writer(), .{});
    var allocator = gpa.allocator();
    var queryParameters = try req.query();
    const weapon = queryParameters.get("weapon");
    const server = queryParameters.get("server");

    defer writeStream.deinit();
    if (req.param("id")) |id| {
        var row: ?zqlite.Row = null;
        defer if (row) |r| r.deinit();

        if (try conn.row(queries.Get.Player.UID, .{id})) |r| {
            row = r;
        }

        if (row) |r| {
            uid = r.text(0);
        }

        if (uid) |player| {
            var aliasRow = try conn.rows(queries.Get.Player.Aliases, .{player});
            defer aliasRow.deinit();
            try writeStream.beginObject();
            if (aliasRow.next()) |r| {
                try writeStream.objectField("name");
                try writeStream.write(r.text(0));
            }
            try writeStream.objectField("uid");
            try writeStream.write(player);
            try writeStream.objectField("aliases");
            try writeStream.beginArray();
            while (aliasRow.next()) |r| {
                try writeStream.write(r.text(0));
            }
            try writeStream.endArray();
            if (weapon != null) {
                const query = try queries.Get.Player.WeaponData(
                    allocator,
                    .{ .weapon = weapon, .server = server },
                );
                defer allocator.free(query);
                const resultsRow = try conn.row(query, .{ server, weapon, player });
                defer if (resultsRow) |r| r.deinit();
                var kills: i64 = 0;
                var distance: f64 = 0;
                if (resultsRow) |r| {
                    kills = r.int(0);
                    distance = r.float(1);
                }
                try writeStream.objectField("kills");
                try writeStream.write(kills);
                try writeStream.objectField("avg_distance");
                try writeStream.print("{d}", .{distance});
            } else {
                const killsQuery = try queries.Get.Player.Kills(
                    allocator,
                    .{ .server = server },
                );
                defer allocator.free(killsQuery);
                const deathsQuery = try queries.Get.Player.Deaths(
                    allocator,
                    .{ .server = server },
                );
                defer allocator.free(deathsQuery);
                const weaponsQuery = try queries.Get.Player.WeaponData(
                    allocator,
                    .{ .weapon = weapon, .server = server },
                );
                defer allocator.free(weaponsQuery);

                const killsRow = try conn.row(killsQuery, .{ server, player });
                defer if (killsRow) |r| r.deinit();
                const deathsRow = try conn.row(deathsQuery, .{ server, player });
                defer if (deathsRow) |r| r.deinit();

                var kills: i64 = 0;
                var deaths: i64 = 0;

                if (killsRow) |r| {
                    kills = r.int(0);
                }

                if (deathsRow) |r| {
                    deaths = r.int(0);
                }

                var weaponRows = try conn.rows(weaponsQuery, .{ server, weapon, player });
                defer weaponRows.deinit();

                try writeStream.objectField("kills");
                try writeStream.write(kills);
                try writeStream.objectField("deaths");
                try writeStream.write(deaths);
                try writeStream.objectField("kd");
                if (deaths == 0) try writeStream.write(kills) else try writeStream.print("{d}", .{@as(f64, @floatFromInt(kills)) / @as(f64, @floatFromInt(deaths))});
                try writeStream.objectField("weapon_stats");
                try writeStream.beginObject();
                while (weaponRows.next()) |r| {
                    try writeStream.objectField(r.text(0));
                    try writeStream.beginObject();
                    try writeStream.objectField("kills");
                    try writeStream.write(r.int(1));
                    try writeStream.objectField("avg_distance");
                    try writeStream.print("{d}", .{r.float(2)});
                    try writeStream.endObject();
                }
                try writeStream.endObject();
            }
            try writeStream.objectField("info");
            try writeStream.beginObject();
            try writeStream.objectField("status");
            try writeStream.write(200);
            try writeStream.objectField("description");
            try writeStream.write("OK");
            try writeStream.endObject();
            try writeStream.endObject();
            res.status = 200;
            res.content_type = httpz.ContentType.JSON;
            return;
        } else {
            try writeStream.beginObject();
            try writeStream.objectField("info");
            try writeStream.beginObject();
            try writeStream.objectField("status");
            try writeStream.write(404);
            try writeStream.objectField("description");
            try writeStream.write("NOT FOUND");
            try writeStream.endObject();
            try writeStream.endObject();
            res.status = 404;
            res.content_type = httpz.ContentType.JSON;
            return;
        }
    }
}

fn getAllPlayerData(req: *httpz.Request, res: *httpz.Response) !void {
    var conn = connPtr.*;
    var writeStream = std.json.writeStream(res.writer(), .{});
    var allocator = gpa.allocator();
    var queryParameters = try req.query();
    const weapon = queryParameters.get("weapon");
    const server = queryParameters.get("server");
    var page = std.fmt.parseInt(i64, queryParameters.get("page") orelse "1", 10) catch 1;
    var results: i64 = 0;
    var pages: i64 = 0;

    const infoQuery = try queries.Get.Players.Count(
        allocator,
        .{ .weapon = weapon, .server = server },
    );
    defer allocator.free(infoQuery);
    const resultsQuery = try queries.Get.Players.Data(
        allocator,
        .{ .weapon = weapon, .server = server },
    );
    defer allocator.free(resultsQuery);

    var infoRow: ?zqlite.Row = undefined;
    if (weapon != null) {
        infoRow = try conn.row(infoQuery, .{ server, weapon });
    } else if (server != null) {
        infoRow = try conn.row(infoQuery, .{ weapon, server });
    } else {
        infoRow = try conn.row(infoQuery, .{});
    }
    if (infoRow) |r| {
        defer r.deinit();
        results = r.int(0);
    }
    pages = switch (results) {
        0 => 0,
        else => std.math.divCeil(i64, results, 25) catch 0,
    };
    page = std.math.clamp(page, 1, pages);

    try writeStream.beginObject();
    if (results != 0) {
        var resultsRows = try conn.rows(resultsQuery, .{ server, weapon, 25 * (page - 1), 25 });
        defer resultsRows.deinit();

        try writeStream.objectField("players");
        try writeStream.beginObject();
        if (weapon != null) {
            while (resultsRows.next()) |r| {
                try writeStream.objectField(r.text(0));
                try writeStream.beginObject();
                try writeStream.objectField("name");
                try writeStream.write(r.text(1));
                try writeStream.objectField("kills");
                try writeStream.write(r.int(2));
                try writeStream.objectField("avg_distance");
                try writeStream.print("{d}", .{r.float(3)});
                try writeStream.endObject();
            }
        } else {
            while (resultsRows.next()) |r| {
                try writeStream.objectField(r.text(0));
                try writeStream.beginObject();
                try writeStream.objectField("name");
                try writeStream.write(r.text(1));
                try writeStream.objectField("kills");
                try writeStream.write(r.int(2));
                try writeStream.objectField("deaths");
                try writeStream.write(r.int(3));
                try writeStream.endObject();
            }
        }
        try writeStream.endObject();
    }
    try writeStream.objectField("info");
    try writeStream.beginObject();
    try writeStream.objectField("status");
    try writeStream.write(200);
    try writeStream.objectField("description");
    try writeStream.write("OK");
    try writeStream.objectField("currentPage");
    try writeStream.write(page);
    try writeStream.objectField("allResults");
    try writeStream.write(results);
    try writeStream.objectField("maxPages");
    try writeStream.write(pages);
    try writeStream.endObject();
    try writeStream.endObject();

    res.status = 200;
    res.content_type = httpz.ContentType.JSON;
    return;
}

fn getServerList(req: *httpz.Request, res: *httpz.Response) !void {
    var conn = connPtr.*;
    var writeStream = std.json.writeStream(res.writer(), .{});

    defer writeStream.deinit();

    var queryParameters = try req.query();
    var page = std.fmt.parseInt(i64, queryParameters.get("page") orelse "1", 10) catch 1;
    var resultsRow: ?zqlite.Row = undefined;
    var results: i64 = 0;
    var pages: i64 = 0;

    resultsRow = try conn.row(queries.Get.Servers.Count, .{});
    defer if (resultsRow) |r| r.deinit();

    if (resultsRow) |r| {
        results = r.int(0);
    }

    pages = switch (results) {
        0 => 0,
        else => std.math.divCeil(i64, results, 25) catch 0,
    };

    page = std.math.clamp(page, 1, pages);

    var serversRow = try conn.rows(queries.Get.Servers.List, .{});
    defer serversRow.deinit();

    try writeStream.beginObject();
    try writeStream.objectField("servers");
    try writeStream.beginObject();
    while (serversRow.next()) |r| {
        try writeStream.objectField(r.text(0));
        try writeStream.beginObject();
        try writeStream.objectField("server_name");
        try writeStream.write(r.text(1));
        try writeStream.objectField("owner");
        try writeStream.write(r.text(2));
        try writeStream.endObject();
    }
    try writeStream.endObject();
    try writeStream.objectField("info");
    try writeStream.beginObject();
    try writeStream.objectField("status");
    try writeStream.write(200);
    try writeStream.objectField("description");
    try writeStream.write("OK");
    try writeStream.objectField("currentPage");
    try writeStream.write(page);
    try writeStream.objectField("allResults");
    try writeStream.write(results);
    try writeStream.objectField("maxPages");
    try writeStream.write(pages);
    try writeStream.endObject();
    try writeStream.endObject();
    res.status = 200;
    res.content_type = httpz.ContentType.JSON;
    return;
}
