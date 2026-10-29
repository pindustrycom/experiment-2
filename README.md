# Boarding School Tycoon (Roblox)

A Habbo-style boarding school tycoon. You start with 2 dorm rooms and 2 students. Students have rarities (Common to Mythic), personalities, and chemistry with their roommates. Happy rooms earn more money, and money buys new rooms, new floors, upgrades and facilities until your school is a skyscraper.

Everything is built in code, so there are no models or assets to import.

## Quick start (no tools needed)

1. Open **`BoardingSchoolTycoon.rbxl`** in Roblox Studio (double-click it, or File > Open).
2. Press **Play** (F5). You spawn at your school. The tutorial pops up at the bottom of the screen.
3. To test likes, visiting and friend boosts, go to **Test > Clients and Servers**, pick 2 players, and press **Start**.

Progress doesn't save in Studio until you complete the publishing steps below. Until then the game warns in the output and runs without saving.

## Publish it

1. In Studio, go to **File > Publish to Roblox** and create a new experience.
2. Go to **Home > Game Settings > Security** and turn on **Enable Studio Access to API Services**. Saving and the global leaderboards need it.
3. Go to **Game Settings > Permissions** and set the game to **Public**.
4. Optional, for Robux: in the Creator Dashboard, create game passes and developer products, then paste their IDs into `ReplicatedStorage > Shared > Config`, under `Config.GamePasses` and `Config.Products`. Any ID left at `0` is hidden in-game. The Shop button only shows up once at least one ID is set.
   - Game passes: `DoubleCash` (2x income), `Lucky` (+50% Legendary/Mythic odds), `VIP` (+10% income)
   - Developer products: `RoyalPull`, `RoyalPull10`, `CashSmall`, `DoubleOffline`
5. Publish again (Alt+P) after every change.

## Editing with Rojo (optional, for coders)

The `src/` folder plus `default.project.json` is a standard Rojo 7 project.

```
rojo serve            # then click Connect in the Rojo Studio plugin
rojo build -o BoardingSchoolTycoon.rbxl
```

| Path | Ends up in | What it does |
|---|---|---|
| `src/shared/Config.lua` | ReplicatedStorage.Shared | **All tuning**: students, odds, prices, facilities, monetization IDs |
| `src/shared/SchoolMath.lua` | ReplicatedStorage.Shared | Satisfaction and income formulas, shared so the UI previews match the server |
| `src/server/Main.server.lua` | ServerScriptService.Server | Remotes, actions, gacha, income tick, likes, idle earnings, Robux, leaderboards |
| `src/server/DataService.lua` | ServerScriptService.Server | DataStore load/save, autosave, shutdown flush |
| `src/server/PlotService.lua` | ServerScriptService.Server | Builds the plaza, 6 plots, and renders each school (rooms, beds, students, facilities, elevator) |
| `src/client/Main.client.lua` | StarterPlayerScripts.Client | All UI: HUD, Enroll, Rooms, Students, Build, Visit, Daily, Shop, gacha reveal |
| `src/client/Animator.client.lua` | StarterPlayerScripts.Client | Students wander their rooms and pop mood bubbles |

## How the game works

- **Rooms**: Room 1 and 2 are free. Each new room costs more, and every 4 rooms adds a new floor (up to 10 floors and 40 rooms). Rooms upgrade from Basic Dorm (2 beds) to Comfy (3), Luxury Suite (4) and Penthouse, and each tier adds decor mood.
- **Students**: 32 students across 6 rarities and 8 personalities (Nerd, Jock, Artist, Rebel, Prankster, Musician, Gamer, Royal). Rare and better students have traits like *Gold* (room income multiplier), *Mood* (cheers up roommates), *Peace* (no fights), *Loner* and *Social*. 1 in 40 pulls is **Shiny** (2x income, sparkles).
- **Chemistry**: every roommate pair is between -2 (enemies 💢) and +2 (besties 💞), and each step is worth 12 satisfaction. Nerd + Gamer and Artist + Musician are besties. Royal + Rebel and Royal + Prankster are enemies. Satisfaction (0 to 100%) scales income from 0.25x up to 2.25x.
- **Only housed students earn money.** That's what pushes players to keep expanding.
- **Admissions (gacha)**: Open, Honors and Royal banners, each with better odds than the last, plus x10 pulls at 10% off. A Legendary is guaranteed within 75 pulls. Admissions get pricier as your roster grows, and expelling students refunds some cash.
- **Facilities**: Cafeteria, Library, Gym, Arcade, Art Studio, Music Hall, Pool, Ballroom and Observatory. They boost mood for everyone or for certain personalities, and some add an income multiplier.
- **Auto-Arrange** solves room assignments for max income in one tap.

## Viral and retention hooks built in

- Server-wide announcements and chat messages when anyone pulls a Legendary, a Mythic or a shiny Epic+. There's also a screen flash and a "LEGENDARY!" banner on your own pull.
- **Idle earnings**: students earn 50% while you're offline (up to 8 hours), shown in a "Welcome back" popup with a Robux "2x it" button.
- **Daily free Honors admission** with a live countdown on the button.
- **Likes**: walk up to anyone's school sign (or use the Visit menu) and ❤ it. Each like pays the owner a minute of their income and pays the liker $50, so liking spreads.
- **Friend boost**: +10% income for each friend in the server (up to +50%), plus an Invite button that uses Roblox's invite prompt.
- **Global leaderboards** in the plaza (Richest Schools, Most Liked) and leaderstats (Cash, Income, Likes).
- **Collection book** (32 students, shown as ??? until discovered) to drive "gotta catch 'em all".
- A visible skyscraper that grows floor by floor, so other players can see who's winning.

## Tuning tips

All numbers live in `Config.lua`. A rough simulation of an active player with the current values: floor 2 at about 2 minutes, floor 4 at about 30 minutes, floor 9 after roughly a day of play (idle earnings included). To speed everything up, raise rarity `income` values or lower `RoomUnlockCost`.

## Ideas for next updates

These keep players coming back if you announce them as "UPDATE 1, 2, 3...":
- Limited-time event banners (Halloween students, Exchange Week)
- Trading between players
- Room furniture and decorating (closer to Habbo)
- Exams or a "School Inspection" mini-event that rewards high satisfaction
- Rebirth/prestige: reset your school for a permanent multiplier
