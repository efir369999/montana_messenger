import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t, locale } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { Page, Section } from "./Settings.jsx";

/** THE QUESTIONS OF THIS BUILD (iOS MTQuestionsPage, 17.10.2026): the answers about levels, the fabric of time, coins, the words and
 *  privacy -- iOS 2251's own words, in English and in their Russian -- each question opening its answer on a page of its own (iOS
 *  MTAnswerPage); at the foot the site's questions and the open specification and code. */
const TOPICS = [
 {
  "title": "Levels",
  "icon": "trianglePath",
  "items": [
   {
    "q": "What is the Global level?",
    "a": "Your Global level is the lowest of three levels: the level of the chain of the person, which grows with your time on the network, the level of π, which grows with the coins you hold, and the Fabric of Time, which stands on the people you write to and call regularly in the last two weeks. You see it in TimeCoin, on the TimeChain page, and in Settings, under Access by level."
   },
   {
    "q": "How does the chain of the person count my time?",
    "a": "A second counts while Montana is open on the screen of one of your devices and a Montana node answers it. The second is read from the node, never from the clock of your phone. Each level doubles the seconds of the one before: 1 second is level 0, 2 seconds level 1, 4 seconds level 2, then 8, 16, 32 and on. When you leave the network, your level stays, and nothing is added until you return."
   },
   {
    "q": "What is the level of π?",
    "a": "It is the level of your wallet: how many first digits of π your balance reaches. 3 coins is level 1, 31 coins level 2, 314 coins level 3, then 3141, 31415 and on, up to 19 digits. Below 3 coins the level is 0. It is the one level you lower yourself: it falls when your balance falls."
   },
   {
    "q": "What do the levels open?",
    "a": "Each level opens functions of Montana. Level 7 opens Forbid deletion on my phone: a message your correspondent deletes for everyone stays on your phone, and their phone is told so. Level 7 also opens Record calls: calls are recorded by themselves on your phone and sent to the call's chat after your first consent. Level 8 opens your own node: a machine you own joins the Montana network through this app. All of them are in Settings, under Access by level."
   },
   {
    "q": "Can I record a call below level 7?",
    "a": "Yes. On every level a call can be recorded by the record button on the call screen, unless your correspondent's switch holds. From level 7 calls are recorded by themselves once you agree the first time, and you can turn it off in Settings, under Access by level."
   },
   {
    "q": "Who can record a call with me?",
    "a": "While your Record calls switch in Access by level is off, and below level 7 it stands off, a correspondent whose Global level is not above yours cannot record your calls: neither by themselves nor by the record button, which they do not see. A correspondent with a higher level records on their side only; your computer records nothing, and the chat is told that the call is being recorded. A version of Montana that does not say the switch forbids nothing."
   },
   {
    "q": "Who sends the recording to the chat?",
    "a": "In a one-to-one call the caller sends the recording to the chat. When the caller does not record, the one who answered sends it, so a recorded call always reaches the chat, once."
   },
   {
    "q": "Can I take my copy back from my node below level 8?",
    "a": "Yes. Setting up your node and sending copies to it open at level 8. Taking your copy back from it is open on every level."
   }
  ]
 },
 {
  "title": "Fabric of Time",
  "icon": "link",
  "items": [
   {
    "q": "What is the Fabric of Time?",
    "a": "The third level your Global level is set by: the people you write to and call regularly, each weighed by the level their own time and wallet give them. Your Global level is the lowest of the three, so the Fabric of Time can lower it and never raises it."
   },
   {
    "q": "What counts as an exchange?",
    "a": "Anything you and a person send each other that stands in your conversation: words, voice and video messages, photos, files, stickers and GIFs, coin transfers, the moves of a game, and a call in which each phone received the other's voice for at least 60 seconds. Receipts, typing and presence do not count, and neither does a group."
   },
   {
    "q": "When does a person's phone sign for me?",
    "a": "When a word of yours reaches their phone and they wrote to you themselves in the last 7 days, their phone signs, once a day at most, that your word reached it: the minute it arrived, the hash the fingerprint of your conversation is read from, and their own ceiling. It gives the signature to you alone, inside your conversation. A person who only writes and is never answered receives none."
   },
   {
    "q": "Who is a regular correspondent?",
    "a": "A person from whom your phone holds a signature in each of the last two weeks: the newer 7 days and the 7 before them. The window slides with the clock of the network; there are no fixed weeks. People are told apart by the key their signatures are made with, which their 24 words give for your conversation alone, not by anything they say about themselves."
   },
   {
    "q": "How is the level of the Fabric of Time counted?",
    "a": "Each regular correspondent stands at their ceiling: the lower of their two other levels, at its lowest in their signatures of the last two weeks. The level is the greatest number g for which at least g of your regular correspondents stand at g or above; a person far above g adds one, exactly as one at g does. It is counted again whenever a signature arrives or leaves the two weeks. Their own Fabric of Time does not enter it, so one person's dip never pulls a whole circle down."
   },
   {
    "q": "Does the Fabric of Time lower a newcomer?",
    "a": "Not in the first two weeks. From the first launch of this version on this phone with your 24 words, for 14 days the Fabric of Time stands at your ceiling, so your Global level follows your two other levels. TimeCoin and Access by level show the days left until the first count."
   },
   {
    "q": "What do the people I write to learn?",
    "a": "Your ceiling, inside the signatures your phone gives them, and nothing else of the Fabric of Time. A signature names your conversation by the hash its fingerprint is read from, which only the two of you can compute, and it is made with a key your 24 words give for that conversation alone. No key and no number in it is the same with two people, so two people you write to cannot tell from it that they speak with the same person."
   },
   {
    "q": "What do the nodes of the network learn?",
    "a": "Nothing they can read: signatures and ceilings ride inside your conversation, sealed for the other person, by the same road as your letters. Signatures stay on your phone for two weeks and then leave it."
   },
   {
    "q": "How does this version differ from the specification?",
    "a": "In four ways. A phone holds no window of the network's core, so the minute of a signature and the two weeks are read from the clock of the Montana nodes, learned from their answers. The signatures are not yet witnessed into the network; they stay on the phone that received them. Each of your devices with the same 24 words counts the signatures that reached it. And a signature names a conversation and is made with a key for that conversation alone, where the specification names the key of a person: this version knows people only by their conversations."
   },
   {
    "q": "Can false signatures lift a level?",
    "a": "No. The Fabric of Time only lowers: a person who states a false ceiling can at most spare someone a lowering and never lifts anyone above their own ceiling. One signature a day from one person is kept, the one with the lower ceiling, so two of their devices answering the same word weigh as one."
   }
  ]
 },
 {
  "title": "Coins and time",
  "icon": "wallet",
  "items": [
   {
    "q": "What is a Time Coin?",
    "a": "The coin of Montana, ticker $TCM. Its measure is time: one second is one coin, so an hour is 3600 coins. A billion coins is one Montana."
   },
   {
    "q": "Do coins mint while Montana is in the background?",
    "a": "Yes. When Montana leaves the screen, it keeps the moment it left. When you come back, every second you were away mints one coin, the same one coin a second as everywhere. At Global level 0 the time away mints nothing, and neither does it when the network did not answer Montana before it left the screen. Both moments are read from the Montana network, so turning the clock of the phone changes nothing."
   }
  ]
 },
 {
  "title": "Your words and devices",
  "icon": "key",
  "items": [
   {
    "q": "What if I use Montana on several devices?",
    "a": "The same 24 words on several devices are one person. Their seconds join: two devices open in the same second add one second, and once the devices have read each other's count, they show one chain of the person."
   },
   {
    "q": "What if I have several sets of 24 words?",
    "a": "Each set of 24 words is a separate person: its own seconds, its own wallet, its own levels. The levels of two persons are never added together, and coins move between them only by a real transfer."
   }
  ]
 },
 {
  "title": "Privacy",
  "icon": "lock",
  "items": [
   {
    "q": "Who sees my level?",
    "a": "The people you write with see your Global level beside your avatar. The nodes of the network keep a table of how many people stand on each level: for it Montana gives them a mark made from your 24 words and your Global level, never your balance, name or contacts. Your seconds online leave the phone only sealed under your 24 words: the nodes keep them for your other devices and cannot read them."
   }
  ]
 }
];
const RU = {
 "Levels": "Уровни",
 "What is the Global level?": "Что такое Глобальный уровень?",
 "Your Global level is the lowest of three levels: the level of the chain of the person, which grows with your time on the network, the level of π, which grows with the coins you hold, and the Fabric of Time, which stands on the people you write to and call regularly in the last two weeks. You see it in TimeCoin, on the TimeChain page, and in Settings, under Access by level.": "Ваш Глобальный уровень — наименьший из трёх уровней: уровня цепи Личности, который растёт с вашим временем в сети, уровня по Пи, который растёт с монетами, которые вы держите, и Ткани времени, которая стоит на людях, с которыми вы регулярно переписываетесь и созваниваетесь за последние две недели. Он виден в Монете Времени на странице TimeChain и в Настройках, в разделе Доступ по уровню.",
 "How does the chain of the person count my time?": "Как цепь Личности считает моё время?",
 "A second counts while Montana is open on the screen of one of your devices and a Montana node answers it. The second is read from the node, never from the clock of your phone. Each level doubles the seconds of the one before: 1 second is level 0, 2 seconds level 1, 4 seconds level 2, then 8, 16, 32 and on. When you leave the network, your level stays, and nothing is added until you return.": "Секунда засчитывается, пока Монтана открыта на экране одного из ваших устройств и ей отвечает узел Монтаны. Секунда берётся у узла, а не с часов телефона. Каждый уровень удваивает секунды предыдущего: 1 секунда — уровень 0, 2 секунды — уровень 1, 4 секунды — уровень 2, дальше 8, 16, 32 и так далее. Когда вы уходите из сети, уровень сохраняется, и ничего не прибавляется, пока вы не вернётесь.",
 "What is the level of π?": "Что такое уровень по Пи?",
 "It is the level of your wallet: how many first digits of π your balance reaches. 3 coins is level 1, 31 coins level 2, 314 coins level 3, then 3141, 31415 and on, up to 19 digits. Below 3 coins the level is 0. It is the one level you lower yourself: it falls when your balance falls.": "Это уровень вашего кошелька: сколько первых цифр числа Пи покрывает ваш баланс. 3 монеты — уровень 1, 31 монета — уровень 2, 314 монет — уровень 3, дальше 3141, 31415 и так далее, до 19 цифр. Меньше 3 монет — уровень 0. Это единственный уровень, который вы понижаете сами: он падает, когда падает баланс.",
 "What do the levels open?": "Что открывают уровни?",
 "Each level opens functions of Montana. Level 7 opens Forbid deletion on my phone: a message your correspondent deletes for everyone stays on your phone, and their phone is told so. Level 7 also opens Record calls: calls are recorded by themselves on your phone and sent to the call's chat after your first consent. Level 8 opens your own node: a machine you own joins the Montana network through this app. All of them are in Settings, under Access by level.": "Каждый уровень открывает функции Монтаны. Уровень 7 открывает Запрет удаления у меня: сообщение, которое собеседник удаляет у всех, остаётся на вашем телефоне, а телефон собеседника получает об этом уведомление. Ещё уровень 7 открывает Записывать звонки: звонки записываются сами на вашем телефоне и после вашего первого согласия отправляются в чат звонка. Уровень 8 открывает ваш собственный узел: машина, которой вы владеете, подключается к сети Монтаны через это приложение. Всё это — в Настройках, в разделе Доступ по уровню.",
 "Can I record a call below level 7?": "Можно ли записать звонок ниже уровня 7?",
 "Yes. On every level a call can be recorded by the record button on the call screen, unless your correspondent's switch holds. From level 7 calls are recorded by themselves once you agree the first time, and you can turn it off in Settings, under Access by level.": "Да. На любом уровне звонок можно записать кнопкой записи на экране звонка, если этого не запрещает переключатель собеседника. С уровня 7 звонки записываются сами после вашего первого согласия, и это можно выключить в Настройках, в разделе «Доступ по уровню».",
 "Who can record a call with me?": "Кто может записать звонок со мной?",
 "While your Record calls switch in Access by level is off, and below level 7 it stands off, a correspondent whose Global level is not above yours cannot record your calls: neither by themselves nor by the record button, which they do not see. A correspondent with a higher level records on their side only; your computer records nothing, and the chat is told that the call is being recorded. A version of Montana that does not say the switch forbids nothing.": "Пока ваш переключатель «Записывать звонки» в разделе «Доступ по уровню» выключен, а ниже уровня 7 он выключен всегда, собеседник, чей Глобальный уровень не выше вашего, не может записать ваши звонки: ни сам, ни кнопкой записи, которую он не видит. Собеседник с более высоким уровнем записывает только на своей стороне; ваш компьютер ничего не записывает, а в чат приходит сообщение, что звонок записывается. Версия Монтаны, которая не сообщает о переключателе, ничего не запрещает.",
 "Who sends the recording to the chat?": "Кто отправляет запись в чат?",
 "In a one-to-one call the caller sends the recording to the chat. When the caller does not record, the one who answered sends it, so a recorded call always reaches the chat, once.": "В личном звонке запись в чат отправляет тот, кто позвонил. Если он не записывает, её отправляет тот, кто ответил, поэтому записанный звонок всегда попадает в чат, один раз.",
 "Can I take my copy back from my node below level 8?": "Можно ли забрать свою копию с узла ниже уровня 8?",
 "Yes. Setting up your node and sending copies to it open at level 8. Taking your copy back from it is open on every level.": "Да. Настройка вашего узла и отправка копий на него открываются с уровня 8. Забрать свою копию с него можно на любом уровне.",
 "Fabric of Time": "Ткань времени",
 "What is the Fabric of Time?": "Что такое Ткань времени?",
 "The third level your Global level is set by: the people you write to and call regularly, each weighed by the level their own time and wallet give them. Your Global level is the lowest of the three, so the Fabric of Time can lower it and never raises it.": "Третий уровень, которым задаётся ваш Глобальный уровень: люди, с которыми вы регулярно переписываетесь и созваниваетесь, каждый — по уровню, который дают ему его собственное время и кошелёк. Глобальный уровень — наименьший из трёх, поэтому Ткань времени может его опустить и никогда не поднимает.",
 "What counts as an exchange?": "Что считается обменом?",
 "Anything you and a person send each other that stands in your conversation: words, voice and video messages, photos, files, stickers and GIFs, coin transfers, the moves of a game, and a call in which each phone received the other's voice for at least 60 seconds. Receipts, typing and presence do not count, and neither does a group.": "Всё, что вы с человеком отправляете друг другу и что стоит в вашей переписке: слова, голосовые и видеосообщения, фото, файлы, стикеры и GIF, переводы монет, ходы игры, а также звонок, в котором каждый телефон слышал голос другого не меньше 60 секунд. Квитанции, «печатает» и присутствие не считаются, группа тоже.",
 "When does a person's phone sign for me?": "Когда телефон собеседника подписывает за меня?",
 "When a word of yours reaches their phone and they wrote to you themselves in the last 7 days, their phone signs, once a day at most, that your word reached it: the minute it arrived, the hash the fingerprint of your conversation is read from, and their own ceiling. It gives the signature to you alone, inside your conversation. A person who only writes and is never answered receives none.": "Когда ваше слово доходит до его телефона, а он сам писал вам за последние 7 дней, его телефон не чаще раза в сутки подписывает, что ваше слово дошло: минуту прихода, хеш, из которого читается отпечаток вашей переписки, и свой потолок. Подпись он отдаёт только вам, внутри вашей переписки. Тот, кто только пишет и не получает ответа, не получает ни одной.",
 "Who is a regular correspondent?": "Кто такой регулярный собеседник?",
 "A person from whom your phone holds a signature in each of the last two weeks: the newer 7 days and the 7 before them. The window slides with the clock of the network; there are no fixed weeks. People are told apart by the key their signatures are made with, which their 24 words give for your conversation alone, not by anything they say about themselves.": "Человек, от которого у вашего телефона есть подпись в каждой из двух последних недель: в последние 7 дней и в 7 дней до них. Окно скользит вместе с часами сети, фиксированных недель нет. Людей различают по ключу их подписей, который их 24 слова дают только для переписки с вами, а не по тому, что они говорят о себе.",
 "How is the level of the Fabric of Time counted?": "Как считается уровень Ткани времени?",
 "Each regular correspondent stands at their ceiling: the lower of their two other levels, at its lowest in their signatures of the last two weeks. The level is the greatest number g for which at least g of your regular correspondents stand at g or above; a person far above g adds one, exactly as one at g does. It is counted again whenever a signature arrives or leaves the two weeks. Their own Fabric of Time does not enter it, so one person's dip never pulls a whole circle down.": "Каждый регулярный собеседник стоит на своём потолке: меньшем из двух его других уровней, в самой низкой точке его подписей за последние две недели. Уровень — наибольшее число g, при котором не меньше g ваших регулярных собеседников стоят на g или выше; человек намного выше g добавляет одного, ровно как стоящий на g. Уровень пересчитывается, как только подпись приходит или выходит из двух недель. Их собственная Ткань времени в счёт не входит, поэтому провал одного человека никогда не тянет вниз весь круг.",
 "Does the Fabric of Time lower a newcomer?": "Опускает ли Ткань времени новичка?",
 "Not in the first two weeks. From the first launch of this version on this phone with your 24 words, for 14 days the Fabric of Time stands at your ceiling, so your Global level follows your two other levels. TimeCoin and Access by level show the days left until the first count.": "Не в первые две недели. С первого запуска этой версии на этом телефоне с вашими 24 словами 14 дней Ткань времени стоит на вашем потолке, поэтому Глобальный уровень следует за двумя другими уровнями. Монета Времени и «Доступ по уровню» показывают, сколько дней осталось до первого счёта.",
 "What do the people I write to learn?": "Что узнают те, с кем я переписываюсь?",
 "Your ceiling, inside the signatures your phone gives them, and nothing else of the Fabric of Time. A signature names your conversation by the hash its fingerprint is read from, which only the two of you can compute, and it is made with a key your 24 words give for that conversation alone. No key and no number in it is the same with two people, so two people you write to cannot tell from it that they speak with the same person.": "Ваш потолок внутри подписей, которые им даёт ваш телефон, и больше ничего из Ткани времени. Подпись называет вашу переписку хешем, из которого читается её отпечаток, и вычислить его можете только вы двое, а сделана она ключом, который ваши 24 слова дают только для этой переписки. Ни ключ, ни число в ней не совпадают у двух людей, поэтому двое ваших собеседников не могут понять по ней, что говорят с одним человеком.",
 "What do the nodes of the network learn?": "Что узнают узлы сети?",
 "Nothing they can read: signatures and ceilings ride inside your conversation, sealed for the other person, by the same road as your letters. Signatures stay on your phone for two weeks and then leave it.": "Ничего, что они могут прочесть: подписи и потолки идут внутри вашей переписки, запечатанные для другого человека, той же дорогой, что ваши письма. Подписи хранятся на вашем телефоне две недели, затем уходят.",
 "How does this version differ from the specification?": "Чем эта версия отличается от спецификации?",
 "In four ways. A phone holds no window of the network's core, so the minute of a signature and the two weeks are read from the clock of the Montana nodes, learned from their answers. The signatures are not yet witnessed into the network; they stay on the phone that received them. Each of your devices with the same 24 words counts the signatures that reached it. And a signature names a conversation and is made with a key for that conversation alone, where the specification names the key of a person: this version knows people only by their conversations.": "В четырёх местах. Телефон не держит окна ядра сети, поэтому минута подписи и две недели читаются по часам узлов Монтаны, узнанным из их ответов. Подписи пока не свидетельствуются в сеть: они остаются на телефоне, который их получил. Каждое ваше устройство с теми же 24 словами считает подписи, дошедшие до него. И подпись называет переписку и делается ключом только этой переписки, тогда как спецификация называет ключ человека: эта версия знает людей только по их перепискам.",
 "Can false signatures lift a level?": "Могут ли ложные подписи поднять уровень?",
 "No. The Fabric of Time only lowers: a person who states a false ceiling can at most spare someone a lowering and never lifts anyone above their own ceiling. One signature a day from one person is kept, the one with the lower ceiling, so two of their devices answering the same word weigh as one.": "Нет. Ткань времени только опускает: человек, заявивший ложный потолок, может самое большее избавить кого-то от понижения и никогда не поднимает никого выше его собственного потолка. От одного человека хранится одна подпись в сутки, с меньшим потолком, поэтому два его устройства, ответившие на одно слово, весят как одно.",
 "Coins and time": "Монеты и время",
 "What is a Time Coin?": "Что такое Монета Времени?",
 "The coin of Montana, ticker $TCM. Its measure is time: one second is one coin, so an hour is 3600 coins. A billion coins is one Montana.": "Монета Монтаны, тикер $TCM. Её мера — время: одна секунда — одна монета, поэтому час — 3600 монет. Миллиард монет — одна Монтана.",
 "Do coins mint while Montana is in the background?": "Чеканятся ли монеты, пока Монтана свёрнута?",
 "Yes. When Montana leaves the screen, it keeps the moment it left. When you come back, every second you were away mints one coin, the same one coin a second as everywhere. At Global level 0 the time away mints nothing, and neither does it when the network did not answer Montana before it left the screen. Both moments are read from the Montana network, so turning the clock of the phone changes nothing.": "Да. Когда Монтана уходит с экрана, она запоминает момент ухода. Когда вы возвращаетесь, каждая секунда отсутствия чеканит одну монету — ту же одну монету в секунду, что и везде. При Глобальном уровне 0 время отсутствия ничего не чеканит, как и тогда, когда сеть не ответила Монтане перед уходом с экрана. Оба момента берутся из сети Монтаны, поэтому перевод часов телефона ничего не меняет.",
 "Your words and devices": "Ваши слова и устройства",
 "What if I use Montana on several devices?": "Что, если я пользуюсь Монтаной на нескольких устройствах?",
 "The same 24 words on several devices are one person. Their seconds join: two devices open in the same second add one second, and once the devices have read each other's count, they show one chain of the person.": "Одни и те же 24 слова на нескольких устройствах — это один человек. Их секунды объединяются: два устройства, открытые в одну и ту же секунду, добавляют одну секунду, и когда устройства прочитают счёт друг друга, они показывают одну цепь Личности.",
 "What if I have several sets of 24 words?": "Что, если у меня несколько наборов из 24 слов?",
 "Each set of 24 words is a separate person: its own seconds, its own wallet, its own levels. The levels of two persons are never added together, and coins move between them only by a real transfer.": "Каждый набор из 24 слов — отдельный человек: свои секунды, свой кошелёк, свои уровни. Уровни двух людей никогда не складываются, а монеты между ними переходят только настоящим переводом.",
 "Privacy": "Приватность",
 "Who sees my level?": "Кто видит мой уровень?",
 "The people you write with see your Global level beside your avatar. The nodes of the network keep a table of how many people stand on each level: for it Montana gives them a mark made from your 24 words and your Global level, never your balance, name or contacts. Your seconds online leave the phone only sealed under your 24 words: the nodes keep them for your other devices and cannot read them.": "Люди, с которыми вы переписываетесь, видят ваш Глобальный уровень рядом с вашим аватаром. Узлы сети ведут таблицу того, сколько людей стоит на каждом уровне: для неё Монтана передаёт им метку, сделанную из ваших 24 слов, и ваш Глобальный уровень — но никогда ваш баланс, имя или контакты. Ваши секунды в сети покидают телефон только запечатанными под вашими 24 словами: узлы хранят их для других ваших устройств и не могут их прочитать."
};
const say = (s) => (locale.startsWith("ru") ? RU[s] || s : s);

export function QuestionsPage({ onClose }) {
  const [open, setOpen] = useState(null);
  if (open) {
    return (
      <Page title={say(open.topic)} onClose={() => setOpen(null)} back>
        <Section>
          <div className="set-row answer" role="group" aria-label={say(open.item.q)}>
            <span className="row-title"><b>{say(open.item.q)}</b><span className="answer-text">{say(open.item.a)}</span></span>
          </div>
        </Section>
      </Page>
    );
  }
  return (
    <Page title={t("Questions")} onClose={onClose} back>
      {TOPICS.map((topic) => (
        <Section key={topic.title} head={<><Glyph name={topic.icon} size={13} /> {say(topic.title)}</>}>
          {topic.items.map((item) => (
            <button key={item.q} className="set-row" onClick={() => setOpen({ topic: topic.title, item })}>
              <span className="row-title">{say(item.q)}</span><span className="row-value">›</span>
            </button>
          ))}
        </Section>
      ))}
      <Section head={t("Documents")} foot={t("The site holds the answers about Montana in English, Russian and Chinese, also as files AI assistants read. The Montana specification and the code of this app are open on GitHub.")}>
        <button className="set-row" onClick={() => invoke("open_site", { page: "guide" })}><span className="row-title">{t("Questions and answers")}</span><span className="row-value">↗</span></button>
        <button className="set-row" onClick={() => invoke("open_site", { page: "source" })}><span className="row-title">{t("Specification and code")}</span><span className="row-value">↗</span></button>
      </Section>
    </Page>
  );
}
