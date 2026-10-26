# Kortspil

A private site where members and family play card games together. The UI is in Danish, and code uses the English names given in brackets.

## The game

**Bord** (`Table`):
The room where people play: four seats, a vært, table chat, and a type (open, password or private). It is made in the lobby for one game (hjerterfri or es-makker), which never changes. A bord hosts any number of spil in sequence. Until its first spil starts it lives only in the lobby (`WaitingTable`, in memory); the spil's start stores it.
_Avoid_: room, lobby (the lobby is the list of borde)

**Bordets regler** (`TableRules`):
The bord's own rules, set by the vært before the spil starts: whether the bord is open, has a password or is private, and for es-makker how many runder the spil lasts.

**Spillets regler** (`GameRules`):
The card game's rules for this bord, set by the vært before the spil starts: for hjerterfri the end score and the house rules; for es-makker the påhæng order, jokers, bank and point values. Together with bordets regler they are the bord's rules.

**Spil** (`Game`):
One game at a bord: hjerterfri is played until someone reaches the end score; es-makker for the bord's number of runder.
_Avoid_: match, session

**Runde** (`Round`):
One deal: the bytte (if any) plus 13 stik.
_Avoid_: hand (a hand is the cards one player holds), deal

**Bytte** (`Pass`):
The start of a runde, before the first stik: every seat gives three cards to another seat, to the left, to the right or across, by turns from runde to runde, and every fourth runde there is no bytte. All four give at the same time, and nobody sees the cards they get until all four have given.
_Avoid_: swap, exchange

**Kortgiver** (`dealer`):
In es-makker, the seat that deals the runde. It moves one seat clockwise each runde.
_Avoid_: giver in code

**Forhånd** (`forhand`):
In es-makker, the seat after the kortgiver, who starts the meldingsrunde.

**Meldingsrunde** (`Bidding`):
In es-makker, the start of a runde: from the forhånd, each seat bids a melding higher than the one standing, or says pas. It ends with a melder, or with the runde dealt again (gives om): when everybody passes, the former forhånd deals; after a jernhånd, the same kortgiver deals again. A runde dealt again is still the same runde.
_Avoid_: auction, bidding in the UI

**Melding** (`Melding`):
In es-makker, a bid: 8–13 stik, with or without a påhæng (gode, halve, vip), or one of the sol-meldinger (sol, ren sol, bordlægger, ren bordlægger). All meldinger sit on one ladder in a fixed order. The seat that wins the meldingsrunde is the **melder**.
_Avoid_: bid in the UI

**Pas** (`Pas`):
In es-makker, saying no in the meldingsrunde. A seat that has said pas is out of it for the rest of the runde.
_Avoid_: pass (that is the bytning in hjerterfri)

**Det kan jeg selv** (`DetKanJegSelv`):
In es-makker, the holder of the melding takes over exactly the melding the challenger just bid (serveretten), on any melding.

**Gå med** (`GaaMed`):
In es-makker, playing the same sol-melding as the melder, each on their own, instead of bidding on.

**Jernhånd** (`Jernhaand`):
In es-makker, 13 cards with no picture cards, aces or jokers. Its holder may claim it before the first melding, and the runde is dealt again.

**Trumf** (`Trump`):
In es-makker, the suit the melder names after winning a stik melding; it beats the other suits. She may name **trumfløs** instead (no trump; the same as Sans). At gode, clubs are trump. At **vip** she calls the ace first and then turns katten's cards one by one (`TurnCard`), taking one as trump (`AcceptTrump`, "det er trumf"); the third is trump in any case, and a joker is trumfløs. The card taken (`vip_card`, 1–3) is the runde's doubling.

**Esmakker** (`esmakker`):
In es-makker, the player holding the ace the melder called: the melder's partner for the runde, hidden from the others until the ace is played. At halve she gives herself away at once, names trump and takes katten (code: the play's `declarer`). If the ace lies in katten, the melder is **selvmakker** and plays alone.
_Avoid_: partner in the UI (say makker)

**Gik hjem / bet** (`gik_hjem?`):
In es-makker, a stik melding goes home when the melder and the esmakker (or the selvmakker alone) take at least the bid number of stik; with fewer it goes bet.

**Point** (`Scoring`, `RundeResult#points`):
In es-makker, the zero-sum score: everyone starts at 0, and each runde moves points between the seats by the bord's point values. A melding that gik hjem wins (indsats + overstik) × fordoblinger; one that went bet loses indsats × manglende stik × fordoblinger. **Indsats** (stake) is the melding's number's amount (8 = 1 … 13 = 3,5); an **overstik** is a stik beyond the bid number; the **fordoblinger** (doublings) are påhæng (gode, halve), vip's kitty card, trumfløs and each bank. Each loser pays each winner the amount; a selvmakker against all three. The **stillingsark** (score sheet) lists every runde's points and the running totals.
_Avoid_: kroner, score in the UI

**Sol og ren sol** (`SolPlay`, `SolResult`):
In es-makker, the sol-meldinger played without trump, called ace or makker: the melder and everyone who went with (the **sol-spillere**) each play the same melding for herself; the others are **modspillere**. The ace is the lowest card, the forhånd leads, a led joker wins the stik. At sol a sol-spiller may take one stik, at ren sol none; one stik more and she is **væltet**. The runde is played to the end and stops early only when every sol-spiller is væltet. Each sol-spiller settles the melding's fixed amount with each modspiller on her own: she wins it from each if she kept within her stik, and pays it to each if væltet. Bordlægger and ren bordlægger are played the same way with the melder's cards open after the first stik.

**Katten** (`kitty`):
In es-makker, the three cards dealt to nobody: 55 cards (52 and three jokers) give 13 to each seat and 3 to katten. The melder takes katten up when she calls the ace and lays three cards away (`Discard`) that nobody else sees. At sol and ren sol the kitty goes round instead: the melder, those who went with, then clockwise from the melder each take up what is left of it and lay as many cards away; kitty cards laid back go on to the next.

**Fordækt** (`LayFordaekt`, `FordaektCard`):
In es-makker, a melder with no card in the called ace's suit after katten may, before she leads the first stik, lay one card (not a joker) face down. It counts as a card of the ace's suit: led, the esmakker must lay the ace on it. Only the melder sees its face until its stik is taken; then it is turned.

**Esset må ikke stikkes**:
In es-makker, the esmakker must lay the called ace the first time its suit is led, and once it lies in a stik led in its suit, a seat void in the suit may not trump it; the ace takes that stik. The rule is the esmakker's: it does not bind a selvmakker.

**Joker** (`Joker`):
In es-makker, one of three extra cards. It may be played at any time; led, it takes the stik (unless the bord lets trump beat it); not led, it is worth nothing.

**Stik** (`Trick`):
Four cards, one from each seat. The winner leads the next stik.

**Øvespil** (practice game):
A spil at a practice bord, one human against three bots. It never counts in any statistics.

## People at the table

**Vært** (`host`):
The bord's owner, who controls its settings: only the vært changes the rules, adds and removes bots, and starts the spil. Starts as the creator and passes to the next human if the vært leaves.

**Bot**:
A computer player in a seat, either from the start or by taking over the seat of a player who has forladt. It acts for itself on its turn, just like a human player, at its level: Let, Mellem or Svær. A bot can never be a spil's vinder.
_Avoid_: AI, computer, afløser

**Puf** (nudge):
An invitation from a player seated at a bord to a friend to join it before its spil, which they accept (and are seated) or decline. A pending puf holds a free seat for a minute; the one who sent it, or the vært, can withdraw it. Seated players, bots and pending pufs never outnumber the seats.
_Avoid_: invite (in the UI)

## Leaving and results

**Forlade** (leave):
To give up one's seat in a spil that is in progress. It is either active (pressing "Forlad bordet") or passive (being frakoblet for longer than 60 seconds). A player who has forladt a spil has lost it and cannot return to it.
_Avoid_: opgive, forfeit, quit

**Frakoblet** (disconnected):
A player who has lost the connection or stopped acting during a spil in progress. The 60-second clock starts the moment the connection is lost. If the player returns in time, they keep their seat; otherwise they have forladt.
_Avoid_: offline, absent

**Tur-ur** (`TurnClock`):
The clock that runs on each human seat during a spil at an open bord. A player who has not acted 30 seconds into their turn is warned, and one who has not acted after 60 seconds, or has been frakoblet for 60 seconds, has forladt. A practice bord has no tur-ur, and bots are never on it.

**Vinder** (winner):
A human with the best total when a spil ends: the lowest at hjerterfri, the highest at es-makker (points are won there). Humans who tie share the win, and a human who ties with a bot still wins. If a bot alone has the lowest total, the spil has no vinder.

**Afbrudt** (abandoned):
A spil that stopped unfinished because no humans were left at the bord.
_Avoid_: cancelled, aborted
