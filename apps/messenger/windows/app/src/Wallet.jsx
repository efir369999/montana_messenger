import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { t, locale } from "./strings.js";
import { Page, Section, Waiting } from "./Settings.jsx";
import { chatName, Face, hourOf, SAVED, SelfFace } from "./Chats.jsx";
import { Glyph } from "./TopBar.jsx";
import { CoinSpinner, MintCoin, PULL, pullAngle } from "./Coin.jsx";
import { AppIcon, TITLES } from "./Library.jsx";
import timeSend from "./assets/ios/time_send.png";
import { PageGround } from "./Ground.jsx";
import { PlayerBar } from "./PlayerBar.jsx";
import { useLeave } from "./leave.js";

/** THE TIME COIN (iOS MTWalletPage, MTWalletCore.swift): a coin is a second -- the constitution, article 11 -- so the balance is the
 *  time the book holds; the coins under it are what a transfer moves (a $TCM is a billion of them). The page standing open mints by
 *  the second (iOS MTWalletPull, on by default), a touch of the coin mints the second's coin at most; the Available is what the
 *  person's chain on the nodes holds for its one owner (Rust: coins.rs, cointx.rs, wallet.rs). */

/** Big numbers part their thousands with commas, in every language (iOS MTCoinText.count). */
export function count(n) {
  return String(Math.abs(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ",").replace(/^/, n < 0 ? "-" : "");
}
/** THE UNITS AS PEOPLE COUNT THEM (iOS MTCoinText.time, the author's word 19.10.2026 20:2x MSK): the spans of MTTimeSpan -- epoch,
 *  century, year, month, week, day, hour, minute, second -- each taking what the larger left, a unit at zero unsaid, every unit that
 *  is not; the system writes year to second in its narrow abbreviated form (iOS DateComponentsFormatter .abbreviated, .dropAll), the
 *  catalogue the century and the epoch; «−» before a negative span when signed. */
export function timeOf(coins, signed = true) {
  let rest = Math.abs(Math.trunc(coins || 0));
  const take = (s) => { const n = Math.floor(rest / s); rest %= s; return n; };
  const epochs = take(31536000000), centuries = take(3153600000);
  const c = calendarSpan(rest);
  const parts = [];
  if (epochs > 0) parts.push(t("%lld ep.").replace("%lld", epochs));
  if (centuries > 0) parts.push(t("%lld cent.").replace("%lld", centuries));
  if (!parts.length || Math.abs(coins) % 3153600000 !== 0) parts.push(span(c));
  const told = parts.join(" ");
  return signed && coins < 0 ? "−" + told : told;
}
/** A span cut as the system's calendar cuts it (iOS DateComponentsFormatter.string(from:): the components from now to now + the
 *  span, years and months by the calendar -- 40 days are «1 month 1 week 2 days», never a month of 30.4 days and its hours). */
export function calendarSpan(seconds) {
  const from = new Date(), to = new Date(from.getTime() + seconds * 1000);
  const step = (d, unit, n) => { const x = new Date(d); if (unit === "y") x.setFullYear(x.getFullYear() + n); else x.setMonth(x.getMonth() + n); return x; };
  let cur = from;
  const count = (unit) => { let n = 0; while (step(cur, unit, n + 1) <= to) n++; cur = step(cur, unit, n); return n; };
  const years = count("y"), months = count("m");
  let rest = Math.max(0, Math.round((to - cur) / 1000));
  const take = (s) => { const n = Math.floor(rest / s); rest %= s; return n; };
  return { years, months, weeks: take(604800), days: take(86400), hours: take(3600), minutes: take(60), seconds: rest };
}
const UNIT = { years: "year", months: "month", weeks: "week", days: "day", hours: "hour", minutes: "minute", seconds: "second" };
/** Year to second as the system writes a span (iOS .abbreviated, .dropAll; matched to its strings, PR #13 25.10.2026, level B): each
 *  unit in the language's narrow form -- «5 д. 3 ч 15 мин», «1 н. 1 д.», «5d 3h 15m» -- but the month in English is «mo», as iOS
 *  writes it, where the narrow form would say «m» for the month and the minute alike. */
function span(c) {
  const kept = Object.entries(c).filter(([, v]) => v > 0);
  if (!kept.length) kept.push(["seconds", 0]);   // nothing at all is said as no seconds (iOS «0 с»): the zero said, never an empty line
  const ru = locale.startsWith("ru");
  return kept.map(([k, v]) => {
    if (k === "months" && !ru) return `${v}mo`;
    try {
      return new Intl.NumberFormat(locale, { style: "unit", unit: UNIT[k], unitDisplay: "narrow" }).format(v);
    } catch {
      const w = { years: ["y", "г."], months: ["mo", "м."], weeks: ["w", "н."], days: ["d", "д."], hours: ["h", "ч"], minutes: ["m", "мин"], seconds: ["s", "с"] };
      return ru ? `${v} ${w[k][1]}` : `${v}${w[k][0]}`;
    }
  }).join(" ");
}
/** The coins as the catalogue writes them (iOS «%@ coins»: «N монет», «N coins», one word for every count). */
function coinsOf(n) {
  return t("%@ coins").replace("%@", count(n));
}
/** The coins as Montana, in integers alone: one coin is 0.000000001 (iOS MTChatMint.montana). */
function montana(coins) {
  const whole = Math.floor(coins / 1e9), part = String(coins % 1e9).padStart(9, "0");
  return `${count(whole)}.${part}`;
}
/** π as far as a level reveals it: 3, 3.1, 3.14 ... (iOS MTPiLevels.revealed). */
function pi(place) {
  const d = "3141592653589793238".slice(0, Math.max(0, place));
  return d.length < 2 ? d : d[0] + "." + d.slice(1);
}

const UNITS = ["time", "coins", "tcm"];

/** THE SPANS OF TIME AS PEOPLE COUNT THEM (iOS MTTimeSpan): their lengths in seconds. */
const SPANS = [["second", 1], ["minute", 60], ["hour", 3600], ["day", 86400], ["week", 604800], ["month", 2628000], ["year", 31536000],
               ["century", 3153600000], ["epoch", 31536000000]];
const SPAN_TITLE = { second: "Second", minute: "Minute", hour: "Hour", day: "Day", week: "Week", month: "Month", year: "Year", century: "Century", epoch: "Epoch" };
/** A sum as its field reads it (iOS MTCoinUnit.read): coins as digits (fifteen at most), time and $TCM as a number with a point,
 *  so many units of the span or of a billion coins, rounded down to a whole coin. */
function readSum(typed, unit, per) {
  if (unit === "coins") { const d = typed.replace(/\D/g, "").slice(0, 15); return [d, Number(d) || 0]; }
  const places = unit === "time" ? 6 : 9, scale = unit === "time" ? per : 1e9;
  let whole = "", fraction = "", pointed = false;
  for (const c of typed) {
    if (/\d/.test(c)) { if (pointed) { if (fraction.length < places) fraction += c; } else if (whole.length < 15) whole += c; }
    else if ((c === "." || c === ",") && !pointed) pointed = true;
  }
  const coins = Math.floor(Number(`${whole || "0"}.${fraction || "0"}`) * scale);
  return [whole + (pointed ? "." + fraction : ""), coins <= 999999999999999 ? coins : 0];
}
/** A sum the page wrote itself, in the unit chosen (iOS MTCoinUnit.written): six places of a span, nine of a $TCM, trimmed. */
function writeSum(coins, unit, per) {
  if (!coins) return "";
  if (unit === "coins") return String(coins);
  const v = coins / (unit === "time" ? per : 1e9), places = unit === "time" ? 6 : 9;
  return String(Math.floor(v * 10 ** places) / 10 ** places);
}

/** THE PICK AND THE FLIGHT (iOS MTPickMark): the platform's circle, its filled check in the system's blue; while the coins go the
 *  system's ring turns in its place, and it closes into the check when the coin letter stands in the chat. */
function PickMark({ picked, going }) {
  if (going === false) return <span className="pick-ring" aria-hidden="true" />;
  if (picked || going === true) return <CheckFill size={26} />;
  return <svg width="26" height="26" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10.5" fill="none" stroke="rgba(235,235,245,0.3)" strokeWidth="1.5" /></svg>;
}

/** SEND COINS TO PEOPLE (iOS MTCoinSendSheet, the author's words 03.10 and 05-11.10.2026): the pairs' chats in the chats tab's own
 *  rows, as many as the person picks, each with its own sum typed beside it -- in time, coins or $TCM -- or a box of π chosen for
 *  every pick; «Level the top 13» raises the poorest of the people who told their balance toward the richest; every pick gets the
 *  pair's own transfer (a record on my chain, then a letter in the chat). Weighed by the Available; a short one refuses before
 *  anything leaves; one recipient's chat opens after, many close the page. */
function SendSheet({ available, onClose, onOpenChat }) {
  const [chats, setChats] = useState([]);
  const [told, setTold] = useState({});
  const [picked, setPicked] = useState(new Set());
  const [amounts, setAmounts] = useState({});
  const [typed, setTyped] = useState({});
  const [unit, setUnit] = useState("coins");
  const [span, setSpan] = useState(3600);
  const [chosen, setChosen] = useState(1);
  const [going, setGoing] = useState({});
  const [ask, setAsk] = useState(null);
  // TO ONESELF ON ANOTHER ACCOUNT (iOS «My other accounts», the author's word 11.10.2026 17:13 MSK, No.62): every person waiting on
  // this computer's shelf, by the face and the name the drawer shows; a pick's key is «seat:<id>», never a chat's name. A transfer
  // between two accounts of one owner links them publicly and forever: the person reads it and agrees, once a sheet (No.65).
  const [seats, setSeats] = useState([]);
  const [linkAgreed, setLinkAgreed] = useState(false);
  const fields = useRef({});
  useEffect(() => {
    invoke("seats_state").then((s) => setSeats(s?.parked || [])).catch(() => {});
    invoke("chats").then((r) => setChats((r || []).filter((x) => !x.group && !x.blocked && x.ref !== SAVED))).catch(() => {});
    invoke("coin_badges").then((b) => setTold(Object.fromEntries(Object.entries(b?.told || {}).filter(([, x]) => x.coins != null).map(([c, x]) => [c, x.coins])))).catch(() => {});
  }, []);
  const coins = (r) => Number(amounts[r] || 0);
  const total = [...picked].reduce((n, r) => n + coins(r), 0);
  const ready = picked.size > 0 && [...picked].every((r) => coins(r) > 0);
  const sumOf = (c) => (unit === "time" ? timeOf(c) : unit === "coins" ? count(c) : `${montana(c)} $TCM`);
  const type = (r, text) => {
    const [shown, c] = readSum(text, unit, span);
    setTyped((x) => ({ ...x, [r]: shown }));
    setAmounts((x) => ({ ...x, [r]: c > 0 ? c : 0 }));
    setPicked((p) => { const n = new Set(p); if (c > 0) n.add(r); else n.delete(r); return n; });
  };
  const toggle = (r) => {
    setTyped((x) => ({ ...x, [r]: undefined }));
    setPicked((p) => {
      const n = new Set(p);
      if (n.has(r)) { n.delete(r); setAmounts((x) => ({ ...x, [r]: 0 })); }
      else { n.add(r); if (!coins(r)) setAmounts((x) => ({ ...x, [r]: chosen })); setTimeout(() => fields.current[r]?.focus(), 0); }
      return n;
    });
  };
  const choose = (n) => {
    setChosen(n);
    setAmounts((x) => { const y = { ...x }; for (const r of picked) y[r] = n; return y; });
    setTyped((x) => { const y = { ...x }; for (const r of picked) y[r] = undefined; return y; });
  };
  // THE TOP THIRTEEN HERE (iOS topThirteen) and the levelling (iOS levelPlan): the poorest raised first, every one to one level,
  // toward the richest and as far as the Available reaches
  const top = chats.filter((c) => told[c.ref] != null).map((c) => ({ ref: c.ref, coins: told[c.ref] })).sort((a, b) => b.coins - a.coins).slice(0, 13);
  const plan = () => {
    if (!top.length) return { level: 0, gifts: [], total: 0 };
    const fill = (l) => top.reduce((n, p) => n + Math.max(0, l - p.coins), 0);
    let low = top[top.length - 1].coins, high = top[0].coins;
    while (low < high) { const mid = low + Math.floor((high - low + 1) / 2); if (fill(mid) <= available) low = mid; else high = mid - 1; }
    return { level: low, gifts: top.filter((p) => low - p.coins > 0).map((p) => ({ ref: p.ref, give: low - p.coins })), total: fill(low) };
  };
  const level = () => {
    const p = plan();
    setTyped({});
    setAmounts((x) => { const y = { ...x }; for (const q of top) y[q.ref] = p.gifts.find((g) => g.ref === q.ref)?.give || 0; return y; });
    setPicked((s) => { const n = new Set(s); for (const q of top) { if (p.gifts.some((g) => g.ref === q.ref)) n.add(q.ref); else n.delete(q.ref); } return n; });
    setAsk(null);
  };
  const send = async (agreed = linkAgreed) => {
    const to = chats.filter((c) => picked.has(c.ref) && coins(c.ref) > 0);
    const toSeats = seats.filter((s) => picked.has(`seat:${s.id}`) && coins(`seat:${s.id}`) > 0);
    if ((!to.length && !toSeats.length) || total > available) { setAsk("short"); return; }
    if (toSeats.length && !agreed) { setAsk("link"); return; }
    setGoing(Object.fromEntries([...to.map((c) => [c.ref, false]), ...toSeats.map((s) => [`seat:${s.id}`, false])]));
    const went = [];
    for (const s of toSeats) {
      const key = `seat:${s.id}`;
      const out = await invoke("coin_send_own", { seat: s.id, coins: coins(key) }).catch(() => "pending");
      invoke("trace", { line: `coin send own out=${out.split(":")[0]} coins=${coins(key)}` }).catch(() => {});
      const ok = out.startsWith("sent:");
      setGoing((g) => ({ ...g, [key]: ok ? true : undefined }));
      if (ok) went.push({ ref: out.split("|")[1] });
    }
    for (const c of to) {
      const out = await invoke("coin_send", { chat: c.ref, coins: coins(c.ref) }).catch(() => "pending");
      invoke("trace", { line: `coin send out=${out.split(":")[0]} coins=${coins(c.ref)}` }).catch(() => {});
      // the record stands on my chain: the letter went; a record no node took yet waits for the network (the chain's walk sends it)
      const ok = out.startsWith("sent:");
      setGoing((g) => ({ ...g, [c.ref]: ok ? true : undefined }));
      if (ok) went.push(c);
    }
    // NOTHING WENT: the sheet says so as iOS does (send: guard !went.isEmpty else { ask = .short })
    if (!went.length) { setGoing({}); setAsk("short"); return; }
    await new Promise((r) => setTimeout(r, 450));   // the closed rings stand a breath, then the page leaves by itself
    if (went.length === 1 && onOpenChat) onOpenChat(went[0].ref); else onClose();
  };
  const p = ask === "level" ? plan() : null;
  const askWords = {
    short: ["Not enough coins", t("Your coin balance is lower than this.")],
    noBalances: ["No balances to level", t("None of your contacts shows their coins yet. A contact's balance appears here once they turn on Show my coins in their wallet.")],
    level: ["Level the top 13?", p && p.gifts.length
      ? t("%lld of your top 13 receive coins, %@ in all, each raised to %@ coins; the richest receive none. The amounts are written beside their names, and nothing leaves until you send them.")
        .replace("%lld", p.gifts.length).replace("%@", count(p.total)).replace("%@", count(p.level))
      : t("Your top 13 already stand level, or your balance reaches none of them: nothing changes.")],
    link: ["Link your accounts forever?", t("A transfer between two of your accounts links them publicly and forever: anyone who reads the TimeChain sees that both belong to one owner. Coins you send to other people never link your accounts.")],
  }[ask];
  return (
    <Page title={t("Send")} subtitle={t("Available %@").replace("%@", count(available))}
          onClose={onClose}
          right={<button className="glass-mark send-mark" onClick={() => send()} disabled={!ready || Object.keys(going).length > 0} aria-label={t("Send")}>
                   <img src={timeSend} alt="" className="time-send" /></button>}>
      <Section>
        <div className="set-row send-units">
          <div className="segmented" role="radiogroup" aria-label={t("Amount")}>
            {[["time", t("Time")], ["coins", t("Coins")], ["tcm", "$TCM"]].map(([k, w]) => (
              <button key={k} role="radio" aria-checked={unit === k} className={unit === k ? "on" : ""} onClick={() => { setUnit(k); setTyped({}); }}>{w}</button>
            ))}
          </div>
          {unit === "time" && (
            <select className="span-menu" aria-label={t("Unit of time")} value={span} onChange={(e) => { setSpan(Number(e.target.value)); setTyped({}); }}>
              {SPANS.map(([k, s]) => <option key={k} value={s}>{t(SPAN_TITLE[k])}</option>)}
            </select>
          )}
        </div>
        {/* THE BOXES OF π AS THE AMOUNTS SENT (iOS): a box chosen stands beside every chat picked */}
        <div className="coin-boxes send-boxes">
          {PI_LEVELS.map((n) => (
            <button key={n} className={chosen === n ? "on" : ""} disabled={available < n} onClick={() => choose(n)}>{shortCoins(n)}</button>
          ))}
        </div>
        <button className="set-row level-top" onClick={() => setAsk(top.length ? "level" : "noBalances")}>
          <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 20V14M10 20V10M16 20V6M22 20H2" stroke="var(--blue)" strokeWidth="2" strokeLinecap="round" fill="none" /></svg>
          <span className="row-title blue">{t("Level the top 13")}</span>
        </button>
        {picked.size > 0 && <div className="set-row" role="group" aria-label={`${t("Total")}: ${sumOf(total)}`}><span className="row-title">{t("Total")}</span><span className="row-value digits">{sumOf(total)}</span></div>}
      </Section>
      {seats.length > 0 && (
        <Section head={t("My other accounts")} foot={t("A transfer to your own account links the two accounts publicly forever.")}>
          {seats.map((s) => {
            const key = `seat:${s.id}`, name = s.name || "Montana";
            return (
              <div key={key} className="set-row send-row">
                <button className="send-who" onClick={() => toggle(key)} aria-label={name}>
                  <div className="self-face" style={{ width: 40, height: 40, fontSize: 17, background: "#000" }}>
                    {s.face ? <img src={`data:image/jpeg;base64,${s.face}`} alt="" className="face-photo" /> : (s.glyph || "M").toUpperCase()}
                  </div>
                  <span className="row-title">{name}</span>
                </button>
                <input ref={(e) => { fields.current[key] = e; }} className="set-field send-field digits" placeholder="0" aria-label={`${t("Amount")}: ${name}`}
                       inputMode={unit === "coins" ? "numeric" : "decimal"} value={typed[key] ?? writeSum(coins(key), unit, span)} onChange={(e) => type(key, e.target.value)} />
                <button className="pick-button" role="checkbox" aria-checked={picked.has(key)} aria-label={`${t("Select")}: ${name}`} onClick={() => toggle(key)}>
                  <PickMark picked={picked.has(key)} going={going[key]} />
                </button>
              </div>
            );
          })}
        </Section>
      )}
      <Section head={t("Choose chats")}>
        {chats.length === 0 && <div className="set-row"><span className="row-title row-caption">{t("No chats yet")}</span></div>}
        {chats.map((c) => (
          <div key={c.ref} className="set-row send-row">
            <button className="send-who" onClick={() => toggle(c.ref)} aria-label={chatName(c.name)}>
              <Face chat={c.ref} version={c.face} size={40} /><span className="row-title">{chatName(c.name)}</span>
            </button>
            <input ref={(e) => { fields.current[c.ref] = e; }} className="set-field send-field digits" placeholder="0" aria-label={`${t("Amount")}: ${chatName(c.name)}`}
                   inputMode={unit === "coins" ? "numeric" : "decimal"} value={typed[c.ref] ?? writeSum(coins(c.ref), unit, span)} onChange={(e) => type(c.ref, e.target.value)} />
            <button className="pick-button" role="checkbox" aria-checked={picked.has(c.ref)} aria-label={`${t("Select")}: ${chatName(c.name)}`} onClick={() => toggle(c.ref)}>
              <PickMark picked={picked.has(c.ref)} going={going[c.ref]} />
            </button>
          </div>
        ))}
      </Section>
      {askWords && (
        <div className="alert-shade" role="alertdialog" aria-label={t(askWords[0])}>
          <div className="alert">
            <b>{t(askWords[0])}</b>
            <p>{askWords[1]}</p>
            <div className={"alert-keys" + (ask === "link" && t("Send and link").length > 12 ? " stacked" : "")}>
              {ask === "level" && p?.gifts.length > 0 && <button onClick={level}>{t("Level them")}</button>}
              {ask === "link" && <button onClick={() => { setLinkAgreed(true); setAsk(null); send(true); }}>{t("Send and link")}</button>}
              <button className="bold" onClick={() => setAsk(null)}>{t(ask === "level" || ask === "link" ? "Cancel" : "OK")}</button>
            </div>
          </div>
        </div>
      )}
    </Page>
  );
}

/** ONE COIN, ONE SECOND -- ALL THE TOP UP SAYS (iOS MTCoinTopUpSheet / MTCoinRules; the author's word 21.10.2026 17:3x MSK: «on the Top
 *  up button the information is old -- leave only 1 coin - 1 second, "Live here and now"»): only the core mints, by the seconds a
 *  person lives, so the sheet names the rule and nothing that would mint beside it. */
function TopUp({ onClose }) {
  return (
    <Page title={t("Top up")} onClose={onClose}>
      <Section>
        <div className="set-row"><span className="row-title rule-head">{t("1 coin — 1 second")}</span></div>
        <div className="set-row"><span className="row-title">{t("Live here and now")}</span></div>
      </Section>
    </Page>
  );
}

/** THE TIMECHAINS ON THE WALLET (iOS MTTimeChainRows): every source's chain with its length and the first letters of its head, and
 *  the seal when every link's seal holds from the genesis; a row opens the chain's own page (iOS MTTimeChainPage). */
const CHAIN_NAMES = { pi: "Levels of π", chess: "Coins from chess", pantheon: "Coins from the Pantheon", vpnwall: "Coins from the VPN Wall",
  vpnpay: "Paid for the VPN", timer: "Timer", chats: "Coins from chats", groups: "Coins from groups", channels: "Coins from channels",
  comments: "Coins for comments", wall: "Wall", received: "Coins received", spent: "Coins on reactions", sent: "Coins sent",
  calls: "Burned for calls", letters: "Burned for letters", system: "System chain", person: "Person", fabric: "Fabric of Time" };
/** The chats' and calls' chains of coins; every other source is the wallet's own (iOS MTTimeChainsPage.talk). */
const TALK = ["chats", "groups", "channels", "comments", "wall", "calls", "letters"];
function ChainRows({ heads, sources, onOpen }) {
  const shown = heads.filter((h) => sources.includes(h.source) && h.n > 0);
  return (
    <>
      {shown.map((h) => (
        <button key={h.source} className="set-row" onClick={() => onOpen(h.source)} aria-label={`${t(CHAIN_NAMES[h.source] || h.source)}: ${h.n} · ${h.hash.slice(0, 8)} ${h.whole ? "✓" : "✗"}`}>
          <span className="row-title">{t(CHAIN_NAMES[h.source] || h.source)}</span>
          <span className="row-value chain-foot">{h.n} · {h.hash.slice(0, 8)} <Seal whole={h.whole} /></span>
          <Glyph name="chevronRight" size={13} color="var(--gray)" />
        </button>
      ))}
    </>
  );
}

/** The platform's seal (SF checkmark.seal.fill green / xmark.seal.fill red): every seal of a chain holds from its genesis, or not. */
function Seal({ whole, size = 16 }) {
  const c = whole ? "var(--green)" : "var(--red)";
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" className="seal">
      <path d="M12 1.5l2.3 1.9 3-.3 1 2.8 2.7 1.4-.6 2.9 1.6 2.6-1.9 2.3.3 3-2.8 1-1.4 2.7-2.9-.6L12 22.5l-2.3-1.9-3 .3-1-2.8-2.7-1.4.6-2.9L2 11.2l1.9-2.3-.3-3 2.8-1L7.8 2.2l2.9.6z" fill={c} />
      {whole ? <path d="M7.6 12.2l3 3 5.8-6.1" fill="none" stroke="#fff" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
             : <path d="M8.6 8.6l6.8 6.8M15.4 8.6l-6.8 6.8" stroke="#fff" strokeWidth="2.2" strokeLinecap="round" />}
    </svg>
  );
}

/** The sections' own marks (iOS Label(systemImage:) in a section's header): 1.circle, 2.circle, 3.circle, the two bubbles, the globe. */
function HeadMark({ n, talk }) {
  return (
    <svg width="17" height="17" viewBox="0 0 24 24" aria-hidden="true" className="head-mark">
      {talk ? <><path d="M3 5.5h11a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2H8l-3.5 3v-3H3a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2z" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round" />
                <path d="M18 9.5h3a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-1v2.5L17 17.5h-4a2 2 0 0 1-2-1.5" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round" /></>
            : <><circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" strokeWidth="1.7" /><text x="12" y="16.3" fontSize="12" fontWeight="600" textAnchor="middle" fill="currentColor">{n}</text></>}
    </svg>
  );
}
const head = (word, mark) => <span className="sect-label">{mark}{t(word)}</span>;

/** THE TOP THIRTEEN (iOS MTCoinTop13, the author's words 03.10 and 04.10.2026): the one table the nodes keep, the same on every
 *  machine -- my row wearing my own face, every other the letter of the name its owner shows -- or, before a node that keeps it
 *  answered, the person among the pairs who told their balance, with the faces and names of the chats. */
function Top13({ st, person }) {
  // THE TOP OPENS OPEN (iOS MTWalletPage: topOpen = true); what showing does is said under it by the person's own switch
  const [open, setOpen] = useState(true);
  const [chats, setChats] = useState([]);
  const [badges, setBadges] = useState(null);
  const [shown, setShown] = useState(true);
  useEffect(() => { invoke("coins_shown", {}).then(setShown).catch(() => {}); }, []);
  useEffect(() => {
    if (!open) return;
    invoke("chats").then((rows) => setChats((rows || []).filter((r) => !r.group && r.ref !== SAVED))).catch(() => {});
    invoke("coin_badges").then(setBadges).catch(() => {});
  }, [open, st.top?.answered]);
  const top = st.top || {};
  const name = (n) => (n ? Array.from(n.trim())[0]?.toUpperCase() || "" : "");
  // a row as iOS lays it: the place headline in the secondary colour, the face of 40, the name, the coins headline in the primary
  const line = (i, face, who, coins, unnamed) => (
    <div key={i} className="set-row top-row" role="group" aria-label={`${i + 1}. ${who}: ${count(coins)}`}>
      <span className="top-place digits">{i + 1}</span>{face}<span className={"row-title" + (unnamed ? " row-caption" : "")}>{who}</span>
      <span className="top-coins digits">{count(coins)}</span>
    </div>
  );
  let rows;
  if (top.answered) {
    rows = top.rows.slice(0, 13).map((r, i) => r.id === top.mine
      ? line(i, <SelfFace name={person?.name} version={person?.face} size={40} />, chatName(person?.name), r.coins)
      : line(i, <span className="top-face">{name(r.name)}</span>, r.name ? r.name : t("No name"), r.coins, !r.name));
  } else {
    const told = Object.entries(badges?.told || {}).filter(([c, x]) => x.coins != null && chats.some((r) => r.ref === c))
      .map(([c, x]) => ({ c, coins: x.coins }));
    // my place by what my chain holds for me (iOS board.rating(mine: split.available))
    const all = [...told, { c: "", coins: st.available, mine: true }].sort((a, b) => b.coins - a.coins).slice(0, 13);
    rows = all.map((p, i) => {
      const chat = chats.find((r) => r.ref === p.c);
      return p.mine ? line(i, <SelfFace name={person?.name} version={person?.face} size={40} />, chatName(person?.name), p.coins)
        : line(i, <Face chat={p.c} version={chat?.face} size={40} />, chatName(chat?.name), p.coins);
    });
  }
  return (
    // what showing does is said where the table stands (iOS: the footer follows «Show my coins», Privacy)
    <Section foot={t(shown ? "Your name and coins are shown to everyone in the Montana top. Privacy settings turn it off." : "You are not in the Montana top. Privacy settings turn it on.")}>
      <button className="set-row" aria-expanded={open} onClick={() => setOpen(!open)}><span className="row-title"><b>{t("Top 13")}</b></span>
        <span className={"disclosure" + (open ? " open" : "")} aria-hidden="true"><Glyph name="chevronRight" size={14} color="var(--blue)" /></span></button>
      {open && rows}
    </Section>
  );
}

/** Why the protocol core says nothing of the wallet, in the person's language (iOS MTWalletCore.said). */
export const CORE_SAID = { unavailable: "The protocol core is unavailable on this device.", device: "The protocol device has not joined the network.",
  person: "The core has not opened your wallet.", refused: "The core could not confirm the wallet state. Try refreshing." };
/** THE CORE'S WALLET (iOS MTTimeChainsPage, the observer's rows): the confirmed balance, the last confirmed window, the notes --
 *  or the core's own reason it says none. */
function CoreRows({ core }) {
  if (!core) return <div className="set-row"><span className="row-title">{t("Reading the wallet…")}</span></div>;
  if (core.absent) return <div className="set-row"><span className="row-title row-caption">{t(CORE_SAID[core.absent] || CORE_SAID.refused)}</span></div>;
  const w = core.ok;
  return (
    <>
      <div className="set-row" role="group" aria-label={`${t("Confirmed balance")}: ${w.balance}`}><span className="row-title">{t("Confirmed balance")}</span><span className="row-value mono">{w.balance}</span></div>
      {w.lastConfirmedWindow != null
        ? <div className="set-row" role="group" aria-label={`${t("Last confirmed window")}: ${w.lastConfirmedWindow}`}><span className="row-title">{t("Last confirmed window")}</span><span className="row-value mono">{w.lastConfirmedWindow}</span></div>
        : <div className="set-row"><span className="row-title row-caption">{t("No confirmed window yet")}</span></div>}
      <div className="set-row" role="group" aria-label={`${t("Wallet notes")}: ${w.notes}`}><span className="row-title">{t("Wallet notes")}</span><span className="row-value mono">{w.notes}</span></div>
    </>
  );
}

/** π as far as a level reveals it: 3, 3.1, 3.14 … (iOS MTPiLevels.revealed). */
const revealed = (place) => { const d = "3141592653589793238".slice(0, Math.max(0, place)); return d.length < 2 ? d : d[0] + "." + d.slice(1); };

/** THE TIMECHAIN PAGE (iOS MTTimeChainsPage): one seed is one person, and beside it the evidence of its time -- the Global Level
 *  (the lowest of the levels below), the chain of the person (its seconds on the network by the nodes' clock, its level, the time
 *  to the next), the wallet's level of π and its own chains, the chains of the chats and calls, and what an observer checks. */
function TimeChainsPage({ onOpen, onClose }) {
  const [c, setC] = useState(null);
  const [files, setFiles] = useState(0);
  useEffect(() => { invoke("chain_files").then(setFiles).catch(() => {}); }, []);
  useEffect(() => {
    const read = () => invoke("timechains", {}).then(setC).catch(() => {});
    read();
    const id = setInterval(read, 3000);
    return () => clearInterval(id);
  }, []);
  if (!c) return <Page title="TimeChain" onClose={onClose} back />;
  const p = c.person || {}, f = c.fabric || {}, own = Object.keys(CHAIN_NAMES).filter((s) => s !== "pi" && s !== "person" && s !== "fabric" && !TALK.includes(s));
  const from = p.level != null && p.level < 62 ? 2 ** p.level : null;
  // the values as iOS writes them: the text's own digits of one width (LabeledContent + .monospacedDigit())
  const row = (title, value, label) => (
    <div className="set-row" role="group" aria-label={label ?? `${t(title)}: ${value}`}><span className="row-title">{t(title)}</span><span className="row-value digits">{value}</span></div>
  );
  const links = (n, hash, src, label) => (
    <button className="set-row" onClick={() => onOpen(src)} aria-label={label ?? `${t("Chain links")}: ${n} · ${hash.slice(0, 8)}`}>
      <span className="row-title">{t("Chain links")}</span><span className="row-value chain-foot">{n} · {hash.slice(0, 8)}</span>
      <Glyph name="chevronRight" size={13} color="var(--gray)" />
    </button>
  );
  const genesis = "0".repeat(64);
  return (
    <Page title="TimeChain" onClose={onClose} back>
      <Section foot={t("The lowest of the three levels below.")}>
        <div className="set-row" role="group" aria-label={`${t("Global level")}: ${c.global}`}>
          <span className="row-title sect-label"><Glyph name="globe" size={20} color="var(--blue)" />{t("Global level")}</span>
          <span className="row-value global-level digits">{c.global}</span>
        </div>
      </Section>
      <Section head={head("Person", <HeadMark n={1} />)} foot={t("A second counts while the app is open on any of your devices and a node answers its coin exchange: every few seconds while TimeCoin stands open, at each exchange elsewhere. The node's second, never the computer's clock. Each level doubles the seconds of the one before. Shown only to you, published nowhere.")}>
        {row("Level", p.level ?? "—")}
        {row("Time online", timeOf(p.seconds || 0, false))}
        {from != null && (
          // THE NEXT LEVEL IN TIME (iOS): the words small and grey, the span beside them, the platform's bar the row's width under both
          <div className="set-row chain-next" role="group" aria-label={`${t("To the next level")}: ${timeOf(Math.max(0, 2 * from - p.seconds), false)}`}>
            <span className="chain-next-line"><span className="row-caption">{t("To the next level")}</span><span className="digits">{timeOf(Math.max(0, 2 * from - p.seconds), false)}</span></span>
            <progress max={from} value={Math.max(0, p.seconds - from)} />
          </div>
        )}
        {links(p.links ?? 0, p.head || genesis, "person")}
      </Section>
      <Section head={head("Wallet", <HeadMark n={2} />)} foot={t("Your balance reveals π: each level opens when the balance reaches the next amount — 3, 31, 314 …")}>
        {row("Level of π", `${c.pi} · π ${revealed(c.pi)}`)}
        <button className="set-row" onClick={() => onOpen("pi")}><span className="row-title">{t("Levels of π")}</span><Glyph name="chevronRight" size={13} color="var(--gray)" /></button>
        <ChainRows heads={c.heads || []} sources={own} onOpen={onOpen} />
      </Section>
      <Section head={head("Fabric of Time", <HeadMark n={3} />)} foot={t("The people you write to and call regularly, each weighed by the level their own time and wallet give them: the greatest number g for which at least g people you exchanged with — words, voice, video, photos, stickers, transfers, games or a call — in each of the last two weeks stand at level g or above. An exchange counts when both of you write: once a day each device signs that the other's word reached it and gives the signature to the other. Counted again whenever a signature comes or leaves the two weeks; through its first two weeks it stands at the lower of your two levels above. Your ceiling goes only to the people you write to, inside your conversation.")}>
        {row("Level", f.level ?? "—")}
        {f.graceDays != null && <div className="set-row" role="group" aria-label={t("Days until the first count: %@").replace("%@", f.graceDays)}><span className="row-title row-caption">{t("Days until the first count: %@").replace("%@", f.graceDays)}</span></div>}
        {row("Regular correspondents", f.regulars ?? 0)}
        {row("Signatures", f.testimonies ?? 0)}
        {row("Ceiling", f.ceiling ?? "—")}
        {links(f.links ?? 0, f.head || genesis, "fabric", `${t("Fabric of Time")} · ${t("Chain links")}: ${f.links ?? 0} · ${(f.head || genesis).slice(0, 8)}`)}
      </Section>
      <Section head={head("Chats and calls", <HeadMark talk />)} foot={t("The chains of the coins your chats, calls and comments minted and burned, and the chain of your wall's posts.")}>
        <ChainRows heads={c.heads || []} sources={TALK} onOpen={onOpen} />
      </Section>
      {/* THE EXPLORER (iOS: the public page that reads a transfer's record from the nodes and checks its signature) -- in the system's
          browser here */}
      <Section foot={t("Every transfer is a record on the nodes signed by its sender's seed. The Explorer reads it from the nodes and checks its signature; a transfer's link in the Wallet chains opens it there.")}>
        <button className="set-row accent" onClick={() => invoke("open_link", { url: EXPLORER }).catch(() => {})}>
          <span className="row-title sect-label blue"><Magnifier />{t("Explorer")}</span>
        </button>
      </Section>
      <Section head={t("For an observer")} foot={t("Every link is sealed by SHA-256 over its number, moment, kind, amount, name and the seal before it; the level of the person is bit_length(seconds) − 1 (Canon). Shared chains can be checked link by link anywhere.")}>
        <div className="set-row" role="group" aria-label={`${t("Frozen vectors")}: ${c.vectors ? "✓" : "✗"}`}><span className="row-title">{t("Frozen vectors")}</span><Seal whole={c.vectors} size={20} /></div>
        {c.top?.answered && row("People who show their coins", c.top.rows.length)}
        {c.top?.answered && row("Coins they show", count(c.top.rows.reduce((n, r) => n + r.coins, 0)))}
        {/* the node of the protocol core and what the core says of the wallet (iOS MTNetworkNode, MTWalletCore) */}
        {row("Genesis machines reached", `${c.node?.reached ?? 0} / ${c.node?.of ?? 4}`)}
        <CoreRows core={c.core} />
        {files > 0 && (
          // the chains' own files through Windows' own «Поделиться» (iOS MTShare of the wallet-*.jsonl)
          <button className="set-row accent" onClick={() => invoke("share_chains").catch(() => {})}>
            <span className="row-title sect-label blue"><Glyph name="share" size={18} color="var(--blue)" />{t("Share the chains")}</span>
          </button>
        )}
      </Section>
    </Page>
  );
}
/** A TIMECHAIN, LINK BY LINK (iOS MTTimeChainPage): every link of one source's chain, the newest first -- its number, its moment,
 *  the coins (a level's link names its level), its seal and the seal it stands on, the move's own name -- and whether every seal
 *  holds from the genesis. A transfer's link opens its record in the Explorer, and its menu copies or shares the link. */
function ChainPage({ source, onClose }) {
  const [c, setC] = useState(null);
  const [menu, setMenu] = useState(null);   // {url, x, y}
  useEffect(() => { invoke("timechains", { source }).then(setC).catch(() => {}); }, [source]);
  const plus = (k) => ["earn", "receive", "keep"].includes(k);
  const when = (ms) => new Date(ms).toLocaleString(locale, { day: "numeric", month: "short", year: "numeric", hour: "numeric", minute: "2-digit", second: "2-digit" });
  const urlOf = (ref) => { const id = ref.startsWith("tx:") ? ref.slice(3) : ""; return /^[0-9a-f]{64}$/i.test(id) ? TX_LINK + id : null; };
  return (
    <Page title={t(CHAIN_NAMES[source] || source)} onClose={onClose} back>
      {c && (
        <Section>
          <div className="set-row" aria-label={`${c.head.n} · ${c.head.hash.slice(0, 16)} ${c.head.whole ? "✓" : "✗"}`}>
            <span className="row-title chain-foot">{c.head.n} · {c.head.hash.slice(0, 16)}</span><Seal whole={c.head.whole} size={20} />
          </div>
          {c.links.map((l) => {
            const url = urlOf(l.ref);
            const body = (<>
              <span className="row-title chain-words">
                <span className="chain-n digits">#{l.n}</span>
                <span className="chain-at">{when(l.at)}</span>
                <span className="chain-seal mono">{l.hash.slice(0, 16)} ← {l.prev.slice(0, 16)}</span>
                <span className="chain-ref mono">{l.ref}</span>
              </span>
              {l.k === "level" ? <span className="row-value chain-coins digits">{t("Level %lld").replace("%lld", l.c)}</span>
                : l.c > 0 && <span className="row-value chain-coins digits">{(plus(l.k) ? "+" : "−") + count(l.c)}<span className="chain-time">{timeOf(l.c, false)}</span></span>}
            </>);
            return url
              ? <button key={l.n} className="set-row chain-link" aria-label={`#${l.n}`} onClick={() => invoke("open_link", { url }).catch(() => {})}
                        onContextMenu={(e) => { e.preventDefault(); setMenu({ url, x: e.clientX, y: e.clientY }); }}>{body}</button>
              : <div key={l.n} className="set-row chain-link" role="group" aria-label={`#${l.n}`}>{body}</div>;
          })}
        </Section>
      )}
      {menu && (
        <div className="menu-shade" onClick={() => setMenu(null)} onContextMenu={(e) => { e.preventDefault(); setMenu(null); }}>
          <div className="letter-menu" style={{ left: Math.min(menu.x, window.innerWidth - 300), top: Math.min(menu.y, window.innerHeight - 200) }} onClick={(e) => e.stopPropagation()} role="menu">
            <div className="menu-rows">
              <button className="menu-row" role="menuitem" onClick={() => { setMenu(null); invoke("open_link", { url: menu.url }).catch(() => {}); }}><span>{t("Open in Explorer")}</span><Magnifier /></button>
              <button className="menu-row" role="menuitem" onClick={() => { setMenu(null); invoke("copy_text", { text: menu.url }).catch(() => {}); }}><span>{t("Copy confirmation link")}</span><Glyph name="copy" size={18} /></button>
              <button className="menu-row" role="menuitem" onClick={() => { setMenu(null); invoke("share_text", { title: "Montana", text: menu.url, link: menu.url }).catch(() => {}); }}><span>{t("Share confirmation link")}</span><Glyph name="share" size={18} /></button>
            </div>
          </div>
        </div>
      )}
    </Page>
  );
}

/** SF magnifyingglass, drawn at its shape. */
function Magnifier({ size = 18 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="10.5" cy="10.5" r="6.5" fill="none" stroke="currentColor" strokeWidth="2" /><path d="M15.5 15.5L21 21" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" />
    </svg>
  );
}

/** AUTO-REACTIONS (iOS MTAutoReactPage, the author's word 06.10.2026): the person's chats with a pair, each with the coins its every
 *  new letter is paid, typed beside the name; an emptied field lets the person go. What is typed stands at once. */
export function AutoReacts({ onClose }) {
  const [rows, setRows] = useState([]);
  const [amounts, setAmounts] = useState({});
  useEffect(() => {
    invoke("chats").then((all) => setRows(all.filter((r) => !r.group && !r.blocked && r.ref !== SAVED))).catch(() => {});
    invoke("auto_react", {}).then((rules) => setAmounts(Object.fromEntries(Object.entries(rules || {}).map(([k, v]) => [k, String(v.c)])))).catch(() => {});
  }, []);
  const type = (chat, typed) => {
    const digits = typed.replace(/\D/g, "").slice(0, 12);
    setAmounts((a) => ({ ...a, [chat]: digits }));
    invoke("auto_react", { chat, coins: Number(digits || 0) }).catch(() => {});
  };
  return (
    <Page title={t("Auto-reactions")} onClose={onClose} back>
      <Section head={t("Coins on each new letter")} foot={t("Paid by itself as a reaction on every letter the person writes from now on, while your coins last.")}>
        {rows.length === 0 && <div className="post-note">{t("No chats yet")}</div>}
        {rows.map((r) => (
          <label key={r.ref} className="set-row send-row">
            <span className="send-who"><Face chat={r.ref} version={r.face} size={40} /><span className="row-title">{chatName(r.name)}</span></span>
            <input className="set-field auto-coins digits" inputMode="numeric" placeholder="0" value={amounts[r.ref] || ""} aria-label={chatName(r.name)}
                   onChange={(e) => type(r.ref, e.target.value)} />
          </label>
        ))}
      </Section>
    </Page>
  );
}

const longWhen = (at, seconds = true) => new Date(at * 1000).toLocaleString(locale, { day: "numeric", month: "short", year: "numeric", hour: "numeric", minute: "2-digit", ...(seconds ? { second: "2-digit" } : {}) });
const pair = (title, value, cls = "") => (
  <div className="set-row" role="group" aria-label={`${t(title)}: ${value}`}><span className="row-title">{t(title)}</span><span className={"row-value digits " + cls}>{value}</span></div>
);
const sealRow = (title, hash) => (
  <div className="set-row seal-row" role="group" aria-label={`${t(title)}: ${hash}`}><span className="row-title">{t(title)}</span><span className="seal-hash mono">{hash}</span></div>
);

/** ONE COIN MOVE ON ITS OWN PAGE (iOS MTCoinMovePage): the coins, their time, to whom or from whom, the moment; the link of the
 *  person's TimeChain that holds it, with its seal and the seal before it; and the system chain's link when the system restored it. */
function MovePage({ line, onClose }) {
  const mine = line.signed < 0;
  const [link, setLink] = useState(null);
  const [restored, setRestored] = useState(null);
  useEffect(() => {
    invoke("timechains", { source: line.src }).then((c) => setLink((c?.links || []).find((l) => l.ref === line.ref) || null)).catch(() => {});
    invoke("timechains", { source: "system" }).then((c) => setRestored((c?.links || []).find((l) => l.ref === "restore:" + line.ref) || null)).catch(() => {});
  }, [line.ref, line.src]);
  return (
    <Page title={t("Transaction")} onClose={onClose} back>
      <Section head={t(mine ? "Coins sent" : "Coins received")}>
        {pair("Amount", (mine ? "−" : "+") + count(Math.abs(line.signed)), mine ? "" : "green")}
        {pair("Time", timeOf(Math.abs(line.signed)))}
        {pair(mine ? "To" : "From", line.title)}
        {pair("Date", longWhen(line.at))}
      </Section>
      {link && (
        <Section head={t("Local TimeChain")}>
          {pair("Chain link", `#${link.n}`)}
          {sealRow("Seal", link.hash)}
          {sealRow("Previous seal", link.prev)}
        </Section>
      )}
      {restored && (
        <Section head={t("System chain")}>
          {pair("Restored by the system", `#${restored.n}`)}
          {sealRow("Seal", restored.hash)}
        </Section>
      )}
    </Page>
  );
}

/** AN OPERATION'S OWN CARD (iOS MTHistoryCard): what it was, with whom, how many coins and when; a day's minting says how many moves
 *  it folds; the person's own coin key's whole chain opens in the Explorer. */
function OperationCard({ line, onClose }) {
  const [key, setKey] = useState(null);
  useEffect(() => { invoke("coin_key").then(setKey).catch(() => {}); }, []);
  return (
    <Page title={t("Operation")} onClose={onClose} back>
      <Section>
        {pair("Amount", (line.signed > 0 ? "+" : "") + count(line.signed))}
        {pair("Time", timeOf(line.signed, false))}
        {pair("Kind", line.title)}
        {pair("Category", line.category)}
        {pair("When", longWhen(line.at, false))}
        {line.count > 1 && pair("Operations", String(line.count))}
      </Section>
      {key && (
        <Section foot={t("Your coin key's whole chain, checked in the Explorer.")}>
          <button className="set-row accent" onClick={() => invoke("open_link", { url: KEY_LINK + key }).catch(() => {})}>
            <span className="row-title sect-label blue"><Magnifier />{t("Open in Explorer")}</span>
          </button>
        </Section>
      )}
    </Page>
  );
}

/** A move's sign (iOS MTCoinEntry.signed). */
const signedOf = (m) => (m.k === "earn" || m.k === "receive" ? m.c : -m.c);
/** THE ONE FOLD OF THE BOOK (iOS MTCoinHistory.fold): day after day, newest first; a day's minting one line, a day's small expenses
 *  (a burn or a spend of at most thirteen coins, a call's seconds aside) one line of each source and kind; every other move its own
 *  line -- who it was with, its category, its moment. */
export function foldHistory(moves) {
  const days = new Map();
  const dayOf = (at) => { const d = new Date(at * 1000); return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime(); };
  const add = (day, line) => { if (!days.has(day)) days.set(day, []); days.get(day).push(line); };
  const minted = new Map(), smalls = new Map();
  for (const m of moves) {
    const day = dayOf(m.at), name = t(CHAIN_NAMES[m.src] || m.src);
    if (m.k === "earn") {
      const had = minted.get(day) || { sum: 0, count: 0, at: 0 };
      minted.set(day, { sum: had.sum + m.c, count: had.count + 1, at: Math.max(had.at, m.at) });
      continue;
    }
    if ((m.k === "spend" || m.k === "burn") && m.src !== "calls" && m.c <= 13) {
      const key = `${day}|${m.src}|${m.k}`, had = smalls.get(key) || { sum: 0, count: 0, at: 0, day, src: m.src, k: m.k };
      smalls.set(key, { ...had, sum: had.sum + m.c, count: had.count + 1, at: Math.max(had.at, m.at) });
      continue;
    }
    const tx = m.ref.startsWith("tx:") && m.ref.length === 67 ? m.ref.slice(3) : null;
    add(day, { id: m.k + m.ref, at: m.at, signed: signedOf(m), title: m.who ? chatName(m.who) : name, category: name, k: m.k, tx, count: 1, src: m.src, ref: m.ref });
  }
  for (const [day, x] of minted) add(day, { id: `minted:${day}`, at: x.at, signed: x.sum, title: t("Minted"), category: t("Minting of the day"), k: "earn", count: x.count });
  for (const x of smalls.values()) add(x.day, { id: `small:${x.k}:${x.src}:${x.day}`, at: x.at, signed: -x.sum, title: t(CHAIN_NAMES[x.src] || x.src),
                                                category: t(x.k === "burn" ? "Burning of the day" : "Spending of the day"), k: x.k, count: x.count });
  return [...days.entries()].sort((a, b) => b[0] - a[0])
    .map(([day, lines]) => ({ day, lines: lines.sort((a, b) => b.at - a.at), sum: lines.reduce((n, l) => n + l.signed, 0) }));
}
/** The glyph of a move's kind (iOS MTCoinHistory.glyph): sparkles, the arrows in and out, the hand, the flame. */
export const KIND_GLYPH = { earn: "✦", receive: "↙", send: "↗", spend: "👍", burn: "🔥" };
/** The kind's own glyph in the thin material's circle of 36 (iOS MTHistoryRow: sparkles, arrow.down.left, arrow.up.right,
 *  hand.thumbsup, flame), drawn at its shape. */
function KindGlyph({ k }) {
  const p = { strokeWidth: 1.8, fill: "none", stroke: "currentColor", strokeLinecap: "round", strokeLinejoin: "round" };
  const d = {
    earn: <><path d="M10 3l1.6 4.4L16 9l-4.4 1.6L10 15l-1.6-4.4L4 9l4.4-1.6z" {...p} /><path d="M18 13l.8 2.2 2.2.8-2.2.8L18 19l-.8-2.2-2.2-.8 2.2-.8z" {...p} /><path d="M17.5 3.5l.5 1.5 1.5.5-1.5.5-.5 1.5-.5-1.5-1.5-.5 1.5-.5z" {...p} /></>,
    receive: <path d="M17 7L7 17M15 17H7V9" {...p} strokeWidth="2" />,
    send: <path d="M7 17L17 7M9 7h8v8" {...p} strokeWidth="2" />,
    spend: <><path d="M7 11v9H4v-9z" {...p} /><path d="M7 11l4-7c1.4 0 2.3 1.1 2 2.5L12.5 9H18a2 2 0 0 1 2 2.3l-1.2 6.5A2.6 2.6 0 0 1 16.3 20H7" {...p} /></>,
    burn: <path d="M12 3c.5 3-3 5-3 9a3 3 0 0 0 6 0c0-1.2-.5-2-1-2.8 2.4 1 4 3.4 4 6.1A6 6 0 0 1 6 15.5C6 10 12 8 12 3z" {...p} />,
  }[k];
  return (
    <span className="history-glyph" aria-hidden="true">
      {d ? <svg width="20" height="20" viewBox="0 0 24 24">{d}</svg> : "•"}
    </span>
  );
}

/** THE HISTORY OF OPERATIONS IN A BANK'S FORMAT (iOS MTCoinHistoryPage, the author's words 12.10.2026): All, Spending or Income,
 *  a search by contacts, then day after day, newest first, each day with its own sum; a page of lines at a time that grows as it
 *  is read; a transfer opens its record in the Explorer. */
function History({ onClose }) {
  const [moves, setMoves] = useState(null);
  const [flow, setFlow] = useState("all");
  const [query, setQuery] = useState("");
  const [limit, setLimit] = useState(120);
  const [opened, setOpened] = useState(null);   // a line's own page: {move} the transaction, {card} the operation
  const end = useRef(null);
  useEffect(() => {
    const read = () => invoke("coin_moves_all").then(setMoves).catch(() => setMoves([]));
    read();
    const id = setInterval(read, 1500);   // the book's moves fold again, at most one fold a second and a half (iOS watch)
    return () => clearInterval(id);
  }, []);
  const days = moves ? foldHistory(moves) : [];
  const holds = (s) => flow === "all" || (flow === "spending" ? s < 0 : s > 0);
  const shown = [];
  let n = 0, more = false;
  for (const d of days) {
    const lines = d.lines.filter((l) => holds(l.signed) && (!query || l.title.toLowerCase().includes(query.toLowerCase())));
    if (!lines.length) continue;
    if (n >= limit) { more = true; break; }
    const cut = lines.slice(0, limit - n);
    shown.push({ ...d, lines: cut, sum: flow === "all" && !query ? d.sum : lines.reduce((s, l) => s + l.signed, 0) });
    n += cut.length;
    if (cut.length < lines.length) { more = true; break; }
  }
  // THE PAGE GROWS AS IT IS READ (iOS): the next lines come when the last is near, never the whole book at the opening
  useEffect(() => {
    const el = end.current;
    if (!el || !more || typeof IntersectionObserver === "undefined") return undefined;
    const io = new IntersectionObserver((seen) => { if (seen.some((s) => s.isIntersecting)) setLimit((x) => x + 120); });
    io.observe(el);
    return () => io.disconnect();
  });
  const today = new Date(new Date().getFullYear(), new Date().getMonth(), new Date().getDate()).getTime();
  if (opened?.move) return <MovePage line={opened.move} onClose={() => setOpened(null)} />;
  if (opened?.card) return <OperationCard line={opened.card} onClose={() => setOpened(null)} />;
  const dayTitle = (d) => (d === today ? t("Today") : d === today - 86400000 ? t("Yesterday")
    : new Date(d).toLocaleDateString(locale, { day: "numeric", month: "long", year: "numeric" }));
  return (
    <Page title={t("History")} onClose={onClose} back>
      <input className="set-field history-search" type="search" placeholder={t("Search contacts")} aria-label={t("Search contacts")}
             value={query} onChange={(e) => { setQuery(e.target.value); setLimit(120); }} />
      <div className="segmented history-flow" role="radiogroup" aria-label={t("Operations")}>
        {[["all", "All"], ["spending", "Spending"], ["income", "Income"]].map(([k, w]) => (
          <button key={k} role="radio" aria-checked={flow === k} className={flow === k ? "on" : ""} onClick={() => { setFlow(k); setLimit(120); }}>{t(w)}</button>
        ))}
      </div>
      {moves && !shown.length && <div className="post-note">{t("No operations")}</div>}
      {shown.map((d) => (
        <Section key={d.day} head={<span className="history-day"><span>{dayTitle(d.day)}</span><span className="digits">{(d.sum > 0 ? "+" : "") + count(d.sum)}</span></span>}>
          {d.lines.map((l) => {
            const row = (
              <>
                <KindGlyph k={l.k} />
                <span className="row-title history-words"><span className="history-who">{l.title}</span>
                  <span className="row-caption">{l.category} · {hourOf(l.at * 1000)}</span></span>
                <span className="row-value history-sum"><span className="digits" style={{ color: l.signed > 0 ? "var(--green)" : "#fff" }}>{(l.signed > 0 ? "+" : "") + count(l.signed)}</span>
                  <span className="row-caption digits">{timeOf(Math.abs(l.signed))}</span></span>
              </>
            );
            // a transfer opens its record in the Explorer, a move between people the transaction's own page, every other line its card
            const open = l.tx ? () => invoke("open_link", { url: TX_LINK + l.tx }).catch(() => {})
              : l.src === "sent" || l.src === "received" ? () => setOpened({ move: l }) : () => setOpened({ card: l });
            return <button key={l.id} className="set-row history-row" onClick={open} aria-label={`${l.title}: ${(l.signed > 0 ? "+" : "") + count(l.signed)}`}>{row}</button>;
          })}
        </Section>
      ))}
      {more && <div ref={end} className="history-more"><span className="spinner" /></div>}
    </Page>
  );
}
/** The transfer's confirmation link (iOS MTCoinTx.link): its record in the Explorer. */
const TX_LINK = "https://montana.xxx/explorer/#tx=";
/** The Explorer's page (iOS MTCoinTx.explorer), and a coin key's whole chain in it (iOS MTCoinTx.keyLink). */
const EXPLORER = "https://montana.xxx/explorer/";
const KEY_LINK = "https://montana.xxx/explorer/#key=";

/** THE TIME COIN'S OWN PAGE OVER THE APP (iOS MTWalletPage in ui.walletPage): the platform's large title inline at the bar's leading
 *  edge, one mark on the bar -- the cross in its right corner --, the page under it, and the one mini player at its foot (iOS
 *  safeAreaInset .bottom: MontanaPlayerBar). It rises as a sheet and leaves the way it came. */
export function WalletPage({ person, onOpenChat, onClose }) {
  const [leaving, setLeaving] = useState(false);
  const leave = () => { if (leaving) return; setLeaving(true); setTimeout(onClose, 260); };
  useLeave(leave);
  return (
    <div className={"page-over rises wallet-over" + (leaving ? " leaving" : "")} inert={leaving || undefined} role="dialog" aria-label={t("TimeCoin")}>
      <PageGround />
      {/* the bar is the page's own: a sheet opened over it (send, top up, the hour …) covers it whole, its cross leaving with it */}
      <WalletPane person={person} onOpenChat={(r) => { onClose(); onOpenChat?.(r); }} bar={
        <header className="page-bar wallet-topbar">
          <div className="wallet-title">{t("TimeCoin")}</div>
          <button className="glass-mark" onClick={leave} aria-label={t("Close")}><Glyph name="close" size={18} color="var(--bar-glyph)" /></button>
        </header>
      } />
      <div className="wallet-player"><PlayerBar /></div>
    </div>
  );
}

export default function WalletPane({ person, onOpenChat, bar }) {
  const [st, setSt] = useState(null);
  const [failed, setFailed] = useState(false);   // the page's first read did not answer
  const [main, setMain] = useState(() => { try { return localStorage.getItem("coinUnit") || "time"; } catch { return "time"; } });
  const [sheet, setSheet] = useState(null);
  const [pops, setPops] = useState([]);
  const read = () => invoke("wallet_state", {}).then(setSt).catch(() => {});
  // the page's opening read: asked again from its waiting row when it did not answer
  const opening = () => invoke("wallet_state", { open: true }).then((x) => { setFailed(false); setSt(x); }, () => setFailed(true));
  useEffect(() => {
    // THE AUTO MINTING IS ON BY DEFAULT (iOS, 09.10.2026): the page standing open mints by the second; leaving it ends it
    opening();
    let stop = null, gone = false;
    listen("montana://coins", read).then((u) => { if (gone) u(); else stop = u; });
    // the page leaving ends the auto minting and lets the coin go (iOS onDisappear: autoMint.stop, pantheon.released)
    return () => { gone = true; stop?.(); invoke("wallet_state", { open: false }).catch(() => {}); invoke("wallet_touch", { down: false }).catch(() => {}); };
  }, []);
  // THE CHATS' CREDITING, AT THE FINGER (iOS MTRisingPlus): the capsule -- our coin turning beside «+N» -- rises 56 from the point the
  // pointer touched and fades in 0.8 s; five at most, the oldest giving way
  const at = useRef({ x: 72, y: 72 });
  const tap = async () => {
    const c = await invoke("wallet_tap").catch(() => 0);
    if (c > 0) {
      const pop = { id: Date.now() + Math.random(), coins: c, ...at.current };
      setPops((p) => [...p.slice(-4), pop]);
      setTimeout(() => setPops((p) => p.filter((x) => x.id !== pop.id)), 850);
    }
    read();
  };
  const place = (e) => { const r = e.currentTarget.getBoundingClientRect(); at.current = { x: e.clientX - r.left, y: e.clientY - r.top }; };
  // THE NINE SECONDS AND THE SWIPE (iOS MTCoinTapPad: armNine, swiped; the author's words 04.10.2026 00:58 and 12:28 MSK): a press that
  // stays on the coin nine seconds, never swiping, turns the auto minting on; every 28 points of the path over the coin is one more
  // touch -- it mints, and it is no hold. The click a swipe ends with mints nothing more.
  const nine = useRef(0);
  const path = useRef(null);
  const swiped = useRef(false);
  const disarm = () => { clearTimeout(nine.current); nine.current = 0; };
  const down = (e) => {
    place(e);
    invoke("wallet_touch", { down: true }).catch(() => {});
    disarm();
    nine.current = setTimeout(() => { nine.current = 0; invoke("wallet_pull", { why: "hold" }).then(read).catch(() => {}); }, 9000);
    path.current = { x: e.clientX, y: e.clientY, run: 0 };
    swiped.current = false;
  };
  const lift = () => { disarm(); path.current = null; invoke("wallet_touch", { down: false }).catch(() => {}); };
  const drag = (e) => {
    const p = path.current;
    if (!p || !(e.buttons & 1)) return;
    p.run += Math.hypot(e.clientX - p.x, e.clientY - p.y);
    p.x = e.clientX; p.y = e.clientY;
    place(e);
    while (p.run >= 28) { p.run -= 28; disarm(); swiped.current = true; tap(); }
  };
  // THE COIN IN THE PULL (iOS MTWalletScreen.pulled, MontanaCoinSpinner; the author's words 04.10.2026 03:19-03:56 MSK): the page
  // drawn down at its top -- the wheel or the touchpad here -- brings the coin, which turns with the pull; let go past the trigger,
  // it turns the auto minting on and reads the page again. While the Pantheon burns nothing is pulled.
  const [pull, setPull] = useState(0);
  const [released, setReleased] = useState(null);
  const pane = useRef(null);
  const pullRef = useRef({ p: 0, idle: 0 });
  const wheel = (e) => {
    const r = pullRef.current;
    if (st?.pantheon?.lit || (pane.current && pane.current.scrollTop > 0) || (e.deltaY >= 0 && r.p === 0)) return;
    r.p = Math.max(0, Math.min(PULL.full, r.p - e.deltaY * (e.deltaMode === 1 ? 33 : 1) * 0.5));
    setPull(r.p);
    clearTimeout(r.idle);
    r.idle = setTimeout(() => {
      const armed = r.p >= PULL.trigger;
      r.p = 0;
      setPull(0);
      if (!armed) return;
      setReleased({ at: performance.now(), angle: pullAngle(PULL.trigger) });
      invoke("wallet_pull", { why: "pull" }).then(read).catch(() => {});
      setTimeout(() => setReleased(null), PULL.finish + 150);
    }, 220);
  };
  useEffect(() => () => { clearTimeout(nine.current); clearTimeout(pullRef.current.idle); }, []);
  const pick = (u) => { setMain(u); try { localStorage.setItem("coinUnit", u); } catch { /* the choice lives this run */ } };
  // THE BAR STANDS AT ONCE (the freeze of the panel's first slot, 25.10.2026): the page's title and its cross while the wallet is
  // read, never a page without its way out over an app it has made inert
  if (!st) {
    return (
      <div className="wallet-wrap">{bar}<div className="wallet-pane">
        {failed ? <Section><Waiting failed onRetry={opening} /></Section> : <div className="history-more" role="status"><span className="spinner" /></div>}
      </div></div>
    );
  }
  // THE PERSON'S COINS ARE THE CHAIN'S (iOS MTWalletScreen.total, fold-7): once the chain has spoken in this run, the available it
  // holds; before it, the book (and the balance a device of the same words told in its tip) -- the sums, π's place and the Send
  const total = st.split ? st.available : st.balance;
  if (sheet === "send") return <SendSheet available={st.available} onClose={() => { setSheet(null); read(); }} onOpenChat={onOpenChat} />;
  if (sheet === "top") return <TopUp onClose={() => setSheet(null)} />;
  if (sheet === "history") return <History onClose={() => setSheet(null)} />;
  if (sheet?.chain) return <ChainPage source={sheet.chain} onClose={() => setSheet("chains")} />;
  if (sheet === "chains") return <TimeChainsPage onOpen={(chain) => setSheet({ chain })} onClose={() => setSheet(null)} />;
  if (sheet === "levels") return <PiLevels balance={total} onClose={() => setSheet(null)} />;
  if (sheet === "analytics") return <Analytics onClose={() => setSheet(null)} />;
  if (sheet === "hour") return <HourWorth rate={st.rate} onClose={() => { setSheet(null); read(); }} />;
  const fire = st.pantheon || {};
  const sum = (u) => (u === "time" ? timeOf(total) : u === "coins" ? coinsOf(total) : `${montana(total)} ${st.ticker}`);
  // the wall's two rows are the bare numbers (iOS String(...)), every count of the book parts its thousands (MTCoinText.count)
  const rows = [["Minting now", String(st.wall?.now ?? 0)], ["Rights from the wall", String(st.wall?.rights ?? 0)],
                ["Coins from chats", count(st.counts.earned)], ["Coins from the Pantheon", count(st.counts.tapped)], ["Coins from chess", count(st.counts.played)],
                ["Coins from the VPN Wall", count(st.counts.walled ?? 0)], ["Coins burned", count(st.counts.burned)], ["Coins received", count(st.counts.received)],
                ["Coins sent", count(st.counts.sent)], ["Coins on reactions", count(st.counts.spent)]];
  // THE COIN TURNS WHILE IT MINTS (iOS): at the taps' speed while the Pantheon burns, at least once a second while the auto minting
  // runs; lit with no taps it rests on its face, its glow dimmed to embers
  const minting = st.minting || fire.lit;
  const spinning = (fire.speed || 0) > 0 || !!st.minting;
  const apps = [...new Set((st.flash?.apps || []).map((s) => FLASH_APP[s]).filter(Boolean))];
  // the badge on the coin (iOS MTMintLevelBadge): the level of π the balance fills, «×N» while N apps mint at once
  const badge = [st.pi > 0 ? String(st.pi) : "", apps.length >= 2 ? `×${apps.length}` : ""].filter(Boolean).join(" ");
  const rate = st.rate && st.rate.amount > 0 ? st.rate : null;
  // the page drawn down follows the pull; let go past the trigger it keeps a gap while the coin's round completes (iOS hold)
  const drawn = released ? PULL.hold : pull;
  return (
    <div className="wallet-wrap">
    {bar}
    {(pull > PULL.start || released) && <div className="wallet-spin"><CoinSpinner pull={pull} released={released} /></div>}
    <div className={"wallet-pane" + (fire.lit ? " still" : "")} aria-label={t("TimeCoin")} ref={pane} onWheel={wheel}
         style={drawn ? { transform: `translateY(${drawn}px)`, transition: released ? "transform 0.2s ease-out" : "none" } : { transition: "transform 0.35s ease" }}>
      <CoinSides flash={st.flash} />
      <div className="wallet-head">
        {/* THE NAME STANDS ALWAYS AND BURNS WHILE THE GAME BURNS (iOS MTWalletScreen, the author's words 04.10 and 08.10.2026) */}
        <div className={"wallet-name" + (fire.lit ? " lit" : "")}><Flame /> {t("Pantheon on Fire")}</div>
        {/* THE APPS THAT MINT, ABOVE THE COIN (iOS MTMintingApps): their icons; the row keeps its place when none mints */}
        <div className="wallet-apps" role="img" aria-label={apps.length ? `${t("Minting")} ${apps.map((a) => t(TITLES[a])).join(", ")}` : undefined}>
          {apps.map((a) => <AppIcon key={a} app={a} side={30} />)}
        </div>
        <button className={"wallet-coin" + (minting ? " minting" : "") + (fire.lit ? ((fire.speed || 0) > 0 ? " lit" : " lit embers") : "")} aria-label={t("Coin")}
                onClick={() => { if (swiped.current) { swiped.current = false; return; } tap(); }}
                onPointerDown={down} onPointerUp={lift} onPointerLeave={lift} onPointerMove={drag}>
          <MintCoin side={120} spinning={spinning} speed={Math.max(fire.speed || 0, st.minting ? 1 : 0)} turn={minting ? undefined : 0} />
          {badge && <span className="count-badge wallet-badge">{badge}</span>}
          {pops.map((p) => (
            <span key={p.id} className="wallet-pop ultrathin" style={{ left: p.x, top: p.y }} aria-hidden="true">
              <MintCoin side={18} turn={1} /><b className="digits">+{count(p.coins)}</b>
            </span>
          ))}
        </button>
        {/* THE NEXT BOX FILLS AS A LOAD FILLS (iOS MTLevelProgress): from the box the balance fills to the next, while it mints */}
        <LevelProgress balance={total} shown={minting} />
        {/* THE PRICE OF A SECOND, FIXED (iOS MTSecondPrice): the one rate, the person's own under it, and the question of the hour */}
        <div className="wallet-price">
          <div className="post-note">{t("1 second = %lld coins").replace("%lld", "1")}</div>
          {rate && <div className="post-note">{t("Your rate: 1 coin = %@").replace("%@", money(coinWorth(rate), rate.code, 3))}</div>}
          {rate && <button className="link-button" onClick={() => setSheet("hour")}>{t("Your hour: %@").replace("%@", money(hourly(rate), rate.code, 4))}</button>}
          <button className="link-button blue" onClick={() => setSheet("hour")}>{t("What is Your hour worth Now?")}</button>
        </div>
        {/* THE BURN'S MINUTE AND THE REST (iOS MTPantheonStreak): shown and hidden in its place, so the coin never moves */}
        <div className="wallet-streak" style={{ visibility: fire.run != null || fire.rest != null ? "visible" : "hidden" }}>
          <div className="wallet-bar"><i style={{ width: `${(100 * (fire.rest ?? fire.run ?? 0)) / 60}%`, background: fire.rest != null ? "var(--gray)" : "#ff9f0a" }} /></div>
          <div className="post-note">{fire.rest != null ? t("Minting rests %@ s").replace("%@", fire.rest) : t("%@ of 60 seconds unbroken").replace("%@", fire.run ?? 0)}</div>
        </div>
        <div className="post-note sub">{t("Time Balance")}</div>
        <FitSum className="wallet-main" onClick={() => pick(main)} label={`${t("Time Balance")}: ${sum(main)}`}>{sum(main)}</FitSum>
        {UNITS.filter((u) => u !== main).map((u) => <button key={u} className="wallet-other" onClick={() => pick(u)}>{sum(u)}</button>)}
        {st.gathering && <div className="post-note gathering"><span className="spinner small" />{t("Gathering your coins")}</div>}
        <div className="post-note sub digits" aria-label={t("Available %@").replace("%@", count(st.available))}>{t("Available %@").replace("%@", count(st.available))}</div>
        {/* THE BALANCE IN THE PERSON'S CURRENCY (iOS MTPersonalRate): the balance at their own rate, in the currency's own format */}
        {rate && <div className="post-note sub digits">{money(coinWorth(rate) * total, rate.code)}</div>}
        <div className="post-note digits">π {pi(st.pi)} · {st.pi}</div>
        {/* TWO BUTTONS OF THE SYSTEM, ONE WIDTH, THE PLATFORM'S BLUE; THEN THE PAGE'S FOUR DOORS (iOS: bordered capsules) */}
        <div className="wallet-keys">
          <button className="capsule prominent" onClick={() => setSheet("send")} disabled={total <= 0} aria-label={t("Send")}>
            <img src={timeSend} alt="" className="time-send" /><span>{t("Send")}</span>
          </button>
          <button className="capsule prominent" onClick={() => setSheet("top")} aria-label={t("Top up")}>
            <Sf name="plusCircle" size={20} color="#fff" /><span>{t("Top up")}</span>
          </button>
        </div>
        <button className="capsule bordered" onClick={() => setSheet("chains")}><Glyph name="link" size={18} color="var(--blue)" /><span>TimeChain</span></button>
        <button className="capsule bordered" onClick={() => setSheet("levels")}><Sf name="listNumber" size={18} color="var(--blue)" /><span>{t("Levels of π")}</span></button>
        <button className="capsule bordered" onClick={() => setSheet("history")}><Sf name="history" size={18} color="var(--blue)" /><span>{t("History")}</span></button>
        <button className="capsule bordered" onClick={() => setSheet("analytics")}><Sf name="chartPie" size={18} color="var(--blue)" /><span>{t("Analytics")}</span></button>
      </div>
      <Top13 st={st} person={person} />
      <Section head={t("Minting")} foot={t("Coins are counted on this computer until the wallet opens.")}>
        {rows.map(([w, v]) => <div key={w} className="set-row" role="group" aria-label={`${t(w)}: ${v}`}><span className="row-title">{t(w)}</span><span className="row-value digits">{v}</span></div>)}
        <div className="set-row" role="group" aria-label={`${t("Coins in Montana")}: ${montana(total)}`}><span className="row-title">{t("Coins in Montana")}</span><span className="row-value digits">{montana(total)}</span></div>
      </Section>
    </div>
    </div>
  );
}

/** SF flame.fill in its multicolour (iOS Label icon of «Pantheon on Fire»): the orange tongue with its yellow heart. */
function Flame({ size = 24 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" className="wallet-flame">
      <path d="M12.3 1.8c.6 3.6-3.9 6-4.9 10.3-.7 3 .6 5.8 2.6 7.3-.8-1.9-.5-3.8.9-5.6.6 1.9 1.8 2.6 2.7 2.6-.6-2.5.4-5 2.1-6.6.3 2.4 1.8 3.5 2.4 5.4.8 2.3-.1 4.6-1.8 5.9 3.1-1 5.2-3.9 5.2-7.4 0-5.7-5.3-8.5-9.2-11.9z" fill="#ff9f0a" />
      <path d="M12 22c-2.3 0-4-1.7-4-3.9 0-2 1.4-3.2 2.6-4.6.3 1.4 1.1 2.2 2 2.4-.3-1.9.5-3.4 1.6-4.4.4 2.1 2 3.2 2 5.5 0 2.7-1.9 5-4.2 5z" fill="#ffd60a" />
    </svg>
  );
}

/** THE MAIN SUM ON ONE LINE (iOS balanceSum: 48 bold, .lineLimit(1).minimumScaleFactor(0.3)): a sum wider than its row narrows its
 *  type to fit, never below three tenths, and never wraps. */
function FitSum({ className, onClick, label, children }) {
  const el = useRef(null);
  const [size, setSize] = useState(48);
  useLayoutEffect(() => {
    const b = el.current;
    if (!b) return undefined;
    const fit = () => {
      b.style.fontSize = "48px";
      const room = b.clientWidth, need = b.scrollWidth;
      setSize(need > room && room > 0 ? Math.max(48 * 0.3, Math.floor((48 * room) / need)) : 48);
      b.style.fontSize = "";
    };
    fit();
    const ro = typeof ResizeObserver !== "undefined" ? new ResizeObserver(fit) : null;
    ro?.observe(b);
    return () => ro?.disconnect();
  }, [children]);
  return <button ref={el} className={className} onClick={onClick} aria-label={label} style={{ fontSize: size }}>{children}</button>;
}

/** The SF Symbols the wallet's doors wear in iOS, drawn here at their shapes (the shipped glyphs carry none of them):
 *  plus.circle.fill, list.number, clock.arrow.circlepath, chart.pie, arrow.up.right, arrow.down.left. */
function Sf({ name, size = 18, color = "currentColor" }) {
  const d = {
    plusCircle: <><circle cx="12" cy="12" r="10" fill={color} /><path d="M12 7v10M7 12h10" stroke="#0a84ff" strokeWidth="2.2" strokeLinecap="round" /></>,
    listNumber: <><path d="M10 6h11M10 12h11M10 18h11" stroke={color} strokeWidth="2" strokeLinecap="round" /><text x="2.5" y="8" fontSize="6.5" fill={color} fontWeight="700">1</text><text x="2.5" y="14" fontSize="6.5" fill={color} fontWeight="700">2</text><text x="2.5" y="20" fontSize="6.5" fill={color} fontWeight="700">3</text></>,
    history: <><path d="M4.5 12a7.5 7.5 0 1 0 2.2-5.3" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" /><path d="M3.5 4.5v4h4" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" /><path d="M12 8v4.5l3 2" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" /></>,
    chartPie: <><path d="M11 3.5a8.5 8.5 0 1 0 9.5 9.5H11z" fill="none" stroke={color} strokeWidth="2" strokeLinejoin="round" /><path d="M14 2.5a8 8 0 0 1 7.5 7.5H14z" fill={color} /></>,
    arrowUpRight: <path d="M7 17L17 7M9 7h8v8" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />,
    arrowDownLeft: <path d="M17 7L7 17M15 17H7V9" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />,
  }[name];
  return <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">{d}</svg>;
}

/** The platform's filled check (SF checkmark.circle.fill): the system's blue, or -- `accent` -- the app's AccentColor, white on the dark
 *  ground and black on the light (the levels of π). */
function CheckFill({ size = 22, accent = false }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" className="pi-check">
      <circle cx="12" cy="12" r="11" fill={accent ? "var(--ink)" : "var(--blue)"} />
      <path d="M7 12.4l3.3 3.2L17.2 8.6" fill="none" stroke={accent ? "var(--page, #000)" : "#fff"} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** Which application a chain's coins are of (iOS MTTimeChain.app): the icon over the coin while that chain's coins are born. */
const FLASH_APP = { chess: "chess", timer: "chess", pantheon: "wallet", vpnwall: "vpn", vpnpay: "vpn", calls: "calls", chats: "chats",
                    groups: "chats", channels: "chats", comments: "feed", wall: "feed" };

/** THE SIDES' COINS (iOS MTCoinSides): at every second that minted, our coin rises at the left and the right edge with the count,
 *  makes its turn and fades (0.9 s rising, the fade 0.3 s after 0.6 s); with Reduce Motion they stand and fade. */
function CoinSides({ flash }) {
  const [tick, setTick] = useState(0);
  const [coins, setCoins] = useState(0);
  const last = useRef(0);
  useEffect(() => {
    if (!flash?.coins || Date.now() - last.current < 900) return;
    last.current = Date.now();
    setCoins(flash.coins);
    setTick((n) => n + 1);
  }, [flash?.coins, flash]);
  if (!tick) return null;
  const side = (
    <div className="coin-side ultrathin"><MintCoin side={30} turn={tick} /><b className="digits">+{count(coins)}</b></div>
  );
  return <div className="coin-sides" key={tick} aria-hidden="true">{side}{side}</div>;
}

/** THE NEXT BOX FILLS AS A LOAD FILLS (iOS MTLevelProgress): the platform's thin bar from the box the balance fills to the next,
 *  the coins left under it; shown and hidden in its place, never inserted, so the coin never moves. */
function LevelProgress({ balance, shown }) {
  const place = PI_LEVELS.filter((v) => v <= balance).length;
  if (place >= PI_LEVELS.length) return null;
  const low = place > 0 ? PI_LEVELS[place - 1] : 0, high = PI_LEVELS[place];
  return (
    <div className="level-progress" style={{ visibility: shown ? "visible" : "hidden" }} aria-hidden={!shown}>
      <progress max={Math.max(1, high - low)} value={Math.max(0, balance - low)} />
      {/* THE NEXT LEVEL IN TIME (iOS, the author's word 20.10.2026 00:08 MSK): one coin is one second, so what is left reads as a span */}
      <div className="post-note digits">{t("%1$@ to level %2$lld").replace("%1$@", timeOf(high - balance, false)).replace("%2$lld", place + 1)}</div>
    </div>
  );
}

/** THE LEVELS OF π (iOS MTPiLevels.all): the first n digits of π as whole coins, nineteen of them. */
const PI_LEVELS = Array.from({ length: 19 }, (_, i) => Number("3141592653589793238".slice(0, i + 1)));
/** A level's coins short (iOS MTPiLevels.short): 3, 31, 314, 3.1K … in the platform's compact form. */
const shortCoins = (n) => new Intl.NumberFormat(locale, { notation: "compact", maximumFractionDigits: 1 }).format(n);

/** THE LEVELS OF π AS A TIMECHAIN, THE NEWEST ON TOP (iOS MTPiLevelsSheet): the next level to reach on top, then the levels reached,
 *  thirteen at a time, each with π revealed to it, its coins short and as a share of a Montana; the reached wear the check, the
 *  person's own level stands out. */
function PiLevels({ balance, onClose }) {
  const place = PI_LEVELS.filter((v) => v <= balance).length;
  const top = Math.min(PI_LEVELS.length, place + 1);
  const levels = [];
  for (let n = top; n >= Math.max(1, top - 13 + 1); n--) levels.push(n);
  return (
    <Page title={t("Levels of π")} onClose={onClose}>
      <Section>
        {levels.map((n) => {
          const coins = PI_LEVELS[n - 1], reached = n <= place;
          return (
            <div key={n} className={"set-row pi-level" + (reached ? " reached" : "") + (n === place ? " mine" : "")} role="group"
                 aria-label={`${n} · π ${pi(n)} · ${shortCoins(coins)}${reached ? " ✓" : ""}`}>
              <span className="pi-n digits">{n}</span>
              <span className="row-title pi-words"><b className="digits">π {pi(n)}</b><span className="row-caption digits">{shortCoins(coins)} · {montana(coins)} $TCM</span></span>
              {reached && <CheckFill accent />}
            </div>
          );
        })}
      </Section>
    </Page>
  );
}

/** THE PERSONAL RATE OF THE COIN (iOS MTPersonalRate): an hour holds 3 600 seconds of one coin each; a year of work is 2 080 hours,
 *  a month a twelfth of it. */
const HOURS = { hour: 1, month: 2080 / 12, year: 2080 };
const hourly = (r) => r.amount / (HOURS[r.per] || 1);
const coinWorth = (r) => hourly(r) / 3600;
/** A sum in the person's currency: with as many significant digits as iOS gives it, or -- none named -- in the currency's own
 *  standard format (iOS .currency(code:)). */
function money(v, code, digits) {
  try { return new Intl.NumberFormat(locale, digits ? { style: "currency", currency: code, maximumSignificantDigits: digits } : { style: "currency", currency: code }).format(v); }
  catch { return digits ? `${v.toPrecision(digits)} ${code}` : `${v.toFixed(2)} ${code}`; }
}
/** The currencies in use (iOS MTCurrency.all: NSLocale.commonISOCurrencyCodes), each with its flag and its own name. */
const CURRENCIES = (() => {
  try { return Intl.supportedValuesOf("currency"); } catch { return ["USD", "EUR", "RUB", "GBP", "CNY", "JPY"]; }
})();
const flagOf = (code) => (code === "EUR" ? "🇪🇺" : code.startsWith("X") ? "🌐" : String.fromCodePoint(...[...code.slice(0, 2)].map((c) => 0x1f1a5 + c.charCodeAt(0))));
/** A currency's name in its own country's language (iOS MTCurrencyMenu): the country's likely language by CLDR's own subtags; the
 *  euro, and a currency of no one country, in the person's language. */
const currencyName = (code) => {
  let lang = locale;
  try {
    const cc = code.slice(0, 2);
    if (code !== "EUR" && !code.startsWith("X")) lang = `${new Intl.Locale("und-" + cc).maximize().language}-${cc}`;
  } catch { /* the person's language */ }
  try { return new Intl.DisplayNames([lang, locale], { type: "currency" }).of(code); } catch { return code; }
};

/** WHAT AN HOUR IS WORTH (iOS MTHourWorth): the period's segments, the sum and its currency; the sum told becomes the person's
 *  rate at once, kept on this machine alone (never sent); an emptied field takes it back. */
function HourWorth({ rate, onClose }) {
  const [per, setPer] = useState(rate?.per || "hour");
  // iOS: the system's own currency first (Locale.current.currency), here Windows' own for the person's region
  const [code, setCode] = useState(rate?.code || "USD");
  useEffect(() => { if (!rate?.code) invoke("system_currency").then((c) => { if (c) setCode(c); }).catch(() => {}); }, []);
  const [amount, setAmount] = useState(rate?.amount ? String(rate.amount) : "");
  const value = Number(amount.replace(",", ".").replace(/[^\d.]/g, "")) || 0;
  // the sum is kept as it is typed (iOS @AppStorage): every change at once, so leaving the page loses nothing
  useEffect(() => { invoke("coin_rate_set", { amount: value, per, code }).catch(() => {}); }, [value, per, code]);
  const word = value > 0 ? { amount: value, per, code } : null;
  return (
    // a sheet with its close at the left and the check at the right (iOS MTHourWorth: cancellation and confirmation actions)
    <Page title={t("Your hour")} onClose={onClose}
          right={<button className="glass-mark" onClick={onClose} aria-label={t("Done")}><Glyph name="tick" size={18} color="var(--bar-glyph)" /></button>}>
      <Section head={t("How much do you earn?")} foot={per !== "hour" ? t("A year of work is 2,080 hours: forty a week") : null}>
        {/* the platform's segments (iOS .pickerStyle(.segmented)) */}
        <div className="segmented" role="radiogroup" aria-label={t("Period")}>
          {[["hour", "Hour"], ["month", "Month"], ["year", "Year"]].map(([k, w]) => (
            <button key={k} role="radio" aria-checked={per === k} className={per === k ? "on" : ""} onClick={() => setPer(k)}>{t(w)}</button>
          ))}
        </div>
        <div className="set-row hour-field">
          <input className="set-field" inputMode="decimal" placeholder={t(per === "hour" ? "Per hour" : per === "month" ? "Per month" : "Per year")}
                 aria-label={t(per === "hour" ? "Per hour" : per === "month" ? "Per month" : "Per year")} value={amount} onChange={(e) => setAmount(e.target.value)} />
          {/* the field's right edge shows the chosen flag and code; the list names every currency in its own language (iOS MTCurrencyMenu) */}
          <label className="currency-menu">
            <span className="digits">{flagOf(code)} {code}</span><span className="currency-chevron" aria-hidden="true">⌃⌄</span>
            <select aria-label={t("Currency")} value={code} onChange={(e) => setCode(e.target.value)}>
              {CURRENCIES.map((c) => <option key={c} value={c}>{`${flagOf(c)}  ${c}  ${currencyName(c)}`}</option>)}
            </select>
          </label>
        </div>
      </Section>
      {/* THE CHECK THAT KEEPS THE HOUR, under the question (iOS confirm): the sum is kept as it is typed, the check closes the form */}
      <button className="capsule prominent round-check" onClick={onClose} aria-label={t("Done")}><Glyph name="tick" size={20} color="#fff" /></button>
      <Section foot={t("1 second = %lld coins").replace("%lld", "1")}>
        <div className="set-row"><span className="row-title">{t("1 hour")}</span><span className="row-value digits">{t("%@ coins").replace("%@", count(3600))}</span></div>
        {word && <div className="set-row"><span className="row-title">{t("1 coin")}</span><span className="row-value digits">{money(coinWorth(word), code, 3)}</span></div>}
        {word && <div className="set-row"><span className="row-title">{t("1 second")}</span><span className="row-value digits">{money(hourly(word) / 3600, code, 3)}</span></div>}
      </Section>
    </Page>
  );
}

/** THE ANALYTICS BY ITS OWN BUTTON (iOS MTCoinAnalyticsPage): the months as chips (and every month), the spending and the income,
 *  where the coins came from and went with each source's share -- one fold of the whole book. */
function Analytics({ onClose }) {
  const [moves, setMoves] = useState(null);
  const [month, setMonth] = useState(null);
  useEffect(() => { invoke("coin_moves_all").then(setMoves).catch(() => setMoves([])); }, []);
  const key = (at) => { const d = new Date(at * 1000); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`; };
  const months = [...new Set((moves || []).map((m) => key(m.at)))].sort().reverse();
  const shown = (moves || []).filter((m) => !month || key(m.at) === month);
  const plus = (m) => m.k === "earn" || m.k === "receive";
  const spending = shown.filter((m) => !plus(m)).reduce((n, m) => n + m.c, 0), income = shown.filter(plus).reduce((n, m) => n + m.c, 0);
  // each source's share: its coins both ways (iOS share.moved) and its sum signed; the bar is its coins moved of all moved
  const by = {};
  for (const m of shown) {
    const x = by[m.src] || (by[m.src] = { signed: 0, moved: 0 });
    x.signed += plus(m) ? m.c : -m.c;
    x.moved += m.c;
  }
  const moved = Math.max(1, spending + income);
  const total = (title, coins, glyph) => (
    <div className="analytics-total" role="group" aria-label={`${t(title)}: ${count(coins)}`}>
      <span className="row-caption"><Sf name={glyph} size={14} color="var(--gray)" /> {t(title)}</span>
      <b className="digits">{count(coins)}</b><span className="row-caption">{timeOf(coins)}</span>
    </div>
  );
  return (
    <Page title={t("Analytics")} onClose={onClose} back>
      <div className="chips" role="radiogroup">
        <button role="radio" aria-checked={!month} className={"chip" + (!month ? " on" : "")} onClick={() => setMonth(null)}>{t("Every month")}</button>
        {months.map((k) => {
          const [y, m] = k.split("-");
          const title = new Date(Number(y), Number(m) - 1, 1).toLocaleDateString(locale, { month: "long", year: "numeric" });
          return <button key={k} role="radio" aria-checked={month === k} className={"chip" + (month === k ? " on" : "")} onClick={() => setMonth(k)}>{title}</button>;
        })}
      </div>
      <div className="analytics-totals">{total("Spending", spending, "arrowUpRight")}{total("Income", income, "arrowDownLeft")}</div>
      <Section>
        {!moves && <div className="post-note">…</div>}
        {Object.entries(by).sort((a, b) => b[1].moved - a[1].moved).map(([src, { signed, moved: own }]) => (
          <div key={src} className="set-row analytics-share" role="group" aria-label={`${t(CHAIN_NAMES[src] || src)}: ${signed > 0 ? "+" : ""}${count(signed)}`}>
            <span className="analytics-line">
              <span className="analytics-name">{t(CHAIN_NAMES[src] || src)}</span>
              <span className="analytics-sum digits"><span style={{ color: signed > 0 ? "var(--green)" : "var(--ink)" }}>{(signed > 0 ? "+" : "") + count(signed)}</span>
                <span className="chain-time">{timeOf(signed)}</span></span>
            </span>
            <progress max={moved} value={own} />
          </div>
        ))}
      </Section>
    </Page>
  );
}
