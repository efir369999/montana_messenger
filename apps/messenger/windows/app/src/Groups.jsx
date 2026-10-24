import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t, locale } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { Face, SAVED, chatName, useChanged } from "./Chats.jsx";
import { Page, Section, Toggle } from "./Settings.jsx";
import { Crop } from "./Profile.jsx";
import { EMOJI, REACTIONS } from "./Conversation.jsx";

/** A group's face as its invitation carries it (iOS MTGroup.thumb): the framed square at 160, within 18 000 bytes. */
const GROUP_FACE = { out: 160, limit: 18000, q0: 0.7 };

/** «N участников» as Russian counts it (one / few / many), or «N members». */
export function members(n) {
  if (!locale.toLowerCase().startsWith("ru")) return `${n} ${n === 1 ? "member" : "members"}`;
  const d = n % 10, h = n % 100;
  return `${n} ${d === 1 && h !== 11 ? "участник" : d >= 2 && d <= 4 && (h < 12 || h > 14) ? "участника" : "участников"}`;
}

/** «N подписчиков» as Russian counts it (iOS «%lld subscribers», the owner counted among them), or «N subscribers». */
export function subscribers(n) {
  if (!locale.toLowerCase().startsWith("ru")) return `${n} ${n === 1 ? "subscriber" : "subscribers"}`;
  const d = n % 10, h = n % 100;
  return `${n} ${d === 1 && h !== 11 ? "подписчик" : d >= 2 && d <= 4 && (h < 12 || h > 14) ? "подписчика" : "подписчиков"}`;
}

/** How many a group holds, in its own word: the members of a group, the subscribers of a channel. */
export function people(kind, n) {
  return kind === "c" ? subscribers(n) : members(n);
}

/** THE RIGHTS OF A GROUP'S MEMBERS (iOS MTGroupRight), in the order of iOS's page, each with its row and its refusal. */
const RIGHTS = [
  ["tx", "Send Messages", "Sending messages is not allowed in this group"],
  ["ph", "Send Photos", "Sending photos is not allowed in this group"],
  ["vd", "Send Videos", "Sending videos is not allowed in this group"],
  ["gf", "Send Stickers & GIFs", "Posting stickers isn’t allowed in this group."],
  ["mu", "Send Music", "Sending music is not allowed in this group"],
  ["fl", "Send Files", "Sending files is not allowed in this group"],
  ["vo", "Send Audio Messages", "Sending audio messages is not allowed in this group"],
  ["rv", "Send Video Messages", "Sending video messages is not allowed in this group"],
  ["ln", "Embed Links", "Sending links is not allowed in this group"],
  ["re", "Send Reactions", "Sending reactions is not allowed in this group"],
  ["pn", "Pin Messages", "You cannot edit this permission."],
  ["ci", "Change Group Info", "You cannot edit this permission."],
];
/** The steps of slow mode (iOS MTGroupPermissionsPage.steps): off, 10 and 30 seconds, 1, 5 and 15 minutes, an hour. */
const SLOW = [0, 10, 30, 60, 300, 900, 3600];
const slowWord = (s) => (s === 0 ? t("Off") : s < 60 ? `${s} ${locale.startsWith("ru") ? "с" : "s"}` : s < 3600 ? `${s / 60} ${locale.startsWith("ru") ? "мин" : "min"}` : `1 ${locale.startsWith("ru") ? "ч" : "h"}`);

/** Why the group takes not these words, in iOS's sentence (MTGroupRight.refusal, slowRefusal). */
export function refusalWords(why) {
  if (why?.startsWith("slow:")) {
    const s = +why.slice(5);
    const span = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    return t("Slowmode is enabled. You can send your next message in %@.", { "%@": span });
  }
  return t(RIGHTS.find((r) => r[0] === why)?.[2] || "You cannot edit this permission.");
}

/** THE GROUP'S PERMISSIONS (iOS MTGroupPermissionsPage): one switch a right and slow mode below; what the owner leaves goes to
 *  every member as the page closes, one word for all the changes. */
function Permissions({ chat, g, onClose }) {
  const [barred, setBarred] = useState(new Set(g.barred || []));
  const [slow, setSlow] = useState(g.slow || 0);
  // what the owner leaves goes as the page goes, whatever closes it (iOS onDisappear): one word for all the changes
  const now = useRef({ barred, slow });
  now.current = { barred, slow };
  useEffect(() => () => invoke("group_set_rights", { chat, barred: [...now.current.barred], slow: now.current.slow }), []);
  const close = () => onClose();
  return (
    <Page title={t("Permissions")} onClose={close} back>
      <Section head={t("What can members of this group do?")}>
        {RIGHTS.map(([k, title]) => (
          <Toggle key={k} title={t(title)} on={!barred.has(k)}
                  onChange={(on) => { const b = new Set(barred); if (on) b.delete(k); else b.add(k); setBarred(b); }} />
        ))}
      </Section>
      <Section head={t("Slowmode")} foot={t("Members will be restricted to send one message per this interval.")}>
        <div className="slow-steps" role="radiogroup" aria-label={t("Slowmode")}>
          {SLOW.map((s) => (
            <button key={s} role="radio" aria-checked={s === slow} className={"slow-step" + (s === slow ? " on" : "")} onClick={() => setSlow(s)}>{slowWord(s)}</button>
          ))}
        </div>
      </Section>
    </Page>
  );
}

/** What an administrator may do (iOS MTAdminRight, a channel's MTChannelRight), each a short word on the wire. */
const ADMIN_RIGHTS = [["ci", "Change Group Info"], ["dm", "Delete Messages"], ["bu", "Ban Users"], ["il", "Invite Users via Link"], ["pm", "Pin Messages"]];
const CHANNEL_ADMIN_RIGHTS = [["ci", "Change Channel Info"], ["po", "Post Messages"], ["dm", "Delete Messages of Others"], ["il", "Add Subscribers"]];

/** AN ADMINISTRATOR'S RIGHTS (iOS MTGroupAdminRightsPage): the custom title, «What can this admin do?» one switch a right, and
 *  «Dismiss Admin»; «Done» names or renews the administrator, carried to every member. */
function AdminRights({ chat, g, p, onClose }) {
  const [taken, setTaken] = useState(new Set(p.taken || []));
  const [rank, setRank] = useState(p.rank || "");
  const list = g.kind === "c" ? CHANNEL_ADMIN_RIGHTS : ADMIN_RIGHTS;
  const done = () => { invoke("group_set_admin", { chat, seat: p.seat, on: true, taken: [...taken], rank: rank.trim() }); onClose(); };
  return (
    <Page title={t("Admin Rights")} onClose={onClose} back
          right={<button className="glass-mark" onClick={done} aria-label={t("Done")}><Glyph name="tick" size={18} color="#fff" /></button>}>
      <Section><div className="set-row"><span className="row-title">{p.name || t("Member")}</span></div></Section>
      <Section head={t("Custom Title")} foot={t("A title that will be shown instead of 'admin'.")}>
        <input className="set-field" placeholder={t("admin")} value={rank} maxLength={16} aria-label={t("Custom Title")}
               onChange={(e) => setRank(e.target.value)} />
      </Section>
      <Section head={t("What can this admin do?")}>
        {list.map(([k, title]) => (
          <Toggle key={k} title={t(title)} on={!taken.has(k)}
                  onChange={(on) => { const s = new Set(taken); if (on) s.delete(k); else s.add(k); setTaken(s); }} />
        ))}
      </Section>
      {p.admin && (
        <Section>
          <button className="set-row" onClick={() => { invoke("group_set_admin", { chat, seat: p.seat, on: false, taken: [], rank: "" }); onClose(); }}>
            <span className="row-title red">{t("Dismiss Admin")}</span>
          </button>
        </Section>
      )}
    </Page>
  );
}

/** The reactions a channel's owner chooses among (iOS MTChannelReactionsPage.choice): the common ones first, then the
 *  panel's own, each once, eighty at most -- and a glyph its list holds that the choice does not, after them. */
function reactionChoice(list) {
  const all = [...new Set([...REACTIONS, ...EMOJI])].slice(0, 80);
  return [...all, ...list.filter((e) => !all.includes(e))];
}

/** THE CHANNEL'S REACTIONS (iOS MTChannelReactionsPage): «AVAILABLE REACTIONS» -- every reaction a tap in or out, every one taken
 *  while all stand chosen, one at least (none at all is «Allow Reactions» off). The choice goes as the page goes: one word. */
function ChannelReactions({ chat, g, onClose }) {
  const all = reactionChoice(g.react_list || []);
  const [chosen, setChosen] = useState(new Set((g.react_list || []).length ? g.react_list : all));
  const now = useRef(chosen);
  now.current = chosen;
  useEffect(() => () => {
    const c = now.current;
    invoke("channel_reactions", { chat, list: c.size === all.length ? [] : all.filter((x) => c.has(x)) });
  }, []);
  const flip = (e) => {
    const s = new Set(chosen);
    if (s.has(e)) s.delete(e); else s.add(e);
    if (s.size) setChosen(s);
  };
  return (
    <Page title={t("Reactions")} onClose={onClose} back>
      <Section head={t("AVAILABLE REACTIONS")} foot={t("Allow subscribers to react to channel posts.")}>
        <div className="react-grid">
          {all.map((e) => (
            <button key={e} className={"react-pick" + (chosen.has(e) ? " on" : "")} aria-label={e} aria-pressed={chosen.has(e)} onClick={() => flip(e)}>{e}</button>
          ))}
        </div>
      </Section>
    </Page>
  );
}

/** THE PEOPLE WHO ASKED BY THE LINK (iOS «Member Requests»): each with «Add to Group» and «Dismiss», the newest first. */
function Requests({ chat, g, onClose }) {
  const list = [...(g.requests || [])].sort((a, b) => b.at - a.at);
  return (
    <Page title={t("Member Requests")} onClose={onClose} back>
      {list.length === 0 ? (
        <Section foot={t("You have no pending requests to join the group.")}><div className="set-row"><span className="row-title">{t("No Member Requests")}</span></div></Section>
      ) : (
        <Section>
          {list.map((r) => (
            <div key={r.pipe} className="set-row member">
              <span className="member-name">{r.name || t("Member")}</span>
              <button className="unblock" onClick={() => { invoke("group_request", { chat, pipe: r.pipe, add: true }); onClose(); }}>{t("Add to Group")}</button>
              <button className="unblock" onClick={() => { invoke("group_request", { chat, pipe: r.pipe, add: false }); onClose(); }}>{t("Dismiss")}</button>
            </div>
          ))}
        </Section>
      )}
    </Page>
  );
}

/** The tint of a speaker's name (iOS memberTint): FNV-1a over the speaker's reference, into iOS's eight colours. */
const TINTS = ["#007AFF", "#34C759", "#FF9500", "#AF52DE", "#FF2D55", "#FF3B30", "#30B0C7", "#5856D6"];
export function tint(ref) {
  let h = 0x811c9dc5;
  for (const b of new TextEncoder().encode(ref)) { h ^= b; h = Math.imul(h, 0x01000193) >>> 0; }
  return TINTS[h % TINTS.length];
}

/** A GROUP'S FACE: its photo when the owner gave one (iOS MTGroup.face), else the people glyph in a circle. */
export function GroupFace({ size = 48, chat, version, onClick }) {
  if (chat && version) return <div onClick={onClick} style={onClick ? { cursor: "pointer" } : null}><Face chat={chat} version={version} size={size} /></div>;
  return (
    <div className="face group-face" style={{ width: size, height: size, cursor: onClick ? "pointer" : null }} onClick={onClick}>
      <Glyph name="contacts" size={size * 0.5} color="#fff" />
    </div>
  );
}

/** THE PEOPLE A GROUP CAN HOLD (iOS MTGroupPickStep): only those with a correspondence -- a group's letter rides each
 *  person's own pipe. */
function Pick({ title, except = [], onDone, onClose, foot = t("A group's letter rides each person's own channel, so only the people you write with are listed.") }) {
  const [rows, setRows] = useState([]);
  const [q, setQ] = useState("");
  const [chosen, setChosen] = useState([]);
  useEffect(() => { invoke("chats").then((r) => setRows(r.filter((x) => !x.group && !x.blocked && x.ref !== SAVED && !except.includes(x.ref)))); }, []);
  const shown = rows.filter((r) => !q.trim() || chatName(r.name).toLowerCase().includes(q.trim().toLowerCase()));
  const flip = (r) => setChosen(chosen.includes(r) ? chosen.filter((x) => x !== r) : [...chosen, r]);
  return (
    <Page title={title} onClose={onClose}
          right={<button className="glass-mark" disabled={!chosen.length} onClick={() => onDone(chosen)} aria-label={t("Done")}>
            <Glyph name="tick" size={18} color={chosen.length ? "#fff" : "#555"} /></button>}>
      <input className="meet-field pick-search" placeholder={t("Search")} value={q} onChange={(e) => setQ(e.target.value)} aria-label={t("Search")} />
      <Section foot={foot}>
        {shown.map((r) => (
          <button key={r.ref} className="set-row pick-row" onClick={() => flip(r.ref)} aria-label={`${t("Choose")}: ${chatName(r.name)}`}>
            <Face chat={r.ref} version={r.face} size={40} />
            <span className="row-title">{chatName(r.name)}</span>
            <span className={"pick-tick" + (chosen.includes(r.ref) ? " on" : "")}>{chosen.includes(r.ref) ? "✓" : ""}</span>
          </button>
        ))}
      </Section>
    </Page>
  );
}

/** A NEW GROUP (iOS: the people, then the name). */
export function GroupCreate({ onClose, onMade }) {
  const [people, setPeople] = useState(null);
  const [title, setTitle] = useState("");
  const [file, setFile] = useState(null);
  const [photo, setPhoto] = useState(null);   // {bytes, url}: the face the group is born with
  const picker = useRef(null);
  if (!people) return <Pick title={t("New Group")} onClose={onClose} onDone={setPeople} />;
  if (file) return <Crop file={file} {...GROUP_FACE} onCancel={() => setFile(null)}
                         onDone={(bytes) => { setPhoto({ bytes, url: URL.createObjectURL(new Blob([bytes], { type: "image/jpeg" })) }); setFile(null); }} />;
  const make = async () => {
    const chat = await invoke("group_create", { title, pipes: people });
    if (photo) await invoke("group_face", photo.bytes, { headers: { chat } });
    onMade(chat);
  };
  return (
    <Page title={t("New Group")} onClose={() => setPeople(null)} back
          right={<button className="glass-mark" disabled={!title.trim()} onClick={make} aria-label={t("Done")}>
            <Glyph name="tick" size={18} color={title.trim() ? "#fff" : "#555"} /></button>}>
      <input ref={picker} type="file" accept="image/*" hidden onChange={(e) => { if (e.target.files[0]) setFile(e.target.files[0]); e.target.value = ""; }} />
      <div className="me-head">
        {photo ? <div className="face" style={{ width: 60, height: 60, cursor: "pointer" }} onClick={() => picker.current.click()}><img src={photo.url} alt="" className="face-photo" /></div>
          : <GroupFace size={60} onClick={() => picker.current.click()} />}
        <button className="link-button" onClick={() => picker.current.click()}>{photo ? t("Change photo") : t("Choose photo")}</button>
      </div>
      <Section head={members(people.length + 1)}>
        <input className="set-field" placeholder={t("Group Name")} value={title} maxLength={64} autoFocus aria-label={t("Group Name")}
               onChange={(e) => setTitle(e.target.value)} onKeyDown={(e) => e.key === "Enter" && title.trim() && make()} />
      </Section>
    </Page>
  );
}

/** A NEW CHANNEL IN THREE STEPS (iOS MontanaChannel: MTChannelIntroStep, MTChannelInfoStep, MTChannelSubscribersStep): what a
 *  channel is; its face, name and description; the subscribers, each chosen among the people this machine writes with. */
export function ChannelCreate({ onClose, onMade }) {
  const [step, setStep] = useState("intro");
  const [title, setTitle] = useState("");
  const [about, setAbout] = useState("");
  const [file, setFile] = useState(null);
  const [photo, setPhoto] = useState(null);
  const picker = useRef(null);
  const make = async (pipes) => {
    const chat = await invoke("group_create", { title, pipes, kind: "c", about });
    if (photo) await invoke("group_face", photo.bytes, { headers: { chat } });
    onMade(chat);
  };
  if (step === "pick") return <Pick title={t("Add Subscribers")} onClose={() => setStep("info")} onDone={make}
                                    foot={t("A post rides the pipe of each person, so only the people you write with are listed.")} />;
  if (file) return <Crop file={file} {...GROUP_FACE} onCancel={() => setFile(null)}
                         onDone={(bytes) => { setPhoto({ bytes, url: URL.createObjectURL(new Blob([bytes], { type: "image/jpeg" })) }); setFile(null); }} />;
  if (step === "intro") {
    return (
      <Page title={t("New Channel")} onClose={onClose}>
        <div className="channel-intro">
          <Glyph name="antenna" size={64} color="#fff" />
          <div className="channel-intro-title">{t("What is a Channel?")}</div>
          <div className="channel-intro-text">{t("Channels are a new tool for broadcasting your messages to large audiences.")}</div>
          <button className="primary-wide" onClick={() => setStep("info")}>{t("Create Channel")}</button>
        </div>
      </Page>
    );
  }
  return (
    <Page title={t("New Channel")} onClose={() => setStep("intro")} back
          right={<button className="glass-mark" disabled={!title.trim()} onClick={() => setStep("pick")} aria-label={t("Done")}>
            <Glyph name="tick" size={18} color={title.trim() ? "#fff" : "#555"} /></button>}>
      <input ref={picker} type="file" accept="image/*" hidden onChange={(e) => { if (e.target.files[0]) setFile(e.target.files[0]); e.target.value = ""; }} />
      <div className="me-head">
        {photo ? <div className="face" style={{ width: 60, height: 60, cursor: "pointer" }} onClick={() => picker.current.click()}><img src={photo.url} alt="" className="face-photo" /></div>
          : <GroupFace size={60} onClick={() => picker.current.click()} />}
        <button className="link-button" onClick={() => picker.current.click()}>{photo ? t("Change photo") : t("Choose photo")}</button>
      </div>
      <Section>
        <input className="set-field" placeholder={t("Channel Name")} value={title} maxLength={64} autoFocus aria-label={t("Channel Name")}
               onChange={(e) => setTitle(e.target.value)} onKeyDown={(e) => e.key === "Enter" && title.trim() && setStep("pick")} />
      </Section>
      <Section foot={t("You can provide an optional description for your channel.")}>
        <textarea className="set-field" rows={3} placeholder={t("Description (Optional)")} value={about} maxLength={255}
                  aria-label={t("Description (Optional)")} onChange={(e) => setAbout(e.target.value)} />
      </Section>
    </Page>
  );
}

/** THE GROUP'S PAGE (iOS MTGroupPage): its face and title, how many; the members (the owner first, roles as chips); the
 *  owner adds, removes and renames; a member leaves; the owner deletes the group for everyone. */
export function GroupPage({ chat, onClose, onGone }) {
  const [g, setG] = useState(null);
  const [adding, setAdding] = useState(false);
  const [promoting, setPromoting] = useState(null);   // the person whose administrator's rights are open (iOS promote)
  const [reactions, setReactions] = useState(false);   // the channel's «Reactions» page
  const [asking, setAsking] = useState(false);   // the people who asked by the link
  const [ask, setAsk] = useState(null);       // {kind: "remove"|"leave"|"delete", seat, name}
  const [renaming, setRenaming] = useState(null);
  const [file, setFile] = useState(null);
  const [link, setLink] = useState(null);       // the group's link (iOS inviteLink), asked of the owner's machine
  const [rights, setRights] = useState(false);
  const [copied, setCopied] = useState(false);
  const picker = useRef(null);
  const look = () => invoke("group_info", { chat }).then(setG);
  useEffect(() => { invoke("group_link", { chat, reset: false }).then(setLink).catch(() => {}); }, [chat]);
  useEffect(() => { look(); }, [chat]);
  useChanged(look);
  if (!g) return null;
  if (file) return <Crop file={file} {...GROUP_FACE} onCancel={() => setFile(null)}
                         onDone={async (bytes) => { setFile(null); await invoke("group_face", bytes, { headers: { chat } }); setTimeout(look, 300); }} />;
  if (rights) return <Permissions chat={chat} g={g} onClose={() => { setRights(false); setTimeout(look, 500); }} />;
  if (asking) return <Requests chat={chat} g={g} onClose={() => { setAsking(false); setTimeout(look, 500); }} />;
  if (reactions) return <ChannelReactions chat={chat} g={g} onClose={() => { setReactions(false); setTimeout(look, 500); }} />;
  if (promoting) return <AdminRights chat={chat} g={g} p={promoting} onClose={() => { setPromoting(null); setTimeout(look, 500); }} />;
  const kicks = g.owner || (g.admin && (g.rights || []).includes("bu"));   // the owner, or an administrator with «Ban Users»
  if (adding) return <Pick title={t("Add Members")} onClose={() => setAdding(false)}
                           onDone={(p) => { invoke("group_add", { chat, pipes: p }); setAdding(false); setTimeout(look, 500); }} />;
  return (
    <Page title="" onClose={onClose} back
          right={g.owner && !g.left ? <button className="glass-mark" onClick={() => setRenaming(g.title)} aria-label={t("Edit")}><Glyph name="pencil" size={18} color="var(--bar-glyph)" /></button> : null}>
      <input ref={picker} type="file" accept="image/*" hidden onChange={(e) => { if (e.target.files[0]) setFile(e.target.files[0]); e.target.value = ""; }} />
      <div className="me-head">
        <GroupFace size={100} chat={chat} version={g.face} onClick={g.owner && !g.left ? () => picker.current.click() : undefined} />
        {renaming != null ? (
          <input className="set-field rename" value={renaming} maxLength={64} autoFocus aria-label={t("Group Name")}
                 onChange={(e) => setRenaming(e.target.value)}
                 onKeyDown={(e) => { if (e.key === "Enter" && renaming.trim()) { invoke("group_rename", { chat, title: renaming }); setRenaming(null); setTimeout(look, 500); } }} />
        ) : <div className="me-bubble name">{g.title}</div>}
        <div className="row-caption">{g.removed ? t("you were removed from the group") : g.left ? t("you have left the group") : people(g.kind, g.count)}</div>
        {g.about && <div className="row-caption group-about">{g.about}</div>}
      </div>
      {(g.owner || g.admin) && !g.left && link && (
        <Section head={t("Invite Link")} foot={g.kind === "c" ? t("Anyone who follows this link will be able to join your channel.")
                                                              : t("Anyone who follows this link will be able to join your group.")}>
          <div className="set-row group-link" aria-label={t("Invite Link")}><span className="row-title">{link}</span></div>
          <button className="set-row accent" onClick={() => { invoke("copy_text", { text: link }); setCopied(true); setTimeout(() => setCopied(false), 1500); }}>
            <Glyph name="copy" size={18} color="#fff" /><span className="row-title">{copied ? t("Link copied") : t("Copy Link")}</span>
          </button>
          {g.owner && (
            <button className="set-row" onClick={() => setAsk({ kind: "revoke" })}>
              <span className="row-title red">{t("Revoke Link")}</span>
            </button>
          )}
        </Section>
      )}
      {g.owner && !g.left && link && g.kind === "g" && (
        <Section foot={g.approval ? t("New users will be able to join the group only after having been approved by the admins.")
                                  : t("New users will be able to join the group without being approved by the admins.")}>
          <Toggle title={t("Request Admin Approval")} on={!!g.approval}
                  onChange={(on) => { invoke("group_set_approval", { chat, on }); setG({ ...g, approval: on }); }} />
          <button className="set-row" onClick={() => setAsking(true)}>
            <span className="row-title">{t("Member Requests")}</span>
            <span className="row-value">{(g.requests || []).length}</span>
          </button>
        </Section>
      )}
      {g.kind === "g" && g.owner && !g.left && (
        <Section>
          <button className="set-row" onClick={() => setRights(true)}>
            <Glyph name="shield" size={18} color="#fff" /><span className="row-title">{t("Permissions")}</span>
            <span className="row-value">{RIGHTS.length - (g.barred || []).length}/{RIGHTS.length}{g.slow ? ` · ${slowWord(g.slow)}` : ""}</span>
          </button>
        </Section>
      )}
      {g.kind === "g" && g.owner && !g.left && (
        <Section head={t("History for new members")}
                 foot={g.history ? t("New members will see messages that were sent before they joined.") : t("New members won't see earlier messages.")}>
          <div className="slow-steps" role="radiogroup" aria-label={t("History for new members")}>
            {[[true, "Visible"], [false, "Hidden"]].map(([on, word]) => (
              <button key={word} role="radio" aria-checked={!!g.history === on} className={"slow-step" + (!!g.history === on ? " on" : "")}
                      onClick={() => { invoke("group_set_history", { chat, visible: on }); setG({ ...g, history: on }); }}>{t(word)}</button>
            ))}
          </div>
        </Section>
      )}
      {g.kind === "c" && g.owner && !g.left && (
        <Section foot={t("Allow subscribers to react to channel posts.")}>
          <Toggle title={t("Sign Messages")} on={!!g.signs} onChange={(on) => { invoke("channel_set", { chat, signs: on, reacts: g.reacts, talks: g.talks }); setG({ ...g, signs: on }); }} />
          <Toggle title={t("Allow Reactions")} on={!!g.reacts} onChange={(on) => { invoke("channel_set", { chat, signs: g.signs, reacts: on, talks: g.talks }); setG({ ...g, reacts: on }); }} />
          {g.reacts && (
            <button className="set-row" onClick={() => setReactions(true)}>
              <span className="row-title">{t("Reactions")}</span>
              <span className="row-value">{(g.react_list || []).length || t("All")}</span>
            </button>
          )}
          <Toggle title={t("Allow Comments")} on={!!g.talks} caption={t("Subscribers comment under every post. The comments ride the channel itself, phone to phone.")}
                  onChange={(on) => { invoke("channel_set", { chat, signs: g.signs, reacts: g.reacts, talks: on }); setG({ ...g, talks: on }); }} />
        </Section>
      )}
      {g.owner && !g.left && (
        <Section>
          <button className="set-row accent" onClick={() => picker.current.click()}>
            <Glyph name="photo" size={18} color="#fff" /><span className="row-title">{g.face ? t("Change photo") : t("Choose photo")}</span>
          </button>
        </Section>
      )}
      <Section>
        {g.owner && !g.left && <button className="set-row accent" onClick={() => setAdding(true)}><Glyph name="plus" size={18} color="var(--blue)" /><span className="row-title" style={{ color: "var(--blue)" }}>{g.kind === "c" ? t("Add Subscribers") : t("Add Member")}</span></button>}
        {g.people.map((p) => (
          <div key={p.seat} className="set-row member" onContextMenu={(e) => { e.preventDefault(); if (g.owner && !p.owner && !p.me) setAsk({ kind: "remove", seat: p.seat, name: p.name }); }}>
            <span className="member-name" style={{ color: p.me ? "#fff" : tint(`gm:${chat.slice(4)}/${p.seat}`) }}>{p.name || t("Member")}</span>
            {p.owner && <span className="role owner">{t("owner")}</span>}
            {p.admin && <span className="role admin">{p.rank || t("admin")}</span>}
            {g.owner && !p.owner && !p.me && (
              <button className="unblock" onClick={() => setPromoting(p)}>{p.admin ? t("Edit Admin Rights") : t("Promote to Admin")}</button>
            )}
            {g.owner && p.admin && !p.owner && !p.me && (
              <button className="unblock" onClick={() => { invoke("group_set_admin", { chat, seat: p.seat, on: false, taken: [], rank: "" }); setTimeout(look, 500); }}>
                {t("Dismiss Admin")}
              </button>
            )}
            {kicks && !p.owner && !p.me && (g.owner || !p.admin) && (
              <button className="unblock" onClick={() => setAsk({ kind: "remove", seat: p.seat, name: p.name })}>{t("Remove")}</button>
            )}
          </div>
        ))}
      </Section>
      {!g.left && (
        <Section>
          <button className="set-row" onClick={() => setAsk({ kind: g.owner ? "delete" : "leave" })}>
            <span className="row-title red center">{g.kind === "c" ? (g.owner ? t("Delete Channel") : t("Leave Channel")) : g.owner ? t("Delete Group") : t("Leave Group")}</span>
          </button>
        </Section>
      )}
      {ask && (
        <div className="alert-shade" onClick={() => setAsk(null)}>
          <div className="alert wide" role="alertdialog" onClick={(e) => e.stopPropagation()}>
            <div className="alert-title">
              {ask.kind === "revoke" ? t("Are you sure you want to revoke this link? Once you do, no one will be able to join the group using it.")
                : ask.kind === "remove" ? t("Remove from group?") : ask.kind === "delete"
                ? (g.kind === "c" ? t("Wait! Deleting this channel will remove all members and all messages will be lost. Delete the channel anyway?")
                                  : t("Are you sure you want to delete the group %@ and all its messages for all members?", { "%@": g.title }))
                : g.kind === "c" ? t("Are you sure you want to leave the channel %@?", { "%@": g.title })
                : t("Are you sure you want to leave and delete %@?", { "%@": g.title })}
            </div>
            <button className="red" onClick={() => {
              if (ask.kind === "revoke") { invoke("group_link", { chat, reset: true }).then(setLink); setAsk(null); return; }
              if (ask.kind === "remove") invoke(g.owner ? "group_remove" : "group_kick", { chat, seat: ask.seat });
              else invoke("group_leave", { chat });
              setAsk(null);
              if (ask.kind !== "remove") onGone?.(); else setTimeout(look, 500);
            }}>{ask.kind === "revoke" ? t("Revoke Link") : ask.kind === "remove" ? t("Remove") : ask.kind === "delete" ? (g.kind === "c" ? t("Delete Channel") : t("Delete for all")) : g.kind === "c" ? t("Leave Channel") : t("Leave Group")}</button>
            <button className="bold" onClick={() => setAsk(null)}>{t("Cancel")}</button>
          </div>
        </div>
      )}
    </Page>
  );
}
