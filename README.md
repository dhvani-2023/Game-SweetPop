# Sweet Pop (iOS)

Native iOS port of the Android game in `/Volumes/Work/Raj/Android/SweetPop`.
This folder is a complete, independent Xcode project. It shares nothing with the other games.

| | |
|---|---|
| Bundle ID | `com.puzzel.lab.sweetpop` |
| Platform | iPhone, iOS 17+ |
| Status | **Port in progress** |

## Run it
1. Open `SweetPop.xcodeproj` in Xcode.
2. Pick an iPhone simulator (or your iPhone) and press **Run**.
3. For the App Store: in *Signing & Capabilities*, choose your Team once.

## What's inside
- `SweetPop/`: app code, art, sounds, fonts, icon.
- `SweetPopTests/`: unit tests, including "same level as Android" checks.
- `Packages/GameKit/`: this game's own copy of the engine code (sound, haptics, saving, game loop, exact Android random numbers).
- `Reference/Android/`: screenshots of the Android version, used to compare the look.

## Port plan
- **Game.** Match-3. 2,000 seeded levels in 100 episodes of 20.
  - Specials: striped, wrapped, colour bomb, plus all 7 special combos.
  - Blockers: jelly, frosting, shaped masks. Goals: score, jelly, collect, frosting.
  - Lives: 5, one regenerates every 20 min. Win bonus: "Sweet Frenzy". Hint after 5 s.
- **Port.**
  - Engine: `BoardEngine`, `MatchFinder`, `GoalTracker` and `LevelGenerator` → pure Swift. Keep the wave-by-wave resolve API that drives the animations.
  - Session: `GameViewModel` → `@Observable GameSession` on a pausable game clock, so pause freezes every animation.
  - Candies: the SDF `CandyPainter` (25 candies × 7/8/9-wide boards) renders per pixel at the splash, in parallel. Effects pool and `Backdrop` → Canvas.
  - Audio: `SynthBank` (16 SFX, 11 cascade chimes, 2 music loops) → `GameKit.Synth`.
- **Must match.** `java.util.Random(n·7919+1013)` in the generator and in the refill.
- **Screens.**
  - Splash (orbiting candies; at least 2.4 s while candies and audio are prepared) → Onboarding (3 pages, Skip, Terms/Privacy) → Map (2,000 nodes, pin hop after a win).
  - Level Start → Game → Pause / Win / Lose / No Lives / Lives Info / Confirm.
  - Settings, Documents.
- **Simulator pass.**
  - Levels 1–6 tutorials, a "Tricky" level, a loss that costs a life, and the "5 moves left!" warning.
  - Frenzy on win, and the lives timer still correct after relaunch.

## Upgrades over Android
- **Fixes:** Has no coins or boosters at all
- **New features:** Coins from wins (by stars). Boosters bought with coins: Lollipop Hammer, Free Swap, +5 Moves (this also gives the hidden ad seam a real use). Daily Spin wheel and 7-day login gift. Episode-complete chest. Mid-level autosave, so a level survives iOS closing the app. Colourblind mode (a symbol on each candy).
