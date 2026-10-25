# Kortspil

A private site where members and family play card games together. The UI is in Danish, and code uses the English names given in brackets.

## The game

**Bord** (`Table`):
The room where people play: four seats, a vært, table chat, and a type (open, password or private). It is made in the lobby for one game (hjerterfri). A bord hosts any number of spil in sequence. Until its first spil starts it lives only in the lobby (`WaitingTable`, in memory); the spil's start stores it.
_Avoid_: room, lobby (the lobby is the list of borde)

**Spil** (`Game`):
One game of hjerterfri, played until someone reaches the end score.
_Avoid_: match, session

**Runde** (`Round`):
One deal: the pass (if any) plus 13 stik.
_Avoid_: hand (a hand is the cards one player holds), deal

**Stik** (`Trick`):
Four cards, one from each seat. The winner leads the next stik.

**Øvespil** (practice game):
A spil at a practice bord, one human against three bots. It never counts in any statistics.

## People at the table

**Vært** (host):
The player who controls the bord's settings. Starts as the creator and passes to the next human if the vært leaves.

**Bot**:
A computer player in a seat, either from the start or by taking over the seat of a player who has forladt. A bot can never be a spil's vinder.
_Avoid_: AI, computer, afløser

**Puf** (nudge):
An invitation from the vært to a friend to join a specific bord before its spil, which they accept (and are seated) or decline. A pending puf holds a free seat and expires after about five minutes.
_Avoid_: invite (in the UI)

## Leaving and results

**Forlade** (leave):
To give up one's seat in a spil that is in progress. It is either active (pressing "Forlad bordet") or passive (being frakoblet for longer than 60 seconds). A player who has forladt a spil has lost it and cannot return to it.
_Avoid_: opgive, forfeit, quit

**Frakoblet** (disconnected):
A player who has lost the connection or stopped acting during a spil in progress. The 60-second clock starts the moment the connection is lost. If the player returns in time, they keep their seat; otherwise they have forladt.
_Avoid_: offline, absent

**Vinder** (winner):
A human with the lowest total when a spil ends. Humans who tie share the win, and a human who ties with a bot still wins. If a bot alone has the lowest total, the spil has no vinder.

**Afbrudt** (abandoned):
A spil that stopped unfinished because no humans were left at the bord.
_Avoid_: cancelled, aborted
