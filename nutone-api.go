package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"

	_ "rsc.io/sqlite"
)

type KillEvent struct {
	MatchID                string  `json:"match_id"`
	ServerName             string  `json:"server_name"`
	GameMode               string  `json:"game_mode"`
	GameTime               float64 `json:"game_time"`
	Map                    string  `json:"map"`
	AttackerName           string  `json:"attacker_name"`
	AttackerId             string  `json:"attacker_id"`
	AttackerCurrentWeapon  string  `json:"attacker_current_weapon"`
	AttackerWeapon1        string  `json:"attacker_weapon_1"`
	AttackerWeapon2        string  `json:"attacker_weapon_2"`
	AttackerWeapon3        string  `json:"attacker_weapon_3"`
	AttackerOffhandWeapon1 string  `json:"attacker_offhand_weapon_1"`
	AttackerOffhandWeapon2 string  `json:"attacker_offhand_weapon_2"`
	AttackerTitan          string  `json:"attacker_titan"`
	AttackerX              float64 `json:"attacker_x"`
	AttackerY              float64 `json:"attacker_y"`
	AttackerZ              float64 `json:"attacker_z"`
	VictimName             string  `json:"victim_name"`
	VictimId               string  `json:"victim_id"`
	VictimCurrentWeapon    string  `json:"victim_current_weapon"`
	VictimWeapon1          string  `json:"victim_weapon_1"`
	VictimWeapon2          string  `json:"victim_weapon_2"`
	VictimWeapon3          string  `json:"victim_weapon_3"`
	VictimOffhandWeapon1   string  `json:"victim_offhand_weapon_1"`
	VictimOffhandWeapon2   string  `json:"victim_offhand_weapon_2"`
	VictimTitan            string  `json:"victim_titan"`
	VictimX                float64 `json:"victim_x"`
	VictimY                float64 `json:"victim_y"`
	VictimZ                float64 `json:"victim_z"`
	CauseOfDeath           string  `json:"cause_of_death"`
	Distance               float64 `json:"distance"`
}

var db *sql.DB

const createTokenTableSQL string = `
CREATE TABLE IF NOT EXISTS tokens (
    token TEXT PRIMARY KEY,
    owner TEXT
);`

const createKillDataTableSQL string = `
CREATE TABLE IF NOT EXISTS kill_data (
    match_id                  TEXT,
    server_name               TEXT,
    game_mode                 TEXT,
    game_time                 REAL,
    map                       TEXT,
    attacker_name             TEXT,
    attacker_id               TEXT,
    attacker_current_weapon   TEXT,
    attacker_weapon_1         TEXT,
    attacker_weapon_2         TEXT,
    attacker_weapon_3         TEXT,
    attacker_offhand_weapon_1 TEXT,
    attacker_offhand_weapon_2 TEXT,
    attacker_titan            TEXT,
    attacker_x                REAL,
    attacker_y                REAL,
    attacker_z                REAL,
    victim_name               TEXT,
    victim_id                 TEXT,
    victim_current_weapon     TEXT,
    victim_weapon_1           TEXT,
    victim_weapon_2           TEXT,
    victim_weapon_3           TEXT,
    victim_offhand_weapon_1   TEXT,
    victim_offhand_weapon_2   TEXT,
    victim_titan              TEXT,
    victim_x                  REAL,
    victim_y                  REAL,
    victim_z                  REAL,
    cause_of_death            TEXT,
    distance                  REAL
);`

const insertKillEventSQL string = `
INSERT INTO kill_data (
    match_id,                 
    server_name,               
    game_mode,                
    game_time,                
    map,                      
    attacker_name,             
    attacker_id,              
    attacker_current_weapon,   
    attacker_weapon_1,        
    attacker_weapon_2,        
    attacker_weapon_3,        
    attacker_offhand_weapon_1,
    attacker_offhand_weapon_2,
    attacker_titan,            
    attacker_x,               
    attacker_y,               
    attacker_z,               
    victim_name,               
    victim_id,                
    victim_current_weapon,     
    victim_weapon_1,          
    victim_weapon_2,          
    victim_weapon_3,          
    victim_offhand_weapon_1,   
    victim_offhand_weapon_2,   
    victim_titan,             
    victim_x,                 
    victim_y,                 
    victim_z,                 
    cause_of_death,            
    distance
) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);`

func dbInit() {
	_, err := db.Exec(createTokenTableSQL)
	if err != nil {
		log.Fatal(err)
	}

	_, err = db.Exec(createKillDataTableSQL)
	if err != nil {
		log.Fatal(err)
	}
}

func dbHasToken(token string) bool {
	if db == nil {
		log.Fatal("Database unopened, exiting")
		return false
	}

	var foundToken string
	var foundOwner string

	row := db.QueryRow("SELECT token, owner FROM tokens WHERE token = ?", token)
	err := row.Scan(&foundToken, &foundOwner)
	if err == sql.ErrNoRows {
		return false
	} else if err != nil {
		log.Fatal(err)
	}

	log.Printf("Found token '%s' for '%s'\n", foundToken, foundOwner)
	return true
}

func dbInsertKillEvent(k KillEvent) error {
	statement, err := db.Prepare(insertKillEventSQL)
	if err != nil {
		return err
	}

	_, err = statement.Exec(
		k.MatchID,
		k.ServerName,
		k.GameMode,
		k.GameTime,
		k.Map,
		k.AttackerName,
		k.AttackerId,
		k.AttackerCurrentWeapon,
		k.AttackerWeapon1,
		k.AttackerWeapon2,
		k.AttackerWeapon3,
		k.AttackerOffhandWeapon1,
		k.AttackerOffhandWeapon2,
		k.AttackerTitan,
		k.AttackerX,
		k.AttackerY,
		k.AttackerZ,
		k.VictimName,
		k.VictimId,
		k.VictimCurrentWeapon,
		k.VictimWeapon1,
		k.VictimWeapon2,
		k.VictimWeapon3,
		k.VictimOffhandWeapon1,
		k.VictimOffhandWeapon2,
		k.VictimTitan,
		k.VictimX,
		k.VictimY,
		k.VictimZ,
		k.CauseOfDeath,
		k.Distance,
	)

	return err
}

func isValidRequest(r *http.Request) bool {
	isValid := false
	for name, headers := range r.Header {
		for _, v := range headers {
			if name == "Token" {
				isValid = dbHasToken(v)
			}
		}
	}

	return isValid
}

// Returns 200 if request has a valid token in 'Bearer' header
func authHandler(w http.ResponseWriter, r *http.Request) {
	isValid := isValidRequest(r)
	if isValid {
		w.WriteHeader(http.StatusOK)
	} else {
		w.WriteHeader(http.StatusUnauthorized)
		w.Header().Set("Content-Type", "application/json")
		resp := make(map[string]string)
		resp["message"] = "Invalid token"
		jsonResp, _ := json.Marshal(resp)
		w.Write(jsonResp)
	}
}

func dataHandler(w http.ResponseWriter, r *http.Request) {
	isValid := isValidRequest(r)
	if !isValid {
		w.WriteHeader(http.StatusUnauthorized)
		w.Header().Set("Content-Type", "application/json")
		resp := make(map[string]string)
		resp["message"] = "Invalid token"
		jsonResp, _ := json.Marshal(resp)
		w.Write(jsonResp)
		return
	}

	var killEvent KillEvent
	err := json.NewDecoder(r.Body).Decode(&killEvent)
	if err != nil {
		http.Error(w, "JSON error", http.StatusBadRequest)
		return
	}

	err = dbInsertKillEvent(killEvent)
	if err != nil {
		log.Print(err)
		http.Error(w, "database error", http.StatusInternalServerError)
	}
	w.WriteHeader(http.StatusOK)
}

func main() {
	var portFlag = flag.Int("p", 8080, "port to listen for HTTP requests")
	var dbFlag = flag.String("d", "nutone.db", "path to SQLite3 database")
	flag.Parse()

	log.Printf("Starting Nutone API on port %d with database '%s'...\n", *portFlag, *dbFlag)

	var err error
	db, err = sql.Open("sqlite3", *dbFlag)
	if err != nil {
		log.Fatal(err)
	}

	dbInit()

	http.HandleFunc("/auth", authHandler)
	http.HandleFunc("/data", dataHandler)

	host := fmt.Sprintf(":%d", *portFlag)
	http.ListenAndServe(host, nil)
}
