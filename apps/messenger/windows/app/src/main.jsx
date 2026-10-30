import { Component, StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { invoke } from "@tauri-apps/api/core";
import App from "./App.jsx";
import { setLanguage, t } from "./strings.js";
import { applyIcon, applyLook, applyMotion } from "./Look.jsx";
import { heardSettings } from "./Settings.jsx";
import "./press.js";   // a double press stays on the layer it began on
import "./app.css";
import "./chats.css";
import "./pages.css";

applyLook();
applyMotion();   // the feed's spring this machine keeps (iOS MTLetterMotion)
applyIcon();     // the app's icon this machine chose (iOS setAlternateIconName)   // the message style this machine keeps (iOS MTBubbleStyle), before the first bubble is drawn

/** When the window may draw itself anew by its own fall: once in this long, so a fall at the very start never turns into a loop. */
const FELL_AGAIN_MS = 30000;
const FELL = "montana.fell";
function mayDrawAgain() {
  try {
    if (Date.now() - (Number(sessionStorage.getItem(FELL)) || 0) < FELL_AGAIN_MS) return false;
    sessionStorage.setItem(FELL, String(Date.now()));
    return true;
  } catch {
    return false;   // nowhere to remember the last time: the person's own press draws it anew
  }
}

/** THE WINDOW IS NEVER LEFT EMPTY (the review of 25.10.2026): a page that throws while it is drawn takes the whole tree away with it,
 *  and the window stood black, taking nothing, until the tray's Quit. The fall is traced and the window drawn anew, once in
 *  FELL_AGAIN_MS; a second fall soon after leaves the black ground with one button that draws it anew (a Windows adaptation: iOS
 *  has no tree to lose). */
class Fall extends Component {
  constructor(props) { super(props); this.state = { fell: false }; }
  static getDerivedStateFromError() { return { fell: true }; }
  componentDidCatch(error) {
    invoke("trace", { line: `window fell: ${String(error?.message || error).slice(0, 160)}` }).catch(() => {});
    if (mayDrawAgain()) window.location.reload();
  }
  render() {
    if (!this.state.fell) return this.props.children;
    return (
      <div className="splash fell">
        <button className="primary-wide" onClick={() => window.location.reload()}>{t("Try again")}</button>
      </div>
    );
  }
}

// the language Settings chose (iOS AppLanguage) is known before the first word is drawn, and every page of the settings draws its
// values at once from what was heard here (iOS @AppStorage)
invoke("settings_get")
  .then((s) => { heardSettings(s); setLanguage(s.AppLanguage); })
  .catch(() => {})
  .finally(() => {
    createRoot(document.getElementById("root")).render(
      <StrictMode>
        <Fall>
          <App />
        </Fall>
      </StrictMode>,
    );
  });
