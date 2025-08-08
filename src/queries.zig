const std = @import("std");
const Filters = @import("types.zig").Filters;

pub const Create = struct {
    pub const Table = struct {
        pub const Tokens = "create table if not exists tokens (token text primary key, owner text)";
        pub const Players = "create table if not exists players (uid text, name text, timestamp timestamp default current_timestamp, primary key (uid, name))";
        pub const Servers = "create table if not exists servers (server_id text primary key, server_name text, owner text, timestamp timestamp default current_timestamp)";
        pub const Matches = "create table if not exists matches (match_id text primary key, server_id text, game_mode text, map text, timestamp timestamp default current_timestamp)";
        pub const KillData = "create table if not exists kill_data (timestamp timestamp default current_timestamp, match_id text, server_id text, game_time real, attacker_uid text, attacker_weapon text, attacker_titan text, attacker_x real, attacker_y real, attacker_z real, victim_uid text, victim_weapon text, victim_titan text, victim_x real, victim_y real, victim_z real, cause_of_death text, distance real)";
    };
    pub const Index = struct {
        pub const KillDataTimestamp = "create index if not exists kill_data_timestamp_idx on kill_data(timestamp)";
        pub const KillDataServer = "create index if not exists kill_data_server_idx on kill_data(server_id)";
        pub const KillDataAttacker = "create index if not exists kill_data_attacker_idx on kill_data(attacker_uid)";
        pub const KillDataVictim = "create index if not exists kill_data_victim_idx on kill_data(victim_uid)";
    };
};

pub const Insert = struct {
    pub const Server = "insert or replace into servers (server_id, server_name, owner) values (?1, ?2, (select owner from tokens where token = ?3 limit 1))";
    pub const Player = "insert or replace into players (uid, name) values (?1, ?2), (?3, ?4)";
    pub const Match = "insert or ignore into matches (match_id, server_id, game_mode, map) values (?1, ?2, ?3, ?4)";
    pub const Kill = "insert into kill_data (match_id, server_id, game_time, attacker_uid, attacker_weapon, attacker_titan, attacker_x, attacker_y, attacker_z, victim_uid, victim_weapon, victim_x, victim_y, victim_z, cause_of_death, distance) values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)";
};

pub const Validate = struct {
    pub const Token = "select owner from tokens where token = ?1";
    pub const ServerOwnership = "select case when exists (select * from servers where server_id = ?1 and owner = (select owner from tokens where token = ?2)) then cast(1 as bit) else cast(0 as bit) end";
    pub const ServerExistence = "select case when exists (select * from servers where server_id = ?1) then cast (0 as bit) else cast (1 as bit) end";
};

pub const Get = struct {
    pub const Player = struct {
        pub const UID = "select uid from players where uid = ?1 or name = ?1 order by timestamp desc limit 1";
        pub const Aliases = "select name from players where uid = ?1 order by timestamp desc";
        pub fn Kills(allocator: std.mem.Allocator, filters: Filters) ![:0]u8 {
            const query = try std.mem.joinZ(allocator, " ", &.{
                "select count(1) from kill_data where attacker_uid = ?1 and attacker_uid <> victim_uid",
                if (filters.server != null) "and server_id = ?2" else "",
            });
            return query;
        }
        pub fn Deaths(allocator: std.mem.Allocator, filters: Filters) ![:0]u8 {
            const query = try std.mem.joinZ(allocator, " ", &.{
                "select count(1) from kill_data where victim_uid = ?1",
                if (filters.server != null) "and server_id = ?2" else "",
            });
            return query;
        }
        pub fn WeaponData(allocator: std.mem.Allocator, filters: Filters) ![:0]u8 {
            if (filters.weapon != null) {
                const query = std.mem.joinZ(allocator, " ", &.{
                    "select count(1) as kills, avg(distance) as avg_distance from kill_data where attacker_uid = ?1 and attacker_uid <> victim_uid and attacker_weapon = ?2",
                    if (filters.server != null) "and server_id = ?3" else "",
                    "group by attacker_weapon",
                });
                return query;
            } else {
                const query = std.mem.joinZ(allocator, " ", &.{
                    "select attacker_weapon, count(1) as kills, avg(distance) as avg_distance from kill_data where attacker_uid = ?1 and attacker_uid <> victim_uid",
                    if (filters.server != null) "and server_id = ?3" else "",
                    "group by attacker_weapon",
                });
                return query;
            }
        }
    };
    pub const Players = struct {
        pub fn Data(allocator: std.mem.Allocator, filters: Filters) ![:0]u8 {
            if (filters.weapon != null) {
                const query = try std.mem.joinZ(allocator, " ", &.{
                    "select players.uid as id, players.name as name, (select count(1) from kill_data where players.uid = kill_data.attacker_uid and kill_data.victim_uid <> kill_data.attacker_uid and kill_data.attacker_weapon = ?3",
                    if (filters.server != null) "and kill_data.server_id = ?4" else "",
                    ") as kills, (select avg(kill_data.distance) from kill_data where players.uid = kill_data.attacker_uid and kill_data.attacker_uid <> kill_data.victim_uid and kill_data.attacker_weapon = ?3",
                    if (filters.server != null) "and kill_data.server_id = ?4" else "",
                    ") as avg_distance from players where name = (select players.name from players where players.uid = id order by timestamp desc limit 1)",
                    if (filters.server != null) "and id in (select attacker_uid from kill_data where kill_data.server_id = ?4)" else "",
                    "and kills <> 0 order by kills desc limit ?1 offset ?2",
                });
                return query;
            } else {
                const query = try std.mem.joinZ(allocator, " ", &.{
                    "select players.uid as id, players.name as name, (select count(1) from kill_data where players.uid = kill_data.attacker_uid and kill_data.victim_uid <> kill_data.attacker_uid",
                    if (filters.server != null) "and kill_data.server_id = ?4" else "",
                    ") as kills, (select count(1) from kill_data where players.uid = kill_data.victim_uid",
                    if (filters.server != null) "and kill_data.server_id = ?4" else "",
                    ") as deaths from players where name = (select players.name from players where players.uid = id order by timestamp desc limit 1)",
                    if (filters.server != null) "and id in (select attacker_uid from kill_data where kill_data.server_id = ?4 union select victim_uid from kill_data where kill_data.server_id = ?4)" else "",
                    "order by kills desc limit ?1 offset ?2",
                });
                return query;
            }
        }
        pub fn Count(allocator: std.mem.Allocator, filters: Filters) ![:0]u8 {
            if (filters.weapon != null) {
                const query = try std.mem.joinZ(allocator, " ", &.{
                    "select count(1) from (select distinct attacker_uid from kill_data where attacker_weapon = ?1",
                    if (filters.server != null) "and server_id = ?2" else "",
                    ")",
                });
                return query;
            } else {
                const query = try std.mem.joinZ(allocator, " ", &.{
                    "select count(1) from (select attacker_uid from kill_data",
                    if (filters.server != null) "where server_id = ?2" else "",
                    "union select victim_uid from kill_data",
                    if (filters.server != null) "where server_id = ?2" else "",
                    ")",
                });
                return query;
            }
        }
    };
    pub const Servers = struct {
        pub const Count = "select count(1) from servers";
        pub const List = "select server_id, server_name, owner from servers";
    };
};
