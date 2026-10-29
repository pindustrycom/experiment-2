# Boarding School Tycoon (Roblox)

A low-key Sims meets Habbo boarding house tycoon. You live in the house with your students: you walk the hallways while they wander between their dorms, the common room and the facilities you build. You have your own big room (bed, desk, wardrobe, plus furniture you buy) with three boards on the wall: **Floor plans** (a full-screen designer for hallways, rooms, stairs, supports and new floors), **Students** (who sleeps where) and **Happiness** (how everyone feels and why). Build mode lets you pick materials for walls, floors and the roof, Sims-style.

Students have rarities (Common to Mythic), personalities, and chemistry with their roommates. Happy rooms earn more money, and money pays for new rooms, facilities and floors until the house is 6 floors tall.

Everything is built in code, so there are no models or assets to import.

## Quick start (no tools needed)

1. Open **`BoardingSchoolTycoon.rbxl`** in Roblox Studio (double-click it, or File > Open).
2. Press **Play** (F5). You spawn in your own room, in front of the three boards. The tutorial pops up at the bottom of the screen.
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

**Lighting:** the game looks best with **Lighting > Technology = Future**. Scripts can't set that property, so if you work with `rojo serve`, set it once by hand in Studio (select Lighting in the Explorer, change Technology in Properties, save the place). `rojo build` sets it for you.

**Students** use real Roblox R15 avatar bodies (with hair and personality accessories built in code) and Roblox's default walk/idle animations. That needs Roblox's avatar service, which works in Studio when you're online; if it's unavailable the game falls back to block students.

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
| `src/shared/House.lua` | ReplicatedStorage.Shared | Floor plans on a 16 x 20 tile lot: hallways, rectangular rooms, doors, stairs, supports, the validity check and hallway pathfinding (shared so the designer, the server and the students agree), build-mode areas and materials |
| `src/server/PlotService.lua` | ServerScriptService.Server | Builds the plaza and 6 plots, and renders each house from its floor plan: walls with doors and windows, stairs, flat and gable roofs, columns under overhangs, room props, your room and its three boards, students |
| `src/client/Main.client.lua` | StarterPlayerScripts.Client | All UI: HUD, Enroll, Rooms, Students, Floor plans, Happiness, Build mode, Visit, Daily, Shop, gacha reveal |
| `src/client/Animator.client.lua` | StarterPlayerScripts.Client | Students wander their rooms, walk the hallways (tile pathfinding) to the common room, facilities and living room items on their floor, and pop mood bubbles |
| `src/client/Cutaway.client.lua` | StarterPlayerScripts.Client | Sims-style cutaway: floors above you and the roof fade out while you're inside a house |

## How the game works

- **The house**: every floor is a grid of 6-stud tiles (16 x 20). The **Floor plans** board opens a full-screen designer: paint hallway tiles, draw rooms of any size (3 x 3 and up, bigger dorms get more beds and decor), move, turn and resize rooms, pick where each door goes, and place the stairs. Every floor has to stand on the one below, unless you buy **supports** for that floor: then the next floor may hang out up to 3 tiles, held up by columns. The designer checks the plan as you go (the front door has to reach the hallway, every door needs a hallway you can walk to, stairs need hallway at both ends) and shows what's wrong. You start with your room, the common room and two dorms on one floor; buy more floors up to 6. Press **E** at a dorm door (or click its door plate) to manage who lives there.
- **Your room**: you spawn here. It's 3 x 6 tiles, with a bed, desk and wardrobe. The three boards on its back wall show the live floor plans, who sleeps where, and every room's happiness (unhappiest first). Walk up to one and press **E** (or click it) to open it. **Happiness** breaks each student's mood into base, decor, facilities, roommates, mood buffs and traits, and points out roommates who don't get along. The **🏠 My Room** button takes you back here from anywhere.
- **Build mode** (🎨 Build): pick any area (outside, hallways, your room, the common room, each dorm, each facility) and choose wall, floor and roof materials, from free paint to Gold Leaf. Every coat costs the material's price. In dorm rooms, fancier walls and floors add 🎀 decor, which raises the students' satisfaction. Furniture for your room (rug, desk, aquarium, trophy cabinet...) is bought here too, and each piece gives the whole house a small income boost. You can hide and re-place furniture for free.
- **Rooms**: Room 1 and 2 are free. Each new room costs more (up to 40 rooms). Rooms upgrade from Basic Dorm (2 beds) to Comfy (3), Luxury Suite (4) and Penthouse, and each tier adds decor mood. New rooms, upgrades and resizing are on the Floor plans board.
- **Students**: boys and girls across 6 rarities, each with several **tags** (Alpha, Chad, Nerd, Gamer, Artistic, Funny, Bully, Chud, Sleepy, Carefree...). Rare and better students have traits like *Gold* (room income multiplier), *Mood* (cheers up roommates) and *Chill*. The Legendary **La Rose** crew (Khan D, JP, Ed, Greg, Miguel) vibe with each other and boost income when they all live in your house. 1 in 40 pulls is **Shiny** (2x income, sparkles).
- **Vibes and friendships**: the vibe between two students is the geometric mean of their tag-pair percentages. Roommates who vibe become friends, best friends and siblings over time (and rooms are always all boys or all girls; the house rule on the Floor plans board picks who applies). **Outings** (movies, park, party...) raise bonds and leave photos on the dorm walls. The **living room** items (guitars, TV, console, VR, canvas) cheer up students with matching tags. Satisfaction (0 to 100%) scales income from 0.25x up to 2.25x.
- **Only housed students earn money.** That's what pushes players to keep expanding.
- **Admissions (gacha)**: Open, Honors and Royal banners, each with better odds than the last, plus x10 pulls at 10% off. A Legendary is guaranteed within 75 pulls. Admissions get pricier as your roster grows, and expelling students refunds some cash.
- **Facilities**: Cafeteria, Library, Gym, Arcade, Art Studio, Music Hall, Pool, Ballroom and Observatory are rooms inside the house, placed wherever you want from the Floor plans board, with their own props. Students drop by to hang out. They boost mood for everyone or for certain personalities, and some add an income multiplier.
- **Auto-Arrange** solves room assignments for max income in one tap.

## Viral and retention hooks built in

- Server-wide announcements and chat messages when anyone pulls a Legendary, a Mythic or a shiny Epic+. There's also a screen flash and a "LEGENDARY!" banner on your own pull.
- **Idle earnings**: students earn 50% while you're offline (up to 8 hours), shown in a "Welcome back" popup with a Robux "2x it" button.
- **Daily free Honors admission** with a live countdown on the button.
- **Likes**: walk up to anyone's house sign (or use the Visit menu) and ❤ it. Each like pays the owner a minute of their income and pays the liker $50, so liking spreads.
- **Friend boost**: +10% income for each friend in the server (up to +50%), plus an Invite button that uses Roblox's invite prompt.
- **Global leaderboards** in the plaza (Richest Schools, Most Liked) and leaderstats (Cash, Income, Likes).
- **Collection book** (32 students, shown as ??? until discovered) to drive "gotta catch 'em all".
- A visible house that grows floor by floor, so other players can see who's winning.

## Tuning tips

All numbers live in `Config.lua`: room and facility prices, room tiers, material prices and their 🎀 decor, furniture prices and income boosts. To speed everything up, raise rarity `income` values or lower `RoomUnlockCost`. The lot size and tile size are at the top of `House.lua`; hallway tile, support and extra-tile prices are next to the room prices in `Config.lua`.

## Ideas for next updates

These keep players coming back if you announce them as "UPDATE 1, 2, 3...":
- Limited-time event banners (Halloween students, Exchange Week)
- Trading between players
- Furniture for dorm rooms, and free placement (drag furniture anywhere)
- Demolishing rooms on the floor plan
- Students that take the stairs and visit other floors (the pathfinding already knows the stairs)
- Exams or a "School Inspection" mini-event that rewards high satisfaction
- Rebirth/prestige: reset your school for a permanent multiplier
