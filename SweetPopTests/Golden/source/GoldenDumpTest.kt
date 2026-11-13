package com.puzzel.lab.sweetpop

import com.puzzel.lab.sweetpop.game.Board
import com.puzzel.lab.sweetpop.game.BoardEngine
import com.puzzel.lab.sweetpop.game.CandyColor
import com.puzzel.lab.sweetpop.game.ComboStart
import com.puzzel.lab.sweetpop.game.CreatedSpecial
import com.puzzel.lab.sweetpop.game.GoalTracker
import com.puzzel.lab.sweetpop.game.GoalType
import com.puzzel.lab.sweetpop.game.Level
import com.puzzel.lab.sweetpop.game.MatchFinder
import com.puzzel.lab.sweetpop.game.MatchGroup
import com.puzzel.lab.sweetpop.game.Move
import com.puzzel.lab.sweetpop.game.Pos
import com.puzzel.lab.sweetpop.game.SpecialType
import com.puzzel.lab.sweetpop.game.Wave
import com.puzzel.lab.sweetpop.levels.LevelCatalog
import com.puzzel.lab.sweetpop.levels.LevelGenerator
import org.junit.Test
import java.io.File
import java.util.Random
import kotlin.math.roundToInt

/**
 * Golden dump for the iOS port (run on a scratch copy only). Writes app/build/golden/:
 *  - levels.json: one fingerprint line per level 1..2000 (every LevelGenerator output field);
 *  - traces.json: a full engine trace of GameSimulationTest's greedy bot for levels 1..60 (seed n * 31);
 *  - bot.json: the bot's win/score for GameSimulationTest's whole sample (seed n * 31) and levels 1..20 (seed n * 7).
 * The bot below is GameSimulationTest.play/pickMove/cascade/score with recording added; the recording never
 * touches the board or the random generator, so the engine call order is exactly the test's.
 * The Swift GoldenTests rebuild every line with the same format and require 100% equality.
 */
class GoldenDumpTest {

    @Test
    fun dump() {
        val dir = File("build/golden").apply { mkdirs() }
        File(dir, "levels.json").writeText(jsonLines("levels", (1..LevelCatalog.LEVEL_COUNT).map { fingerprint(LevelGenerator.generate(it)) }))
        val traces = (1..60).map { n ->
            val out = ArrayList<String>()
            play(n, n * 31L, out)
            n to out
        }
        File(dir, "traces.json").writeText(buildString {
            append("{\"traces\":[\n")
            traces.forEachIndexed { i, (n, lines) ->
                append("{\"n\":").append(n).append(",\"seed\":").append(n * 31L).append(",\"lines\":[\n")
                lines.forEachIndexed { j, l -> append('"').append(l).append('"').append(if (j < lines.size - 1) ",\n" else "\n") }
                append("]}").append(if (i < traces.size - 1) ",\n" else "\n")
            }
            append("]}\n")
        })
        val sample = (1..120) + (121..2000 step 37)
        val bot = sample.map { n -> val (won, score) = play(n, n * 31L, null); "$n|${n * 31L}|$won|$score" } +
            (1..20).map { n -> val (won, score) = play(n, n * 7L, null); "$n|${n * 7L}|$won|$score" }
        File(dir, "bot.json").writeText(jsonLines("bot", bot))
        println("golden: ${LevelCatalog.LEVEL_COUNT} levels, ${traces.size} traces (${traces.sumOf { it.second.size }} lines), ${bot.size} bot games")
    }

    private fun jsonLines(key: String, lines: List<String>) = buildString {
        append("{\"").append(key).append("\":[\n")
        lines.forEachIndexed { i, l -> append('"').append(l).append('"').append(if (i < lines.size - 1) ",\n" else "\n") }
        append("]}\n")
    }

    // ------------------------------------------------------------------ formats

    private fun colorChar(c: CandyColor) = "ROYGBPN"[c.ordinal]

    /** n|w|h|colors|moves|goal|target|collect|stars|difficultyBits|playable|jelly|frosting|initial */
    private fun fingerprint(l: Level): String = buildString {
        append(l.number).append('|').append(l.width).append('|').append(l.height).append('|')
        append(l.colors).append('|').append(l.moves).append('|').append(l.goal.name).append('|').append(l.scoreTarget).append('|')
        append(l.collect.joinToString(",") { "${it.color.name}:${it.count}" }).append('|')
        append(l.starScores.joinToString(",")).append('|')
        append(java.lang.Float.floatToIntBits(l.difficulty)).append('|')
        append(l.playable.joinToString("") { if (it) "1" else "0" }).append('|')
        append(l.jelly.joinToString("")).append('|')
        append(l.frosting.joinToString("")).append('|')
        append(l.initial.joinToString("") { if (it < 0) "." else it.toString() })
    }

    /** Two chars per cell (colour + special ordinal, ".." empty, "##" hole), then jelly and frosting digits. */
    private fun boardString(b: Board): String = buildString {
        for (c in b.cells) {
            if (!c.playable) { append("##"); continue }
            val k = c.candy
            if (k == null) append("..") else append(colorChar(k.color)).append(k.special.ordinal)
        }
        append('/')
        for (c in b.cells) append(c.jelly)
        append('/')
        for (c in b.cells) append(c.frosting)
    }

    private fun idx(p: Pos, w: Int) = p.x + p.y * w

    private fun milli(f: Float) = (f * 1000f).roundToInt()

    private fun waveString(wv: Wave, w: Int): String = buildString {
        append("W").append(wv.index)
        append("|c=").append(wv.cleared.joinToString(",") { "${idx(it.pos, w)}${colorChar(it.candy.color)}${it.candy.special.ordinal}:${it.candy.id}${if (it.byBlast) "*" else ""}" })
        append("|j=").append(wv.jellyHits.joinToString(",") { "${idx(it.pos, w)}:${it.layersBefore}" })
        append("|f=").append(wv.frostingHits.joinToString(",") { "${idx(it.pos, w)}:${it.hpAfter}" })
        append("|t=").append(wv.triggers.joinToString(",") { t -> "${idx(t.pos, w)}:${t.special.ordinal}:${colorChar(t.color)}:${t.area.joinToString(".") { idx(it, w).toString() }}" })
        append("|s=").append(wv.scores.joinToString(",") { "${it.points}@${milli(it.x)}:${milli(it.y)}${colorChar(it.color)}" })
    }

    private fun groupsString(gs: List<MatchGroup>, w: Int) = gs.joinToString(";") { g ->
        "${g.cells.joinToString(".") { idx(it, w).toString() }}:${colorChar(g.color)}:${g.special.ordinal}:${g.specialPos?.let { idx(it, w) } ?: -1}:${g.runs.size}:${milli(g.centerX)}:${milli(g.centerY)}"
    }

    private fun comboString(s: ComboStart, w: Int) =
        "C ${s.kind.name} c=${idx(s.center, w)} b=${s.bombPos?.let { idx(it, w) } ?: -1} col=${colorChar(s.color)} " +
            "conv=${s.converted.joinToString(".") { idx(it, w).toString() }} area=${s.area.joinToString(".") { idx(it, w).toString() }} title=${s.title}"

    private fun createdString(cs: List<CreatedSpecial>, w: Int) =
        "S " + cs.joinToString(",") { "${idx(it.pos, w)}:${it.candy.id}:${colorChar(it.candy.color)}${it.candy.special.ordinal}" }

    /** Count, spawned count and a 31-hash over (id, from*1000, to, spawned) of every move, in order. */
    private fun movesString(moves: List<Move>): String {
        var h = 0
        for (m in moves) {
            h = h * 31 + m.candy.id
            h = h * 31 + milli(m.fromX)
            h = h * 31 + milli(m.fromY)
            h = h * 31 + m.toX
            h = h * 31 + m.toY
            h = h * 31 + if (m.spawned) 1 else 0
            h = h * 31 + milli(m.distance)
        }
        return "n=${moves.size} sp=${moves.count { it.spawned }} h=$h"
    }

    // ------------------------------------------------------------------ GameSimulationTest's bot, recorded

    private fun emptyOpenCells(b: Board): Int = b.cells.count { it.open && it.candy == null }

    private fun cascade(engine: BoardEngine, tracker: GoalTracker, board: Board, initial: List<MatchGroup>?, start: Int, out: MutableList<String>?) {
        var c = start
        var groups = initial ?: MatchFinder.findGroups(board)
        var guard = 0
        while (groups.isNotEmpty()) {
            check(guard++ < 200) { "cascade runaway" }
            out?.add("R c=$c g=${groupsString(groups, board.width)}")
            engine.beginMatches(groups, c)
            score(engine, tracker, board.width, out)
            val created = engine.finishResolve()
            out?.add(createdString(created, board.width))
            val moves = engine.applyGravity()
            out?.add("G " + movesString(moves))
            c++
            groups = MatchFinder.findGroups(board)
        }
    }

    private fun score(engine: BoardEngine, tracker: GoalTracker, w: Int, out: MutableList<String>?) {
        engine.resolveAll().forEach { wv ->
            out?.add(waveString(wv, w))
            wv.scores.forEach { tracker.addScore(it.points) }
            wv.cleared.forEach { cc ->
                val slot = tracker.collectSlotFor(cc.candy.color)
                if (slot >= 0) tracker.collect(slot)
            }
        }
    }

    private fun pickMove(board: Board, engine: BoardEngine, rnd: Random): Pair<Pos, Pos>? {
        val moves = MatchFinder.allValidMoves(board)
        if (moves.isEmpty()) return null
        var best = moves[rnd.nextInt(moves.size)]
        var bestScore = -1
        for (m in moves) {
            val s = if (engine.isComboSwap(m.first, m.second)) {
                100
            } else {
                engine.swap(m.first, m.second)
                val g = MatchFinder.findGroups(board, m.second, m.first)
                engine.swap(m.first, m.second)
                g.sumOf { it.cells.size + if (it.special != SpecialType.NONE) 10 else 0 }
            }
            if (s > bestScore || (s == bestScore && rnd.nextBoolean())) {
                bestScore = s
                best = m
            }
        }
        return best
    }

    private fun shuffleAndCascade(engine: BoardEngine, tracker: GoalTracker, board: Board, out: MutableList<String>?) {
        val moves = engine.shuffle()
        out?.add("X " + movesString(moves) + " b=" + boardString(board))
        cascade(engine, tracker, board, null, 0, out)
    }

    private fun play(n: Int, seed: Long, out: MutableList<String>?): Pair<Boolean, Int> {
        val level = LevelGenerator.generate(n)
        var id = 1
        val board = Board.fromLevel(level) { id++ }
        val rnd = Random(seed)
        val engine = BoardEngine(board, level.colors, rnd, startId = id)
        val tracker = GoalTracker(level)
        tracker.refresh(board)
        out?.add("L n=$n seed=$seed id=$id empty=${emptyOpenCells(board)} b=${boardString(board)}")
        var turn = 0
        while (tracker.movesLeft > 0) {
            val m = pickMove(board, engine, rnd) ?: run {
                out?.add("N")
                shuffleAndCascade(engine, tracker, board, out)
                pickMove(board, engine, rnd)
            } ?: break
            val (a, b) = m
            engine.swap(a, b)
            tracker.useMove()
            val combo = engine.isComboSwap(a, b)
            out?.add("M $turn ${a.x},${a.y}>${b.x},${b.y} combo=$combo")
            if (combo) {
                val start = engine.beginCombo(a, b)
                out?.add(comboString(start, board.width))
                score(engine, tracker, board.width, out)
                // Engine calls stay outside `out?.add(...)`: a safe call skips its argument when out is null.
                val created = engine.finishResolve()
                out?.add(createdString(created, board.width))
                val moves = engine.applyGravity()
                out?.add("G " + movesString(moves))
                cascade(engine, tracker, board, null, 1, out)
            } else {
                val groups = MatchFinder.findGroups(board, b, a)
                check(groups.isNotEmpty()) { "level $n bot picked a non-matching move" }
                cascade(engine, tracker, board, groups, 0, out)
            }
            tracker.refresh(board)
            out?.add(
                "T ml=${tracker.movesLeft} mu=${tracker.movesUsed} sc=${tracker.score} j=${tracker.jellyLeft} f=${tracker.frostingLeft} " +
                    "c=${tracker.collectRemaining.joinToString(",")} done=${tracker.isGoalComplete} b=${boardString(board)}",
            )
            turn++
            if (level.goal != GoalType.SCORE && tracker.isGoalComplete) {
                out?.add("E won=true sc=${tracker.score} stars=${tracker.starsFor(tracker.score)}")
                return true to tracker.score
            }
            if (MatchFinder.findValidMove(board) == null) shuffleAndCascade(engine, tracker, board, out)
        }
        out?.add("E won=${tracker.isGoalComplete} sc=${tracker.score} stars=${tracker.starsFor(tracker.score)}")
        return tracker.isGoalComplete to tracker.score
    }
}
