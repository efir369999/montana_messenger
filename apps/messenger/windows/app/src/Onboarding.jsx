import { useEffect, useRef, useState } from "react";
import { CallsignPicker, Crop } from "./Profile.jsx";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { TermsView } from "./Terms.jsx";
import logo from "./assets/logo.png";
import iconGlass from "./assets/icon_glass.png";
import burgundy from "./assets/montana_burgundy.png";
import { GroundPicker, PageGround, PAGE } from "./Ground.jsx";
import { listen } from "@tauri-apps/api/event";
import { spoken } from "./HomeNode.jsx";

// THE ONBOARDING of iOS Montana 2251 (MontanaOnboardingView, MontanaSettings.swift 2380-2960): the sign-in choice, the
// intro, then -- after «Create» -- the warning, the 24 words and the name; «Open identity» is the recovery from the
// phrase. The words are seen here only, held by this screen alone, and copied from the Rust side.
// The login pages stand on the burgundy ground until the person being made chooses a ground of their own: «Create» opens my
// page's chooser first (iOS MTWallpaperPicker, the author's word 30.09), its checkmark makes the person, and the making's pages
// wear that ground from then on. Not yet on Windows, said in docs/WINDOWS.md: the phone-number door (its confirming bot).

function Door({ blue, disabled, onClick, children }) {
  return (
    <button className={`door${blue ? " door-blue" : ""}`} disabled={disabled} onClick={onClick}>{children}</button>
  );
}

/** A sentence with iOS's markdown links: [word](montana://terms) and [word](montana://privacy). */
function Linked({ text, onTerms }) {
  const parts = [];
  const rx = /\[([^\]]+)\]\(montana:\/\/(terms|privacy)\)/g;
  let at = 0, m;
  while ((m = rx.exec(text))) {
    parts.push(text.slice(at, m.index));
    const [word, which] = [m[1], m[2]];
    parts.push(<a key={m.index} href="#" onClick={(e) => { e.preventDefault(); which === "terms" ? onTerms() : invoke("open_site", { page: "privacy" }); }}>{word}</a>);
    at = m.index + m[0].length;
  }
  parts.push(text.slice(at));
  return <>{parts}</>;
}

function Toggle({ on, onChange, children }) {
  return (
    <label className="toggle-row">
      <span>{children}</span>
      <input type="checkbox" role="switch" checked={on} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
}

function Alert({ title, text, onClose }) {
  return (
    <div className="alert-shade" role="alertdialog">
      <div className="alert">
        <div className="alert-title">{title}</div>
        {text && <div className="alert-text">{text}</div>}
        <button onClick={onClose}>{t("Got it")}</button>
      </div>
    </div>
  );
}

export default function Onboarding({ onDone }) {
  const [step, setStep] = useState("doors");   // doors, intro, warn, words, name, recover
  const [creating, setCreating] = useState(false);
  const [words, setWords] = useState(null);
  const [understood, setUnderstood] = useState(false);
  const [saved, setSaved] = useState(false);
  const [copied, setCopied] = useState(false);
  const [name, setName] = useState("");
  const [callsign, setCallsign] = useState("");
  const [typed, setTyped] = useState("");
  const [restoring, setRestoring] = useState(false);
  const [problem, setProblem] = useState("");
  const [alert, setAlert] = useState(null);
  const [terms, setTerms] = useState(false);
  const [picking, setPicking] = useState(false);   // the call signs listed
  const [photo, setPhoto] = useState(null);        // the file chosen for the face, and the face kept
  const [face, setFace] = useState(null);
  const facePicker = useRef(null);
  const [ground, setGround] = useState(false);              // my page's ground being chosen, before the person is made
  const [groundChosen, setGroundChosen] = useState(false);  // chosen: the making's pages wear it
  const [canReturn, setCanReturn] = useState(false);        // a person waits on this computer's shelf: the cross brings them back
  useEffect(() => {
    invoke("seats_state").then((s) => {
      setCanReturn(s.can_return);
      // a seat emptied to make a person opens on the Montana road, my page's ground carried into it (iOS makeRoom, carry)
      if (s.adding) setStep("intro");
      if (s.carry) {
        try { if (localStorage.getItem("chatWall.page") === null) localStorage.setItem("chatWall.page", s.carry); } catch { /* the ground stays the default */ }
        window.dispatchEvent(new CustomEvent("montana-ground"));
        setGroundChosen(true);
      }
    }).catch(() => {});
  }, []);

  async function create() {
    setCreating(true);
    try {
      const w = await invoke("identity_create");
      setWords(w);
      const st = await invoke("identity_state");
      setCallsign(st.callsign);
      setStep("warn");
    } catch (e) {
      setAlert({ title: t("The identity could not be stored on this device"),
                 text: t("Nothing was created. Unlock the device and try again — an identity that is not stored cannot be opened at the next launch.") });
    } finally {
      setCreating(false);
    }
  }

  // THE PERSON'S OWN NODE, named beside the words (iOS nodeHost, 28.09): the copy it holds comes back before the first screen
  const [nodeHost, setNodeHost] = useState("");
  const [refusal, setRefusal] = useState(null);
  const [share, setShare] = useState(null);
  useEffect(() => {
    let stop = null, gone = false;
    listen("montana://home-node", (e) => setShare(e.payload.share == null ? null : (e.payload.what === "fetching" ? e.payload.share / 2 : 0.5 + e.payload.share / 2)))
      .then((u) => { if (gone) u(); else stop = u; });
    return () => { gone = true; stop?.(); };
  }, []);
  /** THE WORDS OPENED; THE PERSON'S OWN NODE, IF NAMED, HANDS THE COPY BACK (iOS takeFromNode) -- otherwise the first screen; a
   *  refusal is spoken, with «Try again» and the person's own way on without the copy. */
  async function takeFromNode() {
    const h = nodeHost.trim();
    if (!h) { onDone({ restored: true }); return; }
    await invoke("home_node_host", { host: h }).catch(() => {});
    await invoke("home_node_switch", { on: true }).catch(() => {});
    setStep("taking");
    invoke("home_node_take_back").then(() => onDone({ restored: true })).catch((e) => setRefusal(spoken(String(e))));
  }

  async function restore() {
    setProblem("");
    setRestoring(true);
    try {
      await invoke("identity_restore", { words: typed });
      setTyped("");
      await takeFromNode();
    } catch (e) {
      if (e?.kind === "WordCount") setProblem(t("Exactly 24 words required (entered \\(words.count))", { "words.count": e.count }));
      else if (e?.kind === "Storage") setProblem(t("The identity could not be stored on this device"));
      else setProblem(t("Invalid phrase. Check the words and their order."));
    } finally {
      setRestoring(false);
    }
  }

  async function finishName() {
    await invoke("identity_set_name", { name });
    setWords(null);   // the words leave this screen with it
    onDone({ restored: false });
  }

  const back = (to) => (
    <button className="back" onClick={() => setStep(to)} aria-label={t("Back")}>
      <Glyph name="back" size={20} color="#fff" /><span>{t("Back")}</span>
    </button>
  );

  // the words in iOS's order: two columns, the first half down the left (MontanaSettings 2657-2660)
  const half = words ? Math.ceil(words.length / 2) : 0;
  const order = words ? [...Array(half).keys()].flatMap((r) => (r + half < words.length ? [r, r + half] : [r])) : [];

  return (
    <div className={"onboarding" + (groundChosen ? " grounded" : "")} style={groundChosen ? undefined : { backgroundImage: `url(${burgundy})` }}>
      {groundChosen && <div className="ob-ground"><PageGround /></div>}
      {canReturn && (step === "doors" || step === "intro" || step === "recover") && (
        <button className="ob-cross" onClick={() => invoke("seat_return").catch(() => {})} aria-label={t("Cancel")}>
          <Glyph name="close" size={18} color="#fff" />
        </button>
      )}
      {step === "doors" && (
        <div className="ob-page">
          <div className="grow" />
          <img className="door-icon" src={iconGlass} alt="" />
          {/* one door now: no line under the title (iOS 2304 MontanaSettings 2827) */}
          <h1 className="ob-title">{t("Sign in to Montana")}</h1>
          <div className="grow" />
          <div className="doors">
            <Door onClick={() => setStep("intro")}>
              <img className="door-logo" src={logo} alt="" />{t("Continue with Montana")}
            </Door>
          </div>
          <div className="ob-legal">
            <Linked text={t("By continuing, you agree to the [Terms of Use](montana://terms) and [Privacy Policy](montana://privacy).")}
                    onTerms={() => setTerms(true)} />
          </div>
        </div>
      )}

      {step === "intro" && (
        <div className="ob-page">
          {back("doors")}
          <div className="grow" />
          <div className="glow"><img src={logo} alt="" /></div>
          <div className="ob-brand">Montana</div>
          <div className="ob-lead">{t("A private messenger. Your identity comes from your secret phrase, and your chats are encrypted on your device.")}</div>
          <div className="priv">
            {[["key", "Identity from 24 words", "Only you hold the key"], ["shield", "End-to-end encryption", "The key lives on your devices"],
              ["at", "Name or invitation", "People reach you by either"], ["trianglePath", "Sealed on the way", "Nodes carry envelopes they cannot open"]]
              .map(([g, a, b]) => (
                <div className="priv-row" key={a}>
                  <Glyph name={g} size={24} color="#fff" />
                  <div><div className="priv-a">{t(a)}</div><div className="priv-b">{t(b)}</div></div>
                </div>
              ))}
          </div>
          <div className="grow" />
          <div className="doors">
            <Door blue disabled={creating} onClick={() => setGround(true)}>{creating && <span className="spinner" />}{creating ? t("Bringing an identity into being…") : t("Create")}</Door>
            <Door onClick={() => setStep("recover")}>{t("Open identity")}</Door>
          </div>
        </div>
      )}

      {step === "warn" && (
        <div className="ob-page">
          <div className="grow" />
          <Glyph name="warnShield" size={52} color="#ff9f0a" />
          <h2 className="ob-h2">{t("Full control — full responsibility")}</h2>
          <div className="ob-text">{t("The key to your identity is your 24-word seed phrase, which you're about to see. Recovery is only possible with it.\n\nLose it and you lose access to your identity and chats forever. Don't show it to anyone.\n\nStore it securely — using whatever method of storing confidential data you trust (for example, a password manager), or write it down by hand on paper and keep it offline. Don't take a screenshot or save it in Notes.")}</div>
          <Toggle on={understood} onChange={setUnderstood}>{t("I understand and take responsibility")}</Toggle>
          <div className="grow" />
          <div className="doors"><Door blue disabled={!understood} onClick={() => setStep("words")}>{t("Show Words")}</Door></div>
        </div>
      )}

      {step === "words" && words && (
        <div className="ob-page">
          <h2 className="ob-h2">{t("Your 24-word seed phrase")}</h2>
          <div className="ob-caption">{t("Store it securely: a password manager you trust, or write it down on paper and keep it offline. Don't take a screenshot or store it in Notes.")}</div>
          <div className="word-grid">
            {order.map((i) => (
              <div className="word" key={i}><span className="word-n">{i + 1}.</span><b>{words[i]}</b></div>
            ))}
          </div>
          <div className="doors">
            <Door onClick={async () => setCopied(await invoke("identity_copy_words"))}>{copied ? t("Copied") : t("Copy")}</Door>
          </div>
          <Toggle on={saved} onChange={setSaved}>{t("I've saved the words in a safe place")}</Toggle>
          <div className="doors"><Door blue disabled={!saved} onClick={() => { setWords(null); setStep("name"); }}>{t("Your identity in Montana")}</Door></div>
        </div>
      )}

      {step === "name" && (
        <div className="ob-page">
          <div className="grow" />
          <div className="name-card">
            {/* THE FACE ON THE FIRST SCREEN (iOS onboarding's photo): chosen, framed, kept as the editor keeps it */}
            <button className="ob-face" onClick={() => facePicker.current?.click()} aria-label={t(face ? "Change photo" : "Choose photo")}>
              {face ? <img src={face} alt="" /> : <Glyph name="photo" size={34} color="rgba(235,235,245,0.6)" />}
            </button>
            <input ref={facePicker} type="file" accept="image/*" hidden onChange={(e) => { if (e.target.files[0]) setPhoto(e.target.files[0]); e.target.value = ""; }} />
            <input autoFocus className="name-field" placeholder={callsign || t("First name")} value={name} maxLength={64}
                   onChange={(e) => setName(e.target.value)} onKeyDown={(e) => e.key === "Enter" && finishName()} />
            <button className="ob-link" onClick={() => setPicking(true)}>{t("Choose a call sign")}</button>
            <div className="ob-caption">{t("Everything here stays on your device. Nothing is published: your correspondent sees only what you choose to show. Leave the name empty and your call sign is used.")}</div>
          </div>
          {picking && <CallsignPicker current={name} onPick={(r) => { setName(r); setPicking(false); }} onClose={() => setPicking(false)} />}
          {photo && <Crop file={photo} onCancel={() => setPhoto(null)} onDone={async (bytes) => {
            await invoke("face_set", bytes).catch(() => {});
            setFace(URL.createObjectURL(new Blob([bytes], { type: "image/jpeg" })));
            setPhoto(null);
          }} />}
          <div className="grow" />
          <div className="doors"><Door blue onClick={finishName}>{t("Done")}</Door></div>
        </div>
      )}

      {step === "recover" && (
        <div className="ob-page">
          {back("intro")}
          <Glyph name="restore" size={46} color="#fff" />
          <h2 className="ob-h2">{t("Recovery from phrase")}</h2>
          <div className="ob-caption">{t("Enter the 24 words separated by spaces, in the correct order.")}</div>
          <textarea className="recover-field" value={typed} spellCheck={false} autoCorrect="off" autoCapitalize="off" autoComplete="off"
                    onChange={(e) => setTyped(e.target.value)} />
          <input className="recover-field recover-node" placeholder={t("Your node (optional)")} aria-label={t("Your node (optional)")} value={nodeHost}
                 spellCheck={false} autoCapitalize="off" autoComplete="off" onChange={(e) => setNodeHost(e.target.value)} />
          {problem && <div className="problem">{problem}</div>}
          <div className="grow" />
          <div className="doors">
            <Door blue disabled={restoring} onClick={restore}>{restoring && <span className="spinner" />}{restoring ? t("Restoring…") : t("Restore")}</Door>
          </div>
        </div>
      )}

      {step === "taking" && (
        <div className="ob-page">
          <div className="grow" />
          <div className="glow"><img src={logo} alt="" /></div>
          <div className="ob-caption" role="status">{t("Taking your history back")}</div>
          {share == null ? <span className="spinner" /> : (
            <div className="node-track" role="progressbar" aria-label={t("Taking your history back")} aria-valuenow={Math.round(share * 100)}>
              <i style={{ width: `${Math.round(share * 100)}%` }} />
            </div>
          )}
          <div className="grow" />
        </div>
      )}
      {refusal && (
        <div className="alert-shade" role="alertdialog" aria-label={t("Your history")}>
          <div className="alert">
            <b>{t("Your history")}</b>
            <p>{refusal}</p>
            <div className="alert-keys stacked">
              <button onClick={() => { setRefusal(null); takeFromNode(); }}>{t("Try again")}</button>
              <button onClick={() => { setRefusal(null); onDone({ restored: true }); }}>{t("Continue without the copy")}</button>
            </div>
          </div>
        </div>
      )}
      {alert && <Alert title={alert.title} text={alert.text} onClose={() => setAlert(null)} />}
      {terms && (
        <div className="sheet-shade" onClick={() => setTerms(false)}>
          <div className="sheet" onClick={(e) => e.stopPropagation()}><TermsView /></div>
        </div>
      )}
      {ground && <GroundPicker conv={PAGE} onClose={() => setGround(false)}
                               onDone={() => { setGround(false); setGroundChosen(true); create(); }} />}
    </div>
  );
}

/** The first screen after the identity, before the first word (MontanaTermsGate): the terms and «I agree». */
export function TermsGate({ onAgree }) {
  return (
    <div className="gate"><TermsView gate onAgree={onAgree} /></div>
  );
}

/** WelcomeView: the logo and «Montana» for 0.6 s (MontanaSettings 2947). */
export function Welcome() {
  return (
    <div className="welcome"><img src={logo} alt="" /><div>Montana</div></div>
  );
}
