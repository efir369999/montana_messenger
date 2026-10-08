package quest.montana.app

import android.app.AlertDialog
import android.content.Context
import android.graphics.Color
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.Switch

/**
 * THE PAGE «YOUR NODE» (iOS HomeNodeView): the address, the node's word, the two acts, and what the node names it can
 * do. The set-up of a bare machine by its root login (iOS MontanaNodeSetup, over SSH) is not here: the platform has no
 * SSH of its own, and a third-party one is not taken in.
 */
class NodePage(private val act: MainActivity, private val onClose: () -> Unit) {
    val view: View
    private val stateRow = LinearLayout(act)
    private val bars = LinearLayout(act).apply { orientation = LinearLayout.VERTICAL }
    private val capsBox = LinearLayout(act).apply { orientation = LinearLayout.VERTICAL }
    private lateinit var host: EditText
    private lateinit var sendRow: View
    private lateinit var restoreRow: View

    private data class Cap(val id: String, val word: Int)
    private val capWords = listOf(
        Cap("vault", R.string.cap_vault), Cap("box", R.string.cap_box), Cap("blob", R.string.cap_blob),
        Cap("signal", R.string.cap_signal), Cap("turn", R.string.cap_turn), Cap("diag", R.string.cap_diag),
        Cap("stun", R.string.cap_stun), Cap("notify", R.string.cap_notify), Cap("gif", R.string.cap_gif),
        Cap("name", R.string.cap_name))

    init {
        val c: Context = act
        fun header(res: Int) = c.text(c.getString(res), 13f, MT.gray).apply { setPadding(dp(16), dp(20), dp(16), dp(6)) }
        fun row(iconRes: Int, tint: Int, label: String, onTap: () -> Unit) = c.hstack {
            setPadding(dp(16), dp(12), dp(16), dp(12))
            addView(c.icon(iconRes, tint), lp(dp(24), dp(24)).apply { marginEnd = dp(14) })
            addView(c.text(label, 16f), lp(0, WRAP, 1f))
            pressable(onTap)
        }
        val list = c.vstack(Gravity.NO_GRAVITY) {
            setPadding(dp(16), 0, dp(16), dp(24))
            addView(header(R.string.your_node_header))
            addView(c.plate {
                host = EditText(c).apply {
                    hint = c.getString(R.string.node_address)
                    setText(MontanaHomeNode.host)
                    setTextColor(Color.WHITE); setHintTextColor(MT.gray)
                    background = null
                    isSingleLine = true
                    inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                    imeOptions = EditorInfo.IME_ACTION_DONE
                    setOnEditorActionListener { _, _, _ -> commit(); clearFocus(); false }
                    setOnFocusChangeListener { _, has -> if (!has) commit() }
                    setPadding(dp(16), dp(14), dp(16), dp(14))
                }
                addView(c.hstack {
                    setPadding(dp(16), 0, 0, 0)
                    addView(c.icon(R.drawable.ic_hub, MT.gold), lp(dp(24), dp(24)))
                    addView(host, lp(0, WRAP, 1f))
                }, lp())
                addView(stateRow.apply { setPadding(dp(16), 0, dp(16), 0) }, lp())
                addView(bars.apply { setPadding(dp(16), 0, dp(16), 0) }, lp())
            }, lp())
            addView(c.text(c.getString(R.string.your_node_footer), 12f, MT.gray).apply { setPadding(dp(16), dp(8), dp(16), 0) })
            gap(20)
            addView(c.plate {
                var ready = false   // the switch set to what is stored is not the person's tap
                val sw = c.toggleRow(c.getString(R.string.node_copies_switch)) { on ->
                    if (!ready) return@toggleRow
                    MontanaHomeNode.setOn(act, on)
                    if (on) { commit(); act.background { HomeNodeWatch.tick(act, force = false) } }
                }.apply { setPadding(dp(16), dp(10), dp(16), dp(10)) }
                (0 until sw.childCount).map { sw.getChildAt(it) }.filterIsInstance<Switch>().firstOrNull()?.isChecked = MontanaHomeNode.on(act)
                ready = true
                addView(sw, lp())
                divider()
                sendRow = row(R.drawable.ic_arrow_circle_up, MT.green, c.getString(R.string.node_send_now)) { sendNow() }
                addView(sendRow, lp())
                divider()
                restoreRow = row(R.drawable.ic_arrow_circle_down, MT.orange, c.getString(R.string.node_restore)) { restore() }
                addView(restoreRow, lp())
            }, lp())
            addView(capsBox, lp())
        }
        view = c.vstack(Gravity.NO_GRAVITY) {
            setBackgroundColor(Color.BLACK)   // a page over the main screen stands on its own ground
            isClickable = true                // and takes the touches meant for it
            addView(c.topBar(c.getString(R.string.your_node), onBack = onClose))
            addView(ScrollView(c).apply { addView(list) }, lp(MATCH, 0, 1f))
        }
        HomeNodeWatch.onChange = { act.onMain { if (view.isAttachedToWindow) show() } }
        show()
        act.background { HomeNodeWatch.ask() }
    }

    private fun commit() {
        val before = MontanaHomeNode.host
        MontanaHomeNode.setHost(host.text.toString())
        if (host.text.toString() != MontanaHomeNode.host) host.setText(MontanaHomeNode.host)
        val s = HomeNodeWatch.state
        if (MontanaHomeNode.host != before || s is HomeNodeWatch.State.Unknown || s is HomeNodeWatch.State.NoHost)
            act.background { HomeNodeWatch.ask() }
    }

    /** The node's word, and this phone's own counts on the way, as bars. */
    private fun show() {
        val c: Context = act
        stateRow.removeAllViews()
        fun line(word: String, color: Int = Color.WHITE, detail: String? = null, busy: Boolean = false) = stateRow.addView(c.hstack {
            setPadding(0, dp(12), 0, dp(12))
            addView(c.text(word, 15f, color), lp(0, WRAP, 1f))
            if (detail != null) addView(c.text(detail, 13f, MT.gray))   // USER-DATA: a moment and a size, or a code
            if (busy) addView(ProgressBar(c).apply { indeterminateTintList = android.content.res.ColorStateList.valueOf(MT.gold) }, lp(dp(20), dp(20)))
        }, lp())
        when (val s = HomeNodeWatch.state) {
            is HomeNodeWatch.State.Asking -> line(c.getString(R.string.node_asking), busy = true)
            is HomeNodeWatch.State.None -> line(c.getString(R.string.node_holds_none))
            is HomeNodeWatch.State.Held -> line(c.getString(R.string.node_holds), detail =
                java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT).format(s.date) +
                    " · " + android.text.format.Formatter.formatShortFileSize(c, s.bytes))
            is HomeNodeWatch.State.Refused -> line(c.getString(R.string.node_refused_word), MT.red, s.code)
            is HomeNodeWatch.State.Silent -> line(c.getString(R.string.node_silent), detail = s.code)
            else -> {}
        }
        bars.removeAllViews()
        fun bar(word: Int, f: Double) = bars.addView(c.vstack(Gravity.NO_GRAVITY) {
            setPadding(0, dp(8), 0, dp(10))
            addView(c.hstack {
                addView(c.text(c.getString(word), 15f), lp(0, WRAP, 1f))
                addView(c.text("${(f * 100).toInt()}%", 13f, MT.gray))   // USER-DATA: a share
            }, lp())
            addView(ProgressBar(c, null, android.R.attr.progressBarStyleHorizontal).apply {
                max = 100; progress = (f * 100).toInt()
                progressTintList = android.content.res.ColorStateList.valueOf(MT.gold)
            }, lp())
        }, lp())
        HomeNodeWatch.sealing?.let { bar(R.string.node_sealing, it) }
        HomeNodeWatch.sending?.let { bar(R.string.node_sending, it) }
        HomeNodeWatch.fetching?.let { bar(R.string.node_fetching, it) }
        HomeNodeWatch.restoring?.let { bar(R.string.node_restoring, it) }
        val empty = MontanaHomeNode.host.isEmpty()
        val moving = HomeNodeWatch.sealing != null || HomeNodeWatch.sending != null || HomeNodeWatch.fetching != null || HomeNodeWatch.restoring != null
        sendRow.isEnabled = !empty && !moving; sendRow.alpha = if (sendRow.isEnabled) 1f else 0.4f
        restoreRow.isEnabled = HomeNodeWatch.state is HomeNodeWatch.State.Held && !moving
        restoreRow.alpha = if (restoreRow.isEnabled) 1f else 0.4f
        capsBox.removeAllViews()
        val caps = HomeNodeWatch.caps
        if (caps.isNotEmpty()) {
            capsBox.addView(c.text(c.getString(R.string.node_offers), 13f, MT.gray).apply { setPadding(dp(16), dp(20), dp(16), dp(6)) })
            capsBox.addView(c.plate {
                capWords.forEachIndexed { i, cap ->
                    if (i > 0) divider()
                    val on = cap.id in caps
                    addView(c.hstack {
                        setPadding(dp(16), dp(12), dp(16), dp(12))
                        addView(c.text(c.getString(cap.word), 15f, if (on) Color.WHITE else MT.gray), lp(0, WRAP, 1f))
                        addView(c.icon(R.drawable.ic_check, MT.blue).apply { alpha = if (on) 1f else 0f }, lp(dp(20), dp(20)))
                    }, lp())
                }
            }, lp())
        }
    }

    private fun say(word: String) = AlertDialog.Builder(act).setTitle(R.string.your_node).setMessage(word).setPositiveButton(R.string.ok, null).show()

    private fun sendNow() {
        if (!sendRow.isEnabled) return
        commit()
        act.background {
            HomeNodeWatch.send(act) { r ->
                HomeNodeWatch.ask()
                act.onMain {
                    when (r) {
                        is CopyResult.Made -> say(act.getString(R.string.node_taken_by, r.tally.chats, r.tally.records, r.tally.media))
                        is CopyResult.Refused -> say(r.why.spoken(act))
                        else -> {}
                    }
                }
            }
        }
    }

    private fun restore() {
        if (!restoreRow.isEnabled) return
        act.background {
            HomeNodeWatch.takeBack(act) { r ->
                act.onMain {
                    when (r) {
                        is CopyResult.Taken -> say(act.getString(R.string.node_taken_into, r.tally.chats, r.tally.records, r.tally.media))
                        is CopyResult.Refused -> say(r.why.spoken(act))
                        else -> {}
                    }
                }
            }
        }
    }
}

/** What the system says the default network is — for the diary, never shown. */
fun networkWord(c: Context): String {
    val cm = c.getSystemService(ConnectivityManager::class.java) ?: return "no manager"
    val n = cm.activeNetwork ?: return "no active network"
    val caps = cm.getNetworkCapabilities(n) ?: return "no capabilities"
    return listOf(NetworkCapabilities.TRANSPORT_WIFI to "wifi", NetworkCapabilities.TRANSPORT_CELLULAR to "cellular",
        NetworkCapabilities.TRANSPORT_VPN to "vpn", NetworkCapabilities.TRANSPORT_ETHERNET to "ethernet")
        .filter { caps.hasTransport(it.first) }.joinToString("+") { it.second }.ifEmpty { "other" }
}

/** Wi-Fi now, as the system names the default network (the daily road rides Wi-Fi alone). */
fun onWifi(c: Context): Boolean {
    val cm = c.getSystemService(ConnectivityManager::class.java) ?: return false
    val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
    return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
}
