# Hjerterfri-bot: strategi pr. niveau

Spec for `Hjerterfri::Bot`. Besluttet med Anders i ticket 20 (grilling, oktober 2026). Baggrund og kilder står i `docs/research/hjerterfri-bot-strategy.md` (S1–S12 nedenfor henviser dertil).

Mærker:
- **[kilde Sx]** reglen står i en kilde.
- **[valgt]** agenten har valgt reglen ud fra kilderne. Anders har bedt om ikke at blive spurgt på det niveau, så den må justeres efter bot-turneringen.
- **[hjerterfri]** gælder kun hjerterfri. Uden mærke er reglen spilneutral og kan genbruges til nolo og sol i es-makker, hvor ethvert stik er dårligt.

## 1. Grundbegreber (spilneutrale)

| Begreb | Betydning |
|---|---|
| **Strafkort** | Et kort, der giver point til den, der tager stikket. I hjerterfri er det hjerter (1) og Q♠ (13) **[hjerterfri]**. I nolo/sol er hele stikket straf. |
| **Rent stik** | Et stik uden strafkort. |
| **Dukke** | At bekende med det højeste kort, der stadig taber stikket. |
| **Renonce** | Ingen kort tilbage i en farve. Når farven spilles, kan man smide (afkast) hvad som helst. |
| **Exitkort** | Et kort, der med sikkerhed taber stikket, fordi der stadig er et højere kort ude i farven hos en spiller, der ikke er renonce. |
| **Farligt kort** | Et højt kort, der kan tvinges til at vinde et stik med straf. Det gælder især A♠/K♠, mens Q♠ er ude **[hjerterfri]**. |
| **Kortoptælling** | Hvilke kort der er spillet, og hvilke pladser der er renonce i hvilke farver. Den sidste del udledes, når en plads ikke bekender. |

En regel, der siger "vælg X", betyder: blandt `legal_moves` vælges det kort, der passer bedst. Er der ingen sådanne kort, går man videre til næste regel. Botten vælger altid kun fra `legal_moves`.

## 2. Hvad botten ser

Fra `Round#view_for(seat)` (allerede i dag): egen hånd, kortantal, aktuelt stik, `legal_moves`, `hearts_broken`, `pass_direction`, `own_pass`, `received_cards`.

Nyt (kræver motorændring). Alt sammen er offentlig information:
- **Alle stik i runden**, med hvem der spillede hvert kort, og hvem der vandt hvert stik.
- **Point taget i runden pr. plads** (`points_taken`).
- **Samlet score pr. plads** og spillets slutscore.
- **Bordets regler** (`queen_breaks_hearts`, `jack_of_diamonds_minus_ten`).

Hvad hvert niveau *bruger* af det:

| | Let | Mellem | Svær |
|---|---|---|---|
| Aktuelt stik | ja | ja | ja |
| Egne byttede/modtagne kort | nej | ja | ja |
| Om Q♠ er spillet | nej (antager den er ude, medmindre den selv har den) | ja | ja |
| Point taget pr. plads (månen) | nej | ja | ja |
| Fuld kortoptælling og renoncer | nej | nej | ja |
| Samlet score | nej | nej | ja |
| Husregler | via `legal_moves` | ja | ja |

Mellems hukommelse svarer til en almindelig spiller, der lægger mærke til, hvor damen er, og hvem der samler point, men ikke tæller kort **[valgt]**.

## 3. Variation

Hvert niveau rangerer de lovlige træk efter sine regler. Når to eller flere træk er "næsten lige gode", trækkes der lod mellem dem med den injicerede `random:`.
- **Let og Mellem:** næsten lige gode betyder kort, der ligger ved siden af hinanden i rang (fx 7 og 8 i samme farve) og har samme rolle (begge dukker, eller begge er afkast af samme slags) **[valgt]**.
- **Svær:** kun kort, der er helt ækvivalente efter kortoptællingen, fx 7 og 8, når alle kort imellem er spillet **[valgt]**.

Variationen må aldrig vælge et træk, som en tidligere regel har sorteret fra.

## 4. Let

Spiller for at vinde med simple regler. Ingen hukommelse og ingen plan, men aldrig absurd. Det svarer til den nuværende bot.

**Bytte [hjerterfri]**
1. Q♠, hvis den har færre end 3 lavere spar [kilde S2; i dag er tallet 4, og det sænkes til 3 som på de andre niveauer].
2. A♠/K♠, hvis den ikke har Q♠.
3. Højeste hjerter.
4. Højeste kort.

**Udspil.** Laveste kort, helst ikke strafkort og aldrig farlige kort, hvis andet findes.

**Bekende.**
1. Dukke [kilde S3: "very strong"].
2. Kan den ikke dukke og sidder sidst: det højeste kort, der ikke er strafkort.
3. Kan den ikke dukke og sidder ikke sidst: laveste kort.

**Afkast.** Q♠, derefter højeste hjerter, derefter højeste kort **[hjerterfri: rækkefølgen]**.

## 5. Mellem = Let + følgende

**Bytte [hjerterfri]**, i denne rækkefølge, indtil der er 3 kort:
1. **Q♠ væk,** hvis den har færre end 3 andre spar [kilde S2, Puzzle Pirates].
2. **A♠/K♠ væk,** hvis den ikke har Q♠ og har færre end 3 lave spar (knægt og under). Lave spar beholdes altid [kilde S1, Rarepike].
3. **Renonce i ruder eller klør:** en farve med højst så mange kort, som der er plads til i byttet, gives helt væk. Ruder foretrækkes frem for klør [kilde Rarepike: "ruder bedst", "4+ er for mange"]. Giv aldrig spar væk, så man er kort under damen [kilde S1].
4. **A♥, K♥, Q♥ væk.** Lave hjerter (2–6) beholdes [kilde S1, Rarepike].
5. **Resten:** de højeste kort, es og konger først, fra de længste farver [kilde Rarepike].

Botten husker, hvem den gav Q♠ og A♠/K♠ til (retningen er kendt).

**Udspil**
1. **Renonce-plan:** i de første stik spilles den korteste ikke-spar-farve fra toppen, mens stikket næppe får strafkort. Det gælder kun, så længe hjerter ikke er brudt, og ingen plads er kendt renonce i farven [kilde S1, S2; betingelserne er valgt].
2. **Jag Q♠ [hjerterfri]:** har botten hverken Q♠, K♠ eller A♠, og er Q♠ ikke spillet, spilles laveste spar [kilde S1, S2, Pagat].
3. **Hjerter [hjerterfri]:** når hjerter spilles ud, spilles laveste hjerter [kilde S1].
4. Ellers som Let.

**Bekende**
1. **Rent stik, sidst i stikket:** tag stikket med det højeste kort i farven, så botten slipper af med et farligt kort. Undtagelser: hvis kortet er Q♠, eller hvis stikket er i spar, og Q♠ kan komme senere. Det sidste er uden betydning, når botten sidder sidst [kilde S1, S2].
2. **Spar efter damen [hjerterfri]:** har botten givet Q♠ til en plads, der allerede har spillet i stikket uden Q♠, eller er Q♠ spillet, må A♠/K♠ gerne spilles i spar [kilde S1, S10].
3. Ellers dukke som Let.

**Afkast**
1. Q♠ [kilde S1, S2, Pagat: "smid damen, så snart det er sikkert"].
2. A♠/K♠, mens Q♠ er ude, og botten ikke selv har den [kilde S1].
3. Højeste hjerter.
4. Højeste kort i den korteste farve (for at blive renonce) [kilde S2].

**Ruder knægt −10 [hjerterfri, kun når reglen er slået til]**
- Ligger J♦ i stikket, og kan botten tage stikket uden strafkort, så tag det med laveste vindende ruder [kilde S1].
- Spilles ruder ud, og J♦ er ude: læg lav ruder [kilde S1].
- Spil ikke selv J♦, hvis den kan tabes til en anden. Det er kun tilladt, når den er højeste ude, og stikket er rent [valgt].

**Stop månen [hjerterfri]**
- *Månetrussel:* præcis én anden plads har taget strafpoint i runden, og den har mindst 10 [valgt; kilde Puzzle Pirates: "så længe to spillere har taget point, kan ingen skyde månen"].
- Under truslen: kan botten vinde et stik med strafkort, tager den det med laveste vindende kort. Det gælder også, selv om stikket indeholder Q♠, for 13 point er mindre end 26 [kilde S1, S12 §3.6].
- Under truslen gemmer botten 2–3 høje kort til de sidste stik i stedet for at smide dem [kilde S1].

## 6. Svær = Mellem + følgende

**Kortoptælling.** Botten husker alle spillede kort og hvem der spillede dem. Den udleder renoncer og ved, hvor Q♠ er, hvis den har givet eller fået den.

**Bytte**
- **Månehånd [hjerterfri]:** botten har A♥, K♥ og Q♥ og mindst 6 hjerter, eller A♥, K♥ og Q♥ plus en farve med 6+ kort med es. Er Q♠ i hånden, skal den være beskyttet af mindst 3 andre spar. Så beholder botten hjerter og høje kort og giver de laveste kort fra de svageste farver væk [kilde S1, S2; tallene er valgt].
- Ellers som Mellem.

**Udspil**
- **Sent i runden** (højst 4 kort tilbage pr. spiller): spil exitkort og undgå at vinde. Botten beholder lave kort i to farver til slutningen [kilde S1].
- **Sikre høje kort:** midt i runden spilles en farvens højeste tilbageværende kort, hvis ingen anden plads er kendt renonce i farven (stikket bliver rent). Det skaffer botten af med høje kort uden risiko [udledt fra S1 og S2: "tag dine es tidligt"].
- **Spar, mens Q♠ er hos en kendt plads:** botten spiller spar, så den plads tvinges til at spille damen eller dukke [kilde S2].

**Bekende**
- **Exitkort før dukning:** kan botten tabe med sikkerhed, gør den det med sit højeste exitkort.
- **Tag ikke stik til sidst:** sent i runden tager botten hellere et rent stik tidligt end at sidde med høje kort til sidst [kilde S1].

**Afkast**
- Bevar mindst to farver med lave kort.
- Smid strafkort på den plads, der skader botten mest (se slutspil).

**Gå efter månen [hjerterfri]**
- Kun med en månehånd efter byttet (samme kriterier som ovenfor).
- *Månetilstand:* botten spiller høje kort ud og vinder alle stik med strafkort.
- *Afbryd:* så snart en anden plads tager et strafkort, går botten tilbage til normal spil og smider sine strafkort [kilde S1, S2: "mislykket forsøg er katastrofalt"].

**Slutspil og samlet score [hjerterfri]** (Svær kender ikke reglen om, at en bot ikke kan blive vinder)
- *Pas på sig selv:* kan et strafkort bringe botten over slutscoren, prioriteres det over alt andet at undgå strafpoint.
- *Afslut spillet:* er botten lavest i samlet score, og kan en anden plads bringes over slutscoren med de point, botten kan give (fx Q♠ i et afkast), så giver den dem til den plads [kilde Puzzle Pirates: "giv damen til en spiller nær grænsen"].
- *Angrib føreren:* er botten ikke lavest, giver den strafkort til den plads med lavest samlet score, når den kan vælge [kilde Puzzle Pirates].
- *Månen nær slutscoren:* er botten lavest, og vil en vellykket måne bringe en anden over slutscoren, er månen ekstra god. Er botten ikke lavest, gælder det ikke [udledt].

## 7. Q♠: samlede detaljer [hjerterfri, valgt ud fra kilderne]

| Situation | Mellem/Svær gør |
|---|---|
| Byttet, Q♠ med under 3 andre spar | Giv den væk [kilde S2, Puzzle Pirates] |
| Byttet, Q♠ med 3+ andre spar | Behold den [kilde S2] |
| Har Q♠, spar spilles ud | Duk med højeste spar under det vindende kort. Spil aldrig Q♠, hvis den kan vinde [udledt] |
| Har Q♠, renonce i den udspillede farve | Smid Q♠ med det samme [kilde Pagat, S1] |
| Har ikke Q♠, Q♠ ude, uden A♠/K♠ | Spil lave spar ud for at jage damen [kilde S1, S2, Pagat] |
| Har A♠/K♠, Q♠ ude | Smid dem ved første renonce. Spil dem kun, når damens plads har spillet i stikket, eller sidst i et stik uden damen [kilde S1, S10] |
| Q♠ spillet | Spar er en almindelig farve [kilde S2] |
| Spar dame bryder hjerter (husregel) | Ingen ændring i valg. Reglen påvirker kun, om der må spilles hjerter ud, og det står i `legal_moves` |

## 8. Måling (bot-turnering)

Et script eller en test spiller N seedede spil, fx 1.000, med pladserne roteret mellem niveauerne. Det rapporterer gennemsnitlige point pr. runde pr. niveau. Kravet er Svær < Mellem < Let. Reglerne mærket [valgt] er dem, der først skal justeres, hvis turneringen ikke viser den rækkefølge.
