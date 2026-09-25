# Yandere Virus — LAN Co-op Guide

Play Yandere Virus co-op over a virtual LAN (Radmin VPN, Hamachi, ZeroTier,
Tailscale, …) with no Steam account, no Steam servers and no internet.

This was built and verified against **Yandere Virus v1.0.4 (Steam, Windows)**,
Unity **6000.3.13f1**, and the Goldberg emulator that ships with the release.

---

## Quick start

**Host machine**

```powershell
cd "<game folder>\LAN-Setup"
.\Setup-LAN.ps1 -Player 1 -AutoRadmin -Firewall
```

**Second machine** (after copying the game folder over)

```powershell
cd "<game folder>\LAN-Setup"
.\Setup-LAN.ps1 -Player 2 -AutoRadmin -Firewall
```

> **Playing with friends over the internet?** Everyone must first join the same
> virtual network — **Radmin VPN** (or Hamachi / ZeroTier / Tailscale). Radmin
> is the one this was built and tested around. Only then run the commands
> above.
>
> **Both PCs on the same physical LAN** (one router, no VPN — e.g. two machines
> in the same house)? Use `-AutoLAN` instead of `-AutoRadmin`. It targets the
> adapter carrying the default route. `-AutoRadmin` also falls back to that
> automatically when no Radmin adapter is present, so picking the wrong one is
> not fatal — check the `detected:` line the script prints.

Then:

1. Both machines connect to the same Radmin network and can `ping` each other.
2. Host launches the game → **Host Game**.
3. Second machine launches the game → open the **Steam overlay** (`Shift`+`Tab`)
   → click **Join Game** on the host.

That last step is the important one. See
[How joining actually works](#how-joining-actually-works).

---

## Requirements

| | |
|---|---|
| Game | Yandere Virus v1.0.4, the release that ships Goldberg |
| OS | Windows 10 / 11, 64-bit |
| VPN | **Radmin VPN** for playing with friends over the internet — or any equivalent (Hamachi, ZeroTier, Tailscale) that puts both PCs on one subnet. Not needed if both PCs are on the same physical router. |
| PowerShell | 5.1 (built into Windows) — no install needed |
| Both machines | **Same game version.** A version mismatch makes the handshake fail. |

You do **not** need Steam installed, and you do **not** need to own the game.

---

## What is actually going on

### The emulator

The release ships **Goldberg (`gbe_fork`)** where Valve's Steam client DLL would
be:

```
Yandere Virus_Data\Plugins\x86_64\steam_api64.dll        ~11 MB   <- Goldberg
Yandere Virus_Data\Plugins\x86_64\steam_api64.dll.bak   ~300 KB   <- original Valve DLL, kept as backup
```

Goldberg's whole purpose is running Steam multiplayer APIs on a LAN with no
Steam client and no internet. Its behaviour is driven by
`steam_settings\configs.main.ini`:

| Key | Value | What it does |
|---|---|---|
| `disable_networking` | `0` | Steam networking enabled |
| `disable_lan_only` | `0` (default) | Emulator hooks the OS network APIs and keeps traffic on the LAN |
| `listen_port` | `47584` | Discovery channel. **Every machine must use the same value.** |
| `disable_lobby_creation` | `0` (default) | Lobby creation allowed |

### The game's networking stack

The game uses **FishNet** with the **FishySteamworks** transport, so gameplay
traffic runs over `SteamNetworkingSockets` — which is exactly what Goldberg
implements.

```
Game code  ->  FishNet NetworkManager
           ->  FishySteamworks transport
           ->  SteamNetworkingSockets
           ->  steam_api64.dll  (Goldberg)
           ->  UDP on the LAN
```

Because Goldberg is doing the work, the game is *already* LAN-capable. Nothing
has to be patched, injected or hooked. This guide only fixes configuration.

### The one thing that breaks by default

`steam_settings\configs.user.ini` lives **inside the game folder** and ships
with a hardcoded identity:

```ini
account_name=MRGoldberg
account_steamid=76561197960287930
```

Copy the game folder to a second PC and **both machines present the same
SteamID**. The emulator then treats them as one user and networking fails in
confusing ways. `Setup-LAN.ps1 -Player 2` gives the second machine a different
ID. That single fix is most of the work.

---

## How joining actually works

Verified from the game's own logs.

**Quick Join does not work on a LAN.** It searches for a random public lobby and
finds nothing:

```
[RandomLobby] RequestRandomLobby() called
[RandomLobby] RequestRandomLobby: <lobby search request> (gameVersion=1.0.4)
[RandomLobby] RequestRandomLobby: <search result arrived> (count=0, ioError=False)
                                        ^^^^^^^ no lobbies, on every attempt
```

**Steam Rich Presence "Join Game" does work.** The client joins through a Steam
rich-presence join request, which carries the host's SteamID directly:

```
NstarNetworkBridge:<Start>b__54_0(GameRichPresenceJoinRequested_t)
```

So on the second machine: open the Steam overlay, find the host, **Join Game**.

The full successful exchange, from real logs:

*Host side*
```
NstarNetworkBridge:Prepare_ServerLobby()
GameTitleController:StartMultiGamePlayStepA()
My Steam Host ID: 76561197960287930
[Dissonance:Network] FishNet: Running as: Host!
NetworkGlobalManager:SpawnNewPlayer(NetworkConnection)
SceneManager:OnClientLoadedScenes(ClientScenesLoadedBroadcast, Channel)
```

*Client side*
```
[Dissonance:Network] FishNet: Running as: Client!
FishySteamworks.Client.ClientSocket:OnLocalConnectionState(SteamNetConnectionStatusChangedCallback_t)
[Dissonance:Network] ConnectionNegotiator: Received handshake response from server,
                                           joined session '1550993603'
```

Note the client joined with a **different** `listen_port` than the host
(`47585` vs `47584`) — the rich-presence path passes the SteamID directly, so
the two machines do not strictly need matching ports. `Setup-LAN.ps1` puts both
on `47584` anyway, because the emulator's peer *discovery* does use
`listen_port` to resolve a SteamID to an IP address across the network.

---

## Step by step

### 1. Prepare both machines

1. Install **Radmin VPN** on both, join the **same network**.

   > **Testing with two PCs in the same house?** Use Radmin anyway, even though
   > they already share a router. Radmin builds its `26.x.x.x` virtual network on
   > top of whatever physical link exists, so this works — and it exercises the
   > exact path a remote friend will use, which `-AutoLAN` does not.
   >
   > If Radmin fails but `-AutoLAN` works, the fault is in the Radmin layer
   > (routing or broadcast), not in the game or the emulator. That comparison
   > isolates the problem far faster than guessing.

2. Confirm they can reach each other — note the `26.x.x.x` address of each:
   ```powershell
   ipconfig | findstr /i "IPv4"
   ping 26.x.x.x
   ```
3. Confirm both run the **same game version** (bottom-left of the title screen).

### 2. Copy the game to the second machine

Copy the whole game folder. It is about **11 GB**. A network share, an external
drive or a USB stick all work.

### 3. Configure each machine

Run on **each** machine, in an ordinary PowerShell window:

```powershell
cd "<game folder>\LAN-Setup"
.\Setup-LAN.ps1 -Player 1 -AutoRadmin -Firewall     # host
.\Setup-LAN.ps1 -Player 2 -AutoRadmin -Firewall     # second machine
```

Swap `-AutoRadmin` for `-AutoLAN` only if both PCs are on the same physical
router with no VPN.

`-Player` accepts any number from **1 to 16** — it is not limited to two
machines. The number does **not** imply a role; whoever clicks **Host Game** is
the host, and anyone else joins. The only rule is that **every machine uses a
different number**, because that is what gives each one its own SteamID:

| `-Player` | account_name | account_steamid |
|---|---|---|
| 1 | MRGoldberg | 76561197960287930 |
| 2 | Player2 | 76561197960287931 |
| 3 | Player3 | 76561197960287932 |
| 4 | Player4 | 76561197960287933 |
| … | … | … |

Two machines sharing a number is the single most common reason a join fails.
The script prints the identity it wrote — check it before launching the game.

#### Changing the name shown in game

```powershell
.\Setup-LAN.ps1 -Player 1 -PlayerName "Kaito" -AutoRadmin -Firewall
```

The game has **no rename option of its own** — the only text input field in the
whole build is the hidden developer server-IP box. It reads the name from the
Steam persona via `ISteamFriends_GetPersonaName` and syncs it to other players
with `ServerRpcSetPlayerName`. The emulator supplies that persona from
`account_name`, which is exactly what `-PlayerName` writes.

Names are written as **UTF-8** and are trimmed to Steam's 32-byte limit
(`Nguyễn Văn A` = 15 bytes, `雪 Yuki` = 8 bytes).

> **Caveat:** the game ships a Latin-only font
> (`YandereFont_English_Latin_Roboto-Condensed`). The log warns about missing
> glyphs for CJK characters, so a name written in Chinese/Japanese/Korean may
> render as empty boxes in game even though the config file is correct. Latin
> and Latin-Extended characters (including Vietnamese diacritics) are the safe
> choice.

To set the name without re-running the whole script, edit
`steam_settings\configs.user.ini` directly:

```ini
[user::general]
account_name=Kaito
account_steamid=76561197960287930
```

What it does:

1. Writes `configs.user.ini` with an identity unique to `-Player`
   (backup kept as `configs.user.ini.orig`).
2. Writes `configs.main.ini` with `disable_networking=0` and
   `listen_port=47584`.
3. With `-AutoRadmin` (or `-AutoLAN`), finds the right adapter, computes its
   broadcast address and writes `custom_broadcasts.txt` so peer discovery
   survives networks that do not forward `255.255.255.255` — Radmin VPN being
   one of them.
4. With `-Firewall`, adds an inbound UDP rule for `47584`
   (run as Administrator, or accept the UAC prompt).

If auto-detection picks the wrong adapter, pass the subnet explicitly:
`-RadminCIDR 192.168.1.0/24` (replace with your own subnet — check with
`ipconfig`). Omit the switch entirely if you are on a plain home LAN; the
default broadcast almost always works there.

### 4. Play

1. **Host**: launch the game → **Host Game**.
2. **Second machine**: launch the game → `Shift`+`Tab` → **Join Game** on the
   host.
3. If the overlay lists nothing, use the host's in-game **Invite Friend**.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| **Join Game** not listed in the overlay | Emulator has not discovered the host yet | Both machines must be on the same Radmin subnet and able to ping each other. Restart both games after connecting the VPN. |
| Quick Join finds nothing (`count=0`) | Expected — Quick Join searches public lobbies, which do not exist on a LAN | Use the overlay's **Join Game** instead. |
| Handshake fails / instantly disconnects | Both machines on the **same SteamID** | Re-run `Setup-LAN.ps1` with a different `-Player` on one machine and check the printed `account_steamid`. |
| `EMU_MISSING_INTERFACE.txt` appears in the game folder | The game asked for a Steam interface Goldberg did not provide | Check `steam_settings\steam_interfaces.txt`. The DLL does export `SteamAPI_SteamNetworkingSockets_v008`/`v012` and `SteamNetworkingMessages002`, so the interface exists — usually this file is just a report. |
| Connection times out | Firewall | Run with `-Firewall`, or allow `Yandere Virus.exe` through Windows Defender Firewall. Check with `netstat -an \| findstr 47584`. |
| Machines cannot ping each other | Different VPN subnets | Radmin sometimes puts members on different subnets. Every member must be in the same Radmin network. |
| Game crashes at the title screen | Not related to LAN | See the crash reports in `%TEMP%\nStarcube\Yandere Virus\Crashes`. |

Logs to read when diagnosing:

| File | Contents |
|---|---|
| `%USERPROFILE%\AppData\LocalLow\nStarcube\Yandere Virus\Player.log` | Current session |
| `…\Player-prev.log` | Previous session |
| `%APPDATA%\GSE Saves\<appid>\` | Emulator save data, achievements |

Useful lines to grep for:

```
FishNet: Running as: Host!        /  Running as: Client!
Received handshake response from server, joined session
[RandomLobby] RequestRandomLobby
NetworkGlobalManager:SpawnNewPlayer
```

---

## Optional — testing on a single PC

Useful to confirm the emulator stack works before involving anyone else.

### Step 1 — make room in memory

Two instances need roughly **21 GB of commit charge**:

```
instance 1 commit : 12.50 GB
instance 2 commit :  8.38 GB
```

On a 16 GB machine the second instance dies with
`Could not allocate memory: System out of memory!` — because Windows had shrunk
the pagefile on a nearly-full system drive, collapsing the commit limit to
19 GB. Move the pagefile to a roomier drive:

```powershell
.\Set-Pagefile.ps1        # self-elevates via UAC
```

Then **reboot**. Expect the commit limit to roughly double.

### Step 2 — run both instances

```powershell
.\Test-Two-Instances.ps1
```

This starts instance 1 as `HostPlayer`, rewrites the config, then starts
instance 2 as `ClientPlayer` on a different UDP port. Both are left running.
Logs go to `instance1.log` and `instance2.log`.

You are looking for `clean` for both, and this in the logs:

```
instance1.log:  FishNet: Running as: Host!
instance2.log:  FishNet: Running as: Client!
instance2.log:  Received handshake response from server, joined session '…'
```

To force smaller windows: `.\Test-Two-Instances.ps1 -Width 640 -Height 360`

Finish with `.\Restore-Config.ps1`.

You do **not** need the pagefile step to play over LAN with two real machines —
each machine only runs one instance there.

---

## Files in this folder

| File | Purpose |
|---|---|
| `Setup-LAN.ps1` | Configure one machine for LAN co-op. Run this on both. |
| `Restore-Config.ps1` | Put the shipped emulator config back. |
| `Test-Two-Instances.ps1` | Optional — run two instances on one PC. |
| `Set-Pagefile.ps1` | Optional — enlarge the pagefile for the two-instance test. |
| `README.md` | This file. |

---

## Undoing everything

| Change | How to revert |
|---|---|
| Emulator config | `.\Restore-Config.ps1` |
| Firewall rule | `Remove-NetFirewallRule -DisplayName "Yandere Virus LAN UDP 47584"` |
| Pagefile | `sysdm.cpl` → Advanced → Performance **Settings** → Advanced → Virtual memory **Change** |
| Graphics settings lowered for testing | `reg import PlayerPrefs-backup.reg`, or set them again in the in-game Settings menu |

The scripts never touch `GameAssembly.dll`, `global-metadata.dat`, or any game
asset. Nothing is patched — only config files next to `steam_api64.dll` are
written, and every one of them is backed up as `*.orig` first.
