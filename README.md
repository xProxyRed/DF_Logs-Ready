## DF_Logs-Ready (DE/EN)

### Deutsch (DE)

#### Worum geht’s?
Dieses Repo enthält **bereits umgeschriebene/angepasste FiveM-Resources**, die **out-of-the-box** mit meinem Logging-System **`DF_Logs`** funktionieren.

Die enthaltenen Resources sind so angepasst, dass sie **nicht crashen**, wenn `DF_Logs` nicht läuft – in dem Fall werden einfach **keine Logs** gesendet.

Außerdem enthalten:
- **`logs_integration.lua`** (im Repo-Root): Ein **Standalone Helper**, den du in andere Resources kopieren kannst, um schnell `DF_Logs`-Logs zu senden.

#### Voraussetzungen
- **`DF_Logs`** muss serverseitig gestartet sein (Export: `exports["DF_Logs"]:log(payload)`).
- Für RP-Namen-Erkennung (optional): **ESX** (`es_extended`) oder **QBCore** (`qb-core`) oder **Qbox** (`qbx_core`).  
  Falls keines davon läuft, wird auf `GetPlayerName(source)` zurückgefallen.

Zusätzliche Abhängigkeiten gelten je nach Resource – Details stehen jeweils **im Resource-Ordner** (z. B. eigene `README.md`, `fxmanifest.lua`).

#### Installation (kurz)
- Resource(s) in deinen `resources/` Ordner legen.
- In `server.cfg` sicherstellen, dass `DF_Logs` **vor** den Resources startet, die logs senden sollen:
  - `ensure DF_Logs`
  - `ensure <deine_resource>`

#### Eigene Scripts mit `logs_integration.lua` anbinden
Die Datei `logs_integration.lua` ist so gebaut, dass sie **Client + Server** kann:
- **Server**: baut Payload (Playername, Resource, Coords) und ruft `DF_Logs` Export auf
- **Client**: bietet dieselbe API und bridged per Event in die **eigene** Resource (pro Resource eigener Eventname, keine Doppel-Logs)

##### Schritt 1: Datei kopieren
Kopiere `logs_integration.lua` in deine Resource, z. B.:
- `resources/mein_script/logs_integration.lua`

##### Schritt 2: In `fxmanifest.lua` eintragen
Wenn du **nur serverseitig** loggen willst:

```lua
server_scripts {
  'logs_integration.lua',
  'server/*.lua'
}
```

Wenn du auch **vom Client** aus `DFLogs.Log(...)` nutzen willst (empfohlen), lade sie als shared:

```lua
shared_scripts {
  'logs_integration.lua'
}

server_scripts {
  'server/*.lua'
}

client_scripts {
  'client/*.lua'
}
```

##### Schritt 3: Logs senden (API)
Es gibt zwei Aufruf-Varianten:

```lua
-- Variante A (typisch in Server-Events, source ist verfügbar)
DFLogs.Log("my_action", "my message")

-- Variante B (source explizit)
DFLogs.Log(source, "my_action", "my message")
```

Optional kannst du `opts` mitgeben:

```lua
DFLogs.Log(source, "inventory_remove", "Item entfernt", {
  extra = { item = "bread", amount = 2 }, -- wird als Text an message angehängt
  resource = "mein_script",              -- überschreibt Resource-Name
  coords = vector3(0.0, 0.0, 0.0),        -- überschreibt Coords
  player = "Max Mustermann",              -- überschreibt Player-Name
})
```

##### Wichtige Optionen (`opts`)
- **`extra` (table)**: Beliebige Zusatzinfos; werden lesbar an `message` angehängt (`key=value | key=value`).
- **`resource` (string)**: Überschreibt den Resource-Namen im Payload.
- **`coords` (vector3)**: Überschreibt die Coords im Payload.
- **`player` (string)**: Überschreibt den Player-Namen im Payload.
- **`source` (number)**: Falls du nicht im Event-Context bist, kannst du `source` hier setzen.
- **`allowNoSource` (boolean)**: Standardmäßig wird ohne Player-Source **nicht** geloggt.  
  Setze `allowNoSource = true`, wenn du bewusst “System”-Logs senden willst (z. B. aus Exports/Server-Threads).

Beispiel für System-Log (ohne Player):

```lua
DFLogs.Log("startup", "Resource gestartet", { allowNoSource = true })
```

#### Troubleshooting
- **Keine Logs sichtbar**:
  - Läuft `DF_Logs` wirklich? (`ensure DF_Logs`)
  - Existiert der Export `exports["DF_Logs"]:log(...)`?
  - Ist `logs_integration.lua` in der Resource wirklich geladen (server/shared)?
- **Client ruft `DFLogs.Log(...)`, aber nichts passiert**:
  - Stelle sicher, dass `logs_integration.lua` **auch serverseitig** in derselben Resource geladen wird (am besten `shared_scripts`).

---

### English (EN)

#### What is this?
This repo contains **already rewritten/adapted FiveM resources** that work **out of the box** with my logging system **`DF_Logs`**.

The included resources are adapted to **not crash** if `DF_Logs` is not running—in that case, **no logs** will be sent.

Also included:
- **`logs_integration.lua`** (repo root): A **standalone helper** you can copy into other resources to quickly send `DF_Logs` logs.

#### Requirements
- **`DF_Logs`** must be started on the server side (export: `exports["DF_Logs"]:log(payload)`).
- Optional RP name detection: **ESX** (`es_extended`) or **QBCore** (`qb-core`) or **Qbox** (`qbx_core`).  
  If none is running, it falls back to `GetPlayerName(source)`.

Per-resource dependencies may apply—check each **resource folder** (e.g. its `README.md`, `fxmanifest.lua`).

#### Install (quick)
- Drop the resource(s) into your `resources/` folder.
- In `server.cfg`, ensure `DF_Logs` starts **before** resources that send logs:
  - `ensure DF_Logs`
  - `ensure <your_resource>`

#### Use `logs_integration.lua` in your own scripts
`logs_integration.lua` supports **both client + server**:
- **Server**: builds the payload (player name, resource name, coords) and calls the `DF_Logs` export
- **Client**: provides the same API and bridges via a **resource-scoped** event (prevents duplicate/global logging)

##### Step 1: Copy the file
Copy `logs_integration.lua` into your resource, e.g.:
- `resources/my_script/logs_integration.lua`

##### Step 2: Add it to `fxmanifest.lua`
If you only log from the server:

```lua
server_scripts {
  'logs_integration.lua',
  'server/*.lua'
}
```

If you also want to call `DFLogs.Log(...)` from the client (recommended), load it as shared:

```lua
shared_scripts {
  'logs_integration.lua'
}

server_scripts {
  'server/*.lua'
}

client_scripts {
  'client/*.lua'
}
```

##### Step 3: Send logs (API)
Two call styles:

```lua
-- Style A (typical inside server events, source is available)
DFLogs.Log("my_action", "my message")

-- Style B (pass source explicitly)
DFLogs.Log(source, "my_action", "my message")
```

With optional `opts`:

```lua
DFLogs.Log(source, "inventory_remove", "Item removed", {
  extra = { item = "bread", amount = 2 }, -- appended to message as readable key=value pairs
  resource = "my_script",
  coords = vector3(0.0, 0.0, 0.0),
  player = "John Doe",
})
```

##### Important options (`opts`)
- **`extra` (table)**: Extra fields appended to `message` as `key=value | key=value`.
- **`resource` (string)**: Override resource name in payload.
- **`coords` (vector3)**: Override coords in payload.
- **`player` (string)**: Override player name in payload.
- **`source` (number)**: If you’re not in an event context, set the source here.
- **`allowNoSource` (boolean)**: By default, logging without a player source is **blocked**.  
  Set `allowNoSource = true` for intentional system logs (exports/server threads).

System log example (no player):

```lua
DFLogs.Log("startup", "Resource started", { allowNoSource = true })
```

#### Troubleshooting
- **No logs**:
  - Is `DF_Logs` started? (`ensure DF_Logs`)
  - Does the export `exports["DF_Logs"]:log(...)` exist?
  - Is `logs_integration.lua` actually loaded (server/shared)?
- **Client calls `DFLogs.Log(...)` but nothing happens**:
  - Make sure `logs_integration.lua` is also loaded server-side in the same resource (best via `shared_scripts`).


