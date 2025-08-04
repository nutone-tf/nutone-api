const createTokensTable = "create table if not exists tokens (token text primary key, owner text)";
const createPlayersTable = "create table if not exists players (uid text, name text, timestamp timestamp default current_timestamp, primary key (uid, name))";
const createServersTable = "create table if not exists servers (server_id text primary key, server_name text, owner text, timestamp timestamp default current_timestamp)";
const createMatchesTable = "create table if not exists matches (match_id text primary key, server_id text, game_mode text, map text, timestamp timestamp default current_timestamp)";
const createKillDataTable = "create table if not exists kill_data (timestamp timestamp default current_timestamp, match_id text, server_id text, game_time real, attacker_uid text, attacker_weapon text, attacker_titan text, attacker_x real, attacker_y real, attacker_z real, victim_uid text, victim_weapon text, victim_titan text, victim_x real, victim_y real, victim_z real, cause_of_death text, distance real)";

const createKillDataTimestampIDX = "create index if not exists kill_data_timestamp_idx on kill_data(timestamp)";
const createKillDataServerIDX = "create index if not exists kill_data_server_idx on kill_data(server_id)";
const createKillDataAttackerIDX = "create index if not exists kill_data_attacker_idx on kill_data(attacker_uid)";
const createKillDataVictimIDX = "create index if not exists kill_data_victim_idx on kill_data(victim_uid)";

const insertServerData = "insert or replace into servers (server_id, server_name, owner) values (?1, ?2, (select owner from tokens where token = ?3 limit 1))";
const insertPlayerData = "insert or replace into players (uid, name) values (?1, ?2), (?3, ?4)";
const insertMatchData = "insert or ignore into matches (match_id, server_id, game_mode, map) values (?1, ?2, ?3, ?4)";
const insertKillData = "insert into kill_data (match_id, server_id, game_time, attacker_uid, attacker_weapon, attacker_titan, attacker_x, attacker_y, attacker_z, victim_uid, victim_weapon, victim_x, victim_y, victim_z, cause_of_death, distance) values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)";

const validateToken = "select owner from tokens where token = ?1";
const validateServerOwnership = "select case when exists (select * from servers where server_id = ?1 and owner = (select owner from tokens where token = ?2)) then cast(1 as bit) else cast(0 as bit) end";
const validateServerExistence = "select case when exists (select * from servers where server_id = ?1) then cast (0 as bit) else cast (1 as bit) end";

const getPlayerUID = "select uid from players where uid = ?1 or name = ?1 order by timestamp desc limit 1";
const getPlayerNameFromUID = "select name from players where uid = ?1 order by timestamp desc";
const getPlayerSpecificWeaponData = "select count(1) as kills, avg(distance) as avg_distance from kill_data where attacker_uid = ?1 and attacker_uid <> victim_uid and attacker_weapon = ?2 group by attacker_weapon";
const getPlayerKills = "select count(1) from kill_data where attacker_uid = ?1 and attacker_uid <> victim_uid";
const getPlayerDeaths = "select count(1) from kill_data where victim_uid = ?1";
const getPlayerAllWeaponData = "select attacker_weapon, count(1) as kills, avg(distance) as avg_distance from kill_data where attacker_uid = ?1 and attacker_uid <> victim_uid group by attacker_weapon";
const getAllPlayerData = "select players.uid as id, players.name as name, (select count(1) from kill_data where players.uid = kill_data.attacker_uid and kill_data.victim_uid <> kill_data.attacker_uid) as kills, (select count(1) from kill_data where players.uid = kill_data.victim_uid) as deaths from players where name = (select players.name from players where players.uid = id order by timestamp desc limit 1) order by kills desc limit ?1 offset ?2";
