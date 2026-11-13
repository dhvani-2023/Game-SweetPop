import Foundation

/**
 * iOS-only extras on top of the Android port (README "Upgrades over Android"). Every flag switches one feature;
 * with a flag off that part of the game behaves exactly like the Android port.
 *
 * Where each one shows up:
 * • economy      — coin pill on the map's top bar, "+N coins" on the Win dialog, coins flying into the pill.
 * • boosters     — booster bar above the game's bottom bar (Lollipop Hammer, Free Swap, +5 Moves), the booster
 *                  shop dialog, and the "+5 Moves" offer on the Lose dialog (free once per attempt).
 * • dailySpin    — wheel button on the left of the map, with a "!" badge while today's spin is unused.
 * • loginGift    — 7-day gift popup on the first map visit of each day.
 * • episodeChest — chest after winning the last level of an episode (20, 40, 60…).
 * • autosave     — the level in progress is saved when the app goes to the background; the map then offers
 *                  "Continue level N?" after iOS closed the app.
 * • colorBlind   — Settings › Gameplay › "Colour-blind symbols" (off by default).
 */
enum Features {
    static var economy = true
    static var boosters = true
    static var dailySpin = true
    static var loginGift = true
    static var episodeChest = true
    static var autosave = true
    static var colorBlind = true
}
