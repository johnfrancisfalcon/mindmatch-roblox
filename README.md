# mindmatch-roblox
MindMatch Roblox: a social multiplayer guessing game with configurable token packs, power-ups, and themeable UI.

## Local Development
Run Rojo server:

```bash
rojo serve
```

In Roblox Studio, install the Rojo plugin, then connect to the running server (default `localhost:34872`) and sync the project.

Script locations:
- Server scripts: `src/server` -> `ServerScriptService/Server`
- Shared modules: `src/shared` -> `ReplicatedStorage/Shared`
- Client scripts: `src/client` -> `StarterPlayerScripts/Client`
