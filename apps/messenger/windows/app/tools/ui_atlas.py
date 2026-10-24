# THE UI ATLAS'S BOOKS (the owner's word 24.10.2026 11:3x): docs/UI-ATLAS.md is the map of iOS Montana (every screen, element,
# state and way, a lasting ID each); docs/UI-CHECKLIST.md and docs/UI-PROGRESS.md are drawn from its rows, never written apart,
# so every number the owner reads counts real rows.
#
# usage: python3 -B tools/ui_atlas.py merge   -- once: docs/ui-atlas/NN-*.md (the sections the inventory wrote) -> docs/UI-ATLAS.md,
#                                                the parts removed
#        python3 -B tools/ui_atlas.py         -- after every pass: the registry in the atlas, the checklist (the statuses set by hand
#                                                kept by ID) and the progress
#        python3 -B tools/ui_atlas.py set ID key=value ...   -- one row changed by what a check proved, then the books drawn again:
#                                                win / windows / notes -- the atlas's cells; 3..9, lich, ev -- the checklist's
import glob, os, re, sys

DOCS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs")
ATLAS = os.path.join(DOCS, "UI-ATLAS.md")
CHECK = os.path.join(DOCS, "UI-CHECKLIST.md")
PROGRESS = os.path.join(DOCS, "UI-PROGRESS.md")
ID = re.compile(r"^[A-Z]+-\d{3}$")
CELL = re.compile(r"(?<!\\)\|")
REF = "3926188"

def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()

def write(p, s):
    with open(p, "w", encoding="utf-8", newline="") as f:   # Python on Windows would write CRLF
        f.write(s)

def cells(line):
    parts = [c.strip() for c in CELL.split(line.strip())]
    return parts[1:-1] if len(parts) >= 2 else []

def rows_of(text):
    """the atlas's rows in order: (section title, cells); a section opens with its «## » heading"""
    section, out = None, []
    for line in text.splitlines():
        if line.startswith("## "):
            section = line[3:].strip()
        if line.startswith("|"):
            c = cells(line)
            if c and ID.match(c[0]):
                if len(c) != 9:
                    sys.exit(f"{c[0]}: {len(c)} cells, the atlas holds 9")
                out.append((section, c))
    return out

def short(s, n=64):
    s = re.sub(r"`|\*\*", "", s)
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"

# THE SHARED ELEMENTS (the owner's stage 7): one place in Windows for each, corrected there and then checked on every screen that
# wears it; the rows that wear the element are found by their kind or by its words anywhere in the row
REGISTRY = [
    ("Плашка-стекло: кнопки, капсулы, панель (Liquid Glass; до iOS 26 — материал с ободком 0.28)",
     "MontanaShapes.swift:120 `MontanaOctagonFace`, :294 `MontanaOctagonButtonStyle`, :54 `MontanaLongOctagon`",
     "app.css `--glass`, `--glass-rim`; chats.css `.glass-mark`, `.title-bubble`",
     ["octagon", "glass-mark", "title-bubble", "liquid glass", "glasseffect"]),
    ("Поле-стекло", "MontanaShapes.swift:240 `MontanaFieldGlass`", "app.css `--glass-field`; chats.css `.compose-field`",
     ["fieldglass", "compose-field"]),
    ("Метки страниц и панели: назад, закрыть, готово, правка",
     "MontanaShapes.swift:1252 `MontanaBackMark`, :1240 `MontanaCloseMark`, :1234 `MontanaDoneMark`, :1246 `MontanaEditMark`, :1124 `MontanaBarMark`",
     "TopBar.jsx:15 `Glyph`; chats.css `.glass-mark`",
     ["backmark", "closemark", "donemark", "editmark", "barmark"]),
    ("Панель времени: значки и шайба", "MontanaShapes.swift:334 `MTBarGlyphStyle`, :350 `MTBarPuck`",
     "TopBar.jsx; app.css `.bar-plate`", ["mtbarglyph", "mtbarpuck", "topbar.jsx", "bar-plate"]),
    ("Материалы ultraThin / thin / regular", "SwiftUI `.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`",
     "pages.css `--ultrathin`, `--thin-material`, `--regular-material` (конец файла)",
     ["kind:material", "material"]),
    ("Аватары и метки баланса/уровня у них",
     "MontanaShapes.swift:543 `AvatarCircle`, :469 `MTSelfFace`, :630 `MTAvatarBadgeDecoration`; MontanaConversation.swift:4839 `MontanaChatFace`",
     "Chats.jsx:98 `Face`", ["avatarcircle", "mtselfface", "avatarbadge", "chatface", "аватар"]),
    ("Страница и её заголовок", "SwiftUI `NavigationStack` / страницы поверх (см. строки)",
     "Settings.jsx:30 `Page`; pages.css `.page-over`, `page-push-in`", ["kind:page", "settings.jsx:30", "page-over"]),
    ("Строка списка", "MontanaChatsList.swift:1936 `SwipeChatRow`", "app.css `.row` (`--row`, `--side`, `--face`, `--gap`)",
     ["swipechatrow", "строка списка", "app.css:111"]),
    ("Меню по удержанию и контекстные меню", "MontanaMessageMenu.swift",
     "chats.css `.menu-shade`, `.letter-menu`, `.menu-rows`, `.answers-row`; Conversation.jsx:1434 `MenuRow`",
     ["kind:menu", "messagemenu", "menu-shade", "letter-menu", "menurow"]),
    ("Алерты и листы действий", "SwiftUI `.alert`, `.confirmationDialog`, `.sheet`",
     "app.css `.alert`, `.sheet`; chats.css `.action-sheet`, `.action-group`", ["kind:alert", "kind:sheet"]),
    ("Поиск", "MontanaChatsList.swift:30 `MTSearchField`", "App.jsx:213 `.search`", ["mtsearchfield", "поле поиска", "строка поиска"]),
    ("Монеты: спиннер и знак", "MontanaChatsList.swift:99 `MontanaCoinSpinner`", "Coin.jsx:12 `CoinSpinner`",
     ["coinspinner", "спиннер"]),
    ("Кнопка медиа в строке ввода", "MontanaShapes.swift:862 `MTComposeMark`", "chats.css `.media-key`", ["mtcomposemark", "media-key", "кнопка медиа"]),
    ("Кнопка «к новым» в ленте", "MontanaConversation.swift:371 `ScrollDownButton`", "нет (CONV-033)", ["scrolldownbutton"]),
    ("Полосы прокрутки", "системные (UIScrollView)", "app.css:44–48 `::-webkit-scrollbar`", ["scrollindicator", "scrollbar", "полос прокрутки", "полоса прокрутки"]),
    ("Появление и закрытие, переходы страниц", "SwiftUI `.transition`, `.animation`",
     "pages.css `page-push-in/out`, `page-sheet-in/out`, `shade-in`, `alert-in`; chats.css `action-rise`", ["kind:transition", "kind:animation"]),
]

def registry(rows):
    out = ["<!-- registry: строки найдены скриптом tools/ui_atlas.py по виду и словам строки; правится в REGISTRY скрипта -->", "",
           "| Общий элемент | iOS | Windows (одно место) | Строки атласа |", "|---|---|---|---|"]
    for name, ios, win, words in REGISTRY:
        ids = [c[0] for _, c in rows if any(c[1] == w[5:] if w.startswith("kind:") else w in " ".join(c[2:]).lower() for w in words)]
        shown = ", ".join(ids[:40]) + (f" … (+{len(ids) - 40})" if len(ids) > 40 else "")
        out.append(f"| {name} | {ios} | {win} | {shown or '—'} |")
    out += ["", "Строки вида `component` и `material` — тоже общие элементы; их список — в UI-CHECKLIST.md (столбец «Вид»).",
            "<!-- /registry -->"]
    return "\n".join(out)

HEAD = f"""# Атлас интерфейса Montana

Главный документ сверки Montana Windows с оригиналом (слово владельца 24.10.2026 11:3x, звенья №561–606). Атлас — дерево экранов
и граф переходов iOS Montana **с точки зрения человека**: каждый экран, страница, лист, алерт, меню, кнопка, жест, поле,
переключатель, состояние, переход, анимация и материал — одна строка с постоянным ID.

- **Эталон:** iOS Montana, GitHub `efir369999/montana_messenger`, `main`, коммит **`{REF}`** (сборка 2305). Обновление iOS сначала
  записывается отдельной записью в «Изменения эталона» ниже (что изменилось, какие ID затронуты), и только потом меняет строки.
- **Пути:** iOS — от `apps/messenger/ios/Code/Montana/`, Windows — от `app/`.
- **Контроль:** `docs/UI-CHECKLIST.md` (статусы каждой строки) и `docs/UI-PROGRESS.md` (сводка) строятся из этого файла скриптом
  `python3 -B app/tools/ui_atlas.py`; статусы, поставленные вручную, скрипт сохраняет по ID.
- **Данные личности** (слово владельца 24.10.2026 11:58, `docs/IDENTITY-SYNC.md`): у каждого элемента, который создаёт данные,
  проверяется ещё и то, что эти данные доступны другим устройствам той же личности так, как это делает iOS (столбец «Личность»).
- **Доказательства:** `docs/ui-evidence/` (снимки Windows тестовыми личностями; ни 24 слов, ни ключей, ни личной переписки).

## Как читать строки

`| ID | Вид | Название | Родитель | Откуда → куда | iOS | Windows | Win | Заметки |`

- **ID** — `ПРЕФИКС-NNN`, по порядку внутри раздела, не переиспользуется; новая строка берёт следующий свободный номер.
  Один экран из разных путей — одна строка, остальные ссылаются на её ID.
- **Вид:** screen · page · sheet · alert · menu · item · button · field · toggle · gesture · state · transition · animation ·
  material · component.
- **Win** — что есть в коде Windows сейчас: yes · partial · missing · n-a (нет такой возможности платформы) · unclear. Это не
  проверка: проверенное отмечается только в контрольной таблице.
- «нужен iPhone» в заметках — поведение, которое по исходникам не установить (ощущение пальца, кадры, тактильный отклик).

## Префиксы

| Раздел | Префиксы |
|---|---|
| 1. Запуск, вход и личности | LAUNCH, ID, SEAT, LOCK |
| 2. Главный экран и вкладка чатов | MAIN, PANEL, DRAWER, LIB, CHATS, FOLDER |
| 3. Открытая беседа | CONV, MSG, COMPOSE, FLOW |
| 4. Медиа и вложения | MEDIA, PICK, VIEW, EMOJI, GALLERY |
| 5. Звонки | CALL, ROOM, CALLS |
| 6. Люди и сообщества | CONTACTS, PEER, PROFILE, GROUP, CHANNEL |
| 7. Стена, музыка, шахматы, визитка, пароли | WALL, MUSIC, CHESS, CARD, PASS |
| 8. TimeCoin, настройки и сеть | WALLET, SET, NET |

## Изменения эталона

- 24.10.2026: опись по `{REF}` (сборка 2305) — восемь разделов, только чтение исходников (субагенты, звенья №586–605, 627).
"""

def merge():
    parts = sorted(glob.glob(os.path.join(DOCS, "ui-atlas", "0*.md")))
    if len(parts) != 8:
        sys.exit(f"{len(parts)} parts, the atlas has 8")
    texts = [read(p).strip() + "\n" for p in parts]
    rows = rows_of("\n".join(texts))
    ids = [c[0] for _, c in rows]
    dup = sorted({i for i in ids if ids.count(i) > 1})
    if dup:
        sys.exit("repeated IDs: " + ", ".join(dup))
    top = ["## Верхнее дерево", ""]
    for t in texts:
        title = t.splitlines()[0][3:].strip()
        top.append(f"- **{title}**")
        tree = t.split("### Дерево", 1)[1].split("### Строки", 1)[0]
        top += ["  " + l for l in tree.splitlines() if l.startswith("- ")]
    body = HEAD + "\n" + "\n".join(top) + "\n\n## Реестр общих элементов\n\n" + registry(rows) + "\n\n" + "\n".join(texts)
    body = body.replace("(в нём незакоммичена прокрутка полосы папок колесом, Folders.jsx:103-115)",
                        "(прокрутка полосы папок колесом — Folders.jsx:103-115, коммит 995acdf)")
    write(ATLAS, body)
    for p in parts:
        os.remove(p)
    print(f"atlas: {len(rows)} rows in 8 sections; parts removed")

# THE CHECKLIST'S COLUMNS (the owner's stage 3, nine statuses, and the identity's data from 11:58)
COLS = ["ID", "Название", "Вид", "1 iOS", "2 Win", "3 Функция", "4 Визуал", "5 Анимация", "6 Смежные", "7 Различия",
        "8 Регрессия", "Личность", "9 Итог", "Доказательства / причина"]
HAND = COLS[5:]
WIN = {"yes": "да", "partial": "частично", "missing": "нет", "n-a": "н/п", "unclear": "?"}
FINAL = ["не начато", "исследовано", "частично", "по исходникам", "визуально", "заблокировано"]

LEGEND = """# Контрольная таблица атласа

Строится из `docs/UI-ATLAS.md` скриптом `python3 -B app/tools/ui_atlas.py`: столбцы 1–2 — из атласа, остальные ставятся
вручную по проверке и сохраняются скриптом по ID. Отмечать пункт можно только по проверке, не по наличию кода или сборке.

- **1 iOS** — найдено в iOS (источник в атласе): да / нет. **2 Win** — код в Windows: да / частично / нет / н/п / ?.
- **3 Функция, 4 Визуал, 5 Анимация, 6 Смежные, 8 Регрессия:** `—` не проверено · `да` подтверждено (ссылка в «Доказательства») ·
  `код` сверено по исходникам iOS, сравнение с iPhone не выполнено · `iPhone` нужен настоящий iPhone · `нет` проверка не прошла.
- **7 Различия:** `—` не сверено · `нет` не осталось · `есть` осталось (что — в «Доказательства»).
- **Личность** (данные, созданные этим элементом, на других устройствах той же личности; `docs/IDENTITY-SYNC.md`): `·` не
  исследовано · `—` элемент данных не создаёт · `лок` по iOS данные остаются на устройстве · `да` проверено на двух устройствах ·
  `частично` · `нет` iOS переносит, Windows нет.
- **9 Итог:** не начато · исследовано · частично · по исходникам · визуально (подтверждено визуально) · заблокировано.
- **Доказательства / причина:** тест (`tools/*.ps1`), снимок (`docs/ui-evidence/…`), коммит, причина блокировки.

"""

def check():
    rows = rows_of(read(ATLAS))
    if not rows:
        sys.exit("no rows in the atlas")
    kept = {}
    if os.path.exists(CHECK):
        for line in read(CHECK).splitlines():
            c = cells(line)
            if len(c) == len(COLS) and ID.match(c[0]):
                kept[c[0]] = c[5:]
    out = [LEGEND]
    section = None
    for sec, c in rows:
        if sec != section:
            section = sec
            out += ["", f"## {sec}", "", "| " + " | ".join(COLS) + " |", "|" + "---|" * len(COLS)]
        ios = "да" if c[5] and c[5] not in ("—", "-") and not c[5].startswith("нет в iOS") else "нет"
        hand = kept.get(c[0], ["—", "—", "—", "—", "—", "—", "·", "исследовано", ""])
        out.append("| " + " | ".join([c[0], short(c[2]).replace("|", "\\|"), c[1], ios, WIN.get(c[7], c[7] or "?")] + hand) + " |")
    write(CHECK, "\n".join(out) + "\n")
    text = read(ATLAS)
    if "<!-- registry" in text:
        a, rest = text.split("<!-- registry", 1)
        write(ATLAS, a + registry(rows) + rest.split("<!-- /registry -->", 1)[1])
    progress(rows)
    print(f"checklist: {len(rows)} rows, {len(kept)} kept by hand")

def progress(rows):
    table = {}
    for line in read(CHECK).splitlines():
        c = cells(line)
        if len(c) == len(COLS) and ID.match(c[0]):
            table[c[0]] = c
    hand = ("<!-- hand -->\n## Сейчас и дальше\n\n- **Проверяется сейчас:** —\n- **Следующий:** —\n\n"
            "## Главные оставшиеся различия\n\n—\n<!-- /hand -->")
    if os.path.exists(PROGRESS):
        old = read(PROGRESS)
        if "<!-- hand -->" in old:
            hand = "<!-- hand -->" + old.split("<!-- hand -->", 1)[1].split("<!-- /hand -->", 1)[0] + "<!-- /hand -->"
    def count(pred, part=None):
        return sum(1 for s, c in rows if (part is None or s == part) and pred(c, table[c[0]]))
    kinds = lambda *k: (lambda c, t: c[1] in k)
    # EVERY ID COUNTED ONCE (the owner's word 12:2x): the five states of the code part the rows without a remainder
    wins = [count(lambda c, t, w=w: t[4] == w) for w in ("да", "частично", "нет", "н/п", "?")]
    if sum(wins) != len(rows):
        sys.exit(f"the Windows column parts {sum(wins)} of {len(rows)} rows")
    done = lambda col: (lambda c, t: t[COLS.index(col)] == "да")
    lines = [
        "# Ход проверки по атласу", "",
        f"Все числа — подсчёт строк `docs/UI-CHECKLIST.md` (эталон iOS `{REF}`); пересчёт — `python3 -B app/tools/ui_atlas.py`.", "",
        "| Что | Строк |", "|---|---|",
        f"| Экраны (screen) / страницы (page) / листы (sheet) / алерты (alert) / меню (menu) | "
        f"{count(kinds('screen'))} / {count(kinds('page'))} / {count(kinds('sheet'))} / {count(kinds('alert'))} / {count(kinds('menu'))} |",
        f"| Действия: кнопки, пункты, поля, переключатели, жесты | {count(kinds('button', 'item', 'field', 'toggle', 'gesture'))} |",
        f"| Переходы (transition) | {count(kinds('transition'))} |",
        f"| Состояния, анимации, материалы, компоненты | {count(kinds('state'))}, {count(kinds('animation'))}, {count(kinds('material'))}, {count(kinds('component'))} |",
        f"| **Всего строк в карте** | **{len(rows)}** |",
        f"| Код в Windows (не проверка): да / частично / нет / н/п / неясно — сумма {sum(wins)} = все строки | "
        f"{' / '.join(str(n) for n in wins)} |",
        "| | н/п — у Windows нет такой возможности платформы или в iOS это мёртвый код; неясно — по коду не установить |",
        f"| Функционально проверено | {count(done('3 Функция'))} |",
        f"| Визуально сверено | {count(done('4 Визуал'))} (по исходникам: {count(lambda c, t: t[6] == 'код')}) |",
        f"| Анимации проверены | {count(done('5 Анимация'))} |",
        f"| Данные доступны другим устройствам личности (проверено) | {count(lambda c, t: t[11] == 'да')} |",
        f"| Полностью подтверждено (итог «визуально») | {count(lambda c, t: t[12] == 'визуально')} |",
        f"| Заблокировано | {count(lambda c, t: t[12] == 'заблокировано')} |",
        "", "## По разделам", "",
        "| Раздел | Строк | Win да | частично | нет | Функция | Визуал | Анимация | Итог: визуально | Заблокировано |",
        "|---|---|---|---|---|---|---|---|---|---|"]
    for part in dict.fromkeys(s for s, _ in rows):
        name = part.split(" (префиксы")[0]
        lines.append(f"| {name} | {count(lambda c, t: True, part)} | {count(lambda c, t: t[4] == 'да', part)} | "
                     f"{count(lambda c, t: t[4] == 'частично', part)} | {count(lambda c, t: t[4] == 'нет', part)} | "
                     f"{count(done('3 Функция'), part)} | {count(done('4 Визуал'), part)} | {count(done('5 Анимация'), part)} | "
                     f"{count(lambda c, t: t[12] == 'визуально', part)} | {count(lambda c, t: t[12] == 'заблокировано', part)} |")
    write(PROGRESS, "\n".join(lines) + "\n\n" + hand + "\n")

def set_row(rid, pairs):
    # the atlas's own cells first: what the Windows code now holds
    atlas_keys = {"windows": 6, "win": 7, "notes": 8}
    text = read(ATLAS)
    out, found = [], False
    for line in text.splitlines():
        c = cells(line) if line.startswith("|") else []
        if c and c[0] == rid:
            found = True
            for k, v in pairs:
                if k in atlas_keys:
                    c[atlas_keys[k]] = v
            line = "| " + " | ".join(c) + " |"
        out.append(line)
    if not found:
        sys.exit(f"{rid}: no such row in the atlas")
    write(ATLAS, chr(10).join(out) + chr(10))
    check()
    # then the checklist's hand columns, kept by ID from now on
    hand = {str(i): COLS.index(n) for i, n in [(3, "3 Функция"), (4, "4 Визуал"), (5, "5 Анимация"), (6, "6 Смежные"),
                                                  (7, "7 Различия"), (8, "8 Регрессия"), (9, "9 Итог")]}
    hand.update({"lich": COLS.index("Личность"), "ev": COLS.index("Доказательства / причина")})
    lines = []
    for line in read(CHECK).splitlines():
        c = cells(line) if line.startswith("|") else []
        if len(c) == len(COLS) and c[0] == rid:
            for k, v in pairs:
                if k in hand:
                    c[hand[k]] = v
            line = "| " + " | ".join(c) + " |"
        lines.append(line)
    write(CHECK, chr(10).join(lines) + chr(10))
    check()

if __name__ == "__main__":
    if sys.argv[1:] == ["merge"]:
        merge()
    if sys.argv[1:2] == ["set"] and len(sys.argv) > 3:
        set_row(sys.argv[2], [a.split("=", 1) for a in sys.argv[3:]])
    else:
        check()
