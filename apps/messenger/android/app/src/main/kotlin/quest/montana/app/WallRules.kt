package quest.montana.app

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout

/**
 * WHO MAY WRITE ON MY WALL, OR SEE IT (iOS MTBoardRulePage, MontanaBoardViews 2444-2491; opened from Privacy, MontanaSettings
 * 1847-1874): the five rules, the chosen one checked, the rule standing from the first frame; «Some people» and «Everyone except»
 * lead to the people they name. A rule moved renews the wall's version (WallRule.choose), so the page goes to its visitors again.
 */
fun wallRulePage(act: MainActivity, a: WallRule.Act, onBack: () -> Unit): View {
    val c: Context = act
    val title = c.getString(if (a == WallRule.Act.WRITE) R.string.wall_who_write_mine else R.string.wall_who_see_mine)
    lateinit var body: LinearLayout
    fun draw() {
        body.removeAllViews()
        val rule = WallRule.current(a)
        body.section(null, null, *WallRule.Rule.values().map { r ->
            // the check is the platform's own mark in the words' white (no accent colour in our panels)
            val mark = c.icon(R.drawable.ic_check, Color.WHITE, 18).apply { alpha = if (r == rule) 1f else 0f }
            c.settingsRow(null, 0, c.getString(ruleWords(r)), mark, chevron = false) { WallRule.choose(r, a); draw() }
        }.toTypedArray())
        if (rule == WallRule.Rule.SOME || rule == WallRule.Rule.EXCEPT) body.section(null, null,
            c.settingsRow(null, 0, c.getString(R.string.wall_choose_people)) {
                act.push { close -> wallPeoplePage(act, a, deny = rule == WallRule.Rule.EXCEPT, onBack = close) }
            })
    }
    return settingsPage(act, title, onBack) {
        body = c.vstack(Gravity.NO_GRAVITY)
        addView(body, lp())
        draw()
    }
}

private fun ruleWords(r: WallRule.Rule) = when (r) {
    WallRule.Rule.ONLY_ME -> R.string.wall_rule_only_me
    WallRule.Rule.EVERYONE -> R.string.wall_rule_everyone
    WallRule.Rule.CONTACTS -> R.string.wall_rule_contacts
    WallRule.Rule.SOME -> R.string.wall_rule_some
    WallRule.Rule.EXCEPT -> R.string.wall_rule_except
}

/**
 * THE PEOPLE A RULE NAMES (iOS MTBoardPeoplePage 2493-2545): the correspondents this phone holds a pipe with -- no group, no
 * room of my own -- each row whole a target, the chosen checked; every touch is kept at once.
 */
fun wallPeoplePage(act: MainActivity, a: WallRule.Act, deny: Boolean, onBack: () -> Unit): View {
    val c: Context = act
    val title = c.getString(when {
        a == WallRule.Act.WRITE && !deny -> R.string.wall_who_can_write
        a == WallRule.Act.WRITE -> R.string.wall_who_cannot_write
        !deny -> R.string.wall_who_can_see
        else -> R.string.wall_who_cannot_see
    })
    val chosen = (if (deny) WallRule.denied(a) else WallRule.allowed(a)).toMutableSet()
    val people = Book.all().filter { !Groups.isKey(it.ref) && SamePair.merged(it.ref) == null && Book.secret(it.ref) != null }
    fun keep() = if (deny) WallRule.setDenied(chosen.toSet(), a) else WallRule.setAllowed(chosen.toSet(), a)
    return settingsPage(act, title, onBack) {
        if (people.isEmpty()) return@settingsPage
        section(null, null, *people.map { ch ->
            val name = ch.shown?.ifBlank { null } ?: c.getString(R.string.peer)
            val mark = c.icon(R.drawable.ic_check, Color.WHITE, 18).apply { alpha = if (ch.ref in chosen) 1f else 0f }
            c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                minimumHeight = dp(52)
                setPadding(dp(16), dp(8), dp(14), dp(8))
                val face = Book.shownFace(ch.ref).takeIf { it.exists() }?.let { f -> BitmapFactory.decodeFile(f.path) }
                addView(c.avatar(face, name, 36), lp(dp(36), dp(36)))
                gap(12)
                addView(c.text(name, 16f).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: the correspondent's name
                addView(mark, lp(dp(18), dp(18)))
                pressable {
                    if (!chosen.remove(ch.ref)) chosen.add(ch.ref)
                    mark.alpha = if (ch.ref in chosen) 1f else 0f
                    keep()
                }
            }
        }.toTypedArray())
    }
}
