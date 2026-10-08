package quest.montana.app

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ScrollView

/**
 * MY PAGE (iOS MontanaMyProfileView, opened from the drawer as MTMyPageFromDrawer): my profile as the people I write to see it — the
 * one face owner (FaceHead) at its circle, my name as it leaves this phone, my words and my link as they leave it, over my page's
 * ground. The back mark top left; «Edit» top right opens the profile's editor over the page, and its checkmark comes back to the page
 * drawn anew. My own wall stands under the head when the wall comes (iOS MTBoardPane(owner: nil)).
 */
fun myPage(act: MainActivity, onClose: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY) { setPadding(0, dp(56), 0, dp(40)) }
    val face = FaceHead(act, body)
    fun draw() = face.draw(SelfFace.load(act), Prefs.userName, false, MyAbout.bio(), PeerAbout.url(MyAbout.link()), "")
    draw()
    body.addView(face.view, lp())
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))   // my page's ground (iOS MTFacePage of .me)
        addView(ScrollView(c).apply { isVerticalScrollBarEnabled = false; addView(body); face.attach(this) }, FrameLayout.LayoutParams(MATCH, MATCH))
        // the back mark on its own round of glass, over the page (iOS MontanaBackMark)
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.back)
            addView(c.icon(R.drawable.ic_arrow_back_ios_new, Color.WHITE), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
            pressable { onClose() }
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.START).apply { setMargins(dp(14), dp(6), 0, 0) })
        // THE PAGE'S AUTHOR EDITS IT FROM IT (iOS MontanaEditMark, the author's word 25.09): the editor over the page closes itself,
        // never the page under it
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.pe_edit)
            addView(c.icon(R.drawable.ic_more_horiz, Color.WHITE), FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
            pressable { act.push { close -> Profile(act, onboarding = false) { close(); draw() }.view } }
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.END).apply { setMargins(0, dp(6), dp(14), 0) })
    }
}
