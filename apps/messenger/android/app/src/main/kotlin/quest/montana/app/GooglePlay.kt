package quest.montana.app

/**
 * THE GOOGLE PLAY BUILD (the author's word 31.10.2026: «before the road we take every coin and VPN off the app, or Google will not
 * let us in»; and then: «so that we bring the coins and the VPN back fast»). Nothing of the coins is deleted -- the doors are shut,
 * and these two switches are the only place that shuts them.
 *
 * COINS false: no wallet in the drawer (Home), no wallet beside a pair's name (Conversation walletStands), no coin's key in the
 * field (ChatInputBar.coins), no wallet from a coin's link (MainActivity), no road from a coin letter's plate to its move
 * (WalletPage.coinPlate), and no word of a wallet in the onboarding (priv_address_*), the seed's guard (sg_account) or the level's
 * rule (lv_footer_play). The book of coins goes on beneath (the core still counts its seconds).
 *
 * VPN false: the VPN left for its own app 08.10, so nothing of it stands here today; its two names in the wallet's history
 * (tc_src_vpnwall, tc_src_vpnpay) are behind the wallet. Any VPN door ported later stands behind this switch.
 *
 * SELF_UPDATE false (the author's word 31.10.2026 20:0x: one build for the site and Google Play, and Play lets no app update itself
 * past it): the app brings and installs no newer Montana -- the notice, the update banner and the release's «Update» lead to Google
 * Play's page when Play installed the app, to the site's page in the browser otherwise (Update.shop); the manifest asks no
 * REQUEST_INSTALL_PACKAGES. The rest of Update stays: the site's latest.json is still read, the Montana room still hears each build.
 *
 * TO BRING THEM BACK: set them to true and build -- every door returns as it was (for SELF_UPDATE also put the manifest's
 * REQUEST_INSTALL_PACKAGES line back, written there in a comment). `git grep GooglePlay.` lists every gate.
 */
object GooglePlay {
    const val COINS = false
    const val VPN = false
    const val SELF_UPDATE = false
}
