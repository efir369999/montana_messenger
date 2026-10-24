import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { invoke } from "@tauri-apps/api/core";
import App from "./App.jsx";
import { setLanguage } from "./strings.js";
import { applyIcon, applyLook, applyMotion } from "./Look.jsx";
import "./app.css";
import "./chats.css";
import "./pages.css";

applyLook();
applyMotion();   // the feed's spring this machine keeps (iOS MTLetterMotion)
applyIcon();     // the app's icon this machine chose (iOS setAlternateIconName)   // the message style this machine keeps (iOS MTBubbleStyle), before the first bubble is drawn
// the language Settings chose (iOS AppLanguage) is known before the first word is drawn
invoke("settings_get")
  .then((s) => setLanguage(s.AppLanguage))
  .catch(() => {})
  .finally(() => {
    createRoot(document.getElementById("root")).render(
      <StrictMode>
        <App />
      </StrictMode>,
    );
  });
