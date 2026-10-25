# Hjerterfri-bot: strategi pr. niveau

Spec for `Hjerterfri::Bot`. Besluttet med Anders i ticket 20 (grilling, oktober 2026). Baggrund og kilder står i `docs/research/hjerterfri-bot-strategy.md` (S1–S12 nedenfor henviser dertil).

Mærker:
- **[kilde Sx]** reglen står i en kilde.
- **[valgt]** agenten har valgt reglen ud fra kilderne. Anders har bedt om ikke at blive spurgt på det niveau, så den må justeres efter bot-turneringen.
- **[hjerterfri]** gælder kun hjerterfri. Uden mærke er reglen spilneutral og kan genbruges til sol, ren sol og bordlægger i es-makker, hvor ethvert stik er dårligt.

## 1. Grundbegreber (spilneutrale)

| Begreb | Betydning |
|---|---|
| **Strafkort** | Et kort, der giver point til den, der tager stikket. I hjerterfri er det hjerter (1) og Q♠ (13) **[hjerterfri]**. I sol, ren sol og bordlægger er hele stikket straf. |
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

### Risiko før et højt kort (Anders, 2026-10-25)

Botterne holder øje med, hvad der er spillet, og hvad folk smider af. Før de spiller et højt kort, vurderer de chancen for, at en plads, der endnu ikke har spillet i stikket, er renonce og smider Q♠ (eller hjerter) på det. Det er **ét risikomål**, ens for alle farver og hele runden: tidligt er en renonce usandsynlig, når farven har været rundt, er den det ikke. Niveauerne adskiller sig kun i, hvor godt de vurderer.

Risikoen for et stik i en farve er summen over pladserne efter botten (alle andre, når den spiller ud) af *chancen for, at pladsen er renonce* × (13 × *chancen for, at den har Q♠* + 1 for et hjerter). Q♠ tæller ikke i spar, og hjertet tæller ikke, når farven er hjerter, eller pladsen er vist renonce i hjerter (`Bot::Knowledge#dump_risk`). I første stik er risikoen 0, for der kan ikke komme point i det (`LegalMoves`) **[kilde: reglerne]**.

| | Let | Mellem | Svær |
|---|---|---|---|
| Hvor er Q♠ | En plads, der er vist renonce i spar, har den ikke; er alle andre end én renonce, har den sidste den | + husker, hvem den gav Q♠ til; en plads, der smed et andet kort af i stedet for damen, har den nok ikke (vægt 0,2 **[valgt]**) | + vægter pladserne efter, hvor mange ukendte kort de har; en plads, der bekendte spar under A♠/K♠ uden at smide damen, har den nok ikke (vægt 0,4 **[valgt]**) |
| Chance for renonce | Kun vist renonce | Groft: farvens kort, der stadig er ude, fordelt på pladser med lige så mange kort som botten. + modtagne kort, groft (nedenfor) | Præcist: ukendte kort i farven fordelt på pladsernes ukendte kort; byttede kort, den ved hvor er, regnes med. + modtagne kort og byttets renoncer (nedenfor) |

- **Risikabel:** risiko ≥ 1,0 forventede point **[valgt; 2,0 før 2026-10-25, se §8]**. Så spiller botten hellere et andet kort ud (alle niveauer; det gælder ethvert kort, ikke kun høje kort, se §8) og bruger ikke farven til renonce-planen.

### Modtagne kort (Anders, 2026-10-25)

Kortene, en plads får i byttet, fortæller, hvilke farver giveren er kort eller renonce i, for botter (og mange mennesker) bytter korte farver væk med vilje. Det gælder fra andet stik og resten af runden. Første stik er undtaget, fordi det ikke kan give point. Når en plads har bekendt en farve, er den ikke mistænkt for at have været renonce i den fra byttet.

- **Let** læser ikke byttet.
- **Mellem** (groft): har giveren givet botten 2 eller flere kort i en farve, regnes giveren for sandsynligt renonce i den: chance 0,5 **[valgt]**.
- **Svær** regner chancen for, at pladsen var renonce, da spillet begyndte, sammen med optællingen: *p + (1 − p) × chancen ved tilfældig fordeling*. Her er *p* fra byttet:
  - giveren, efter hvor mange kort i farven den gav botten (0, 1, 2, 3): 0,014, 0,096, 0,33 og 0,40 **[udledt: målt på botternes egne bytter, `botlab voids`]**;
  - enhver anden plads, efter et bytte: 0,16 i klør og ruder og 0,026 i spar, mod ca. 0,013 ved tilfældig fordeling **[udledt, samme måling]**. Det er Anders' "regn med, at de andre laver renonce ved at bytte".
  - Hjerter tæller ikke (ingen bytter hjerter væk for at blive renonce).

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

**Udspil.** Laveste kort, helst ikke strafkort og aldrig farlige kort, hvis andet findes, og helst ikke i en risikabel farve (§2) **[valgt; før kun høje kort fra 10 og op, se §8]**.

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
2. **Jag Q♠ [hjerterfri]:** har botten hverken Q♠, K♠ eller A♠, og er Q♠ ikke spillet, spilles spar ud [kilde S1, S2, Pagat]. Det er den højeste spar under damen: først J♠, så 10♠, så 9♠ osv., så damen presses ud. De lave spar gemmes som bottens egen sikring mod selv at blive tvunget til at tage Q♠ senere [Anders, 2026-10-25, gengivet: spil spar knægt ud, pres, spil 10 ud, spil 9 ud, pres, så man ikke selv får damen; før laveste spar].
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
- Spil ikke selv J♦, hvis den kan tabes til en anden. Det er kun tilladt, når den er højeste ude, og stikket er rent [valgt]. Det gælder også udspil (J♦ spilles ikke ud, før den er højeste ruder ude) og afkast (J♦ smides ikke af, hvis andet kan smides) [valgt, 2026-10-25; før kun ved bekendelse].

**Stop månen [hjerterfri]**
- *Månetrussel:* præcis én anden plads har taget strafpoint i runden, og den har mindst 17 [valgt; 10 → 14 → 17 efter målingerne 2026-10-25 (§8), så Q♠ alene (13) og Q♠ med få hjerter ikke er en trussel; kilde Puzzle Pirates: "så længe to spillere har taget point, kan ingen skyde månen"].
- Under truslen: kan botten vinde et stik med strafkort, tager den det med laveste vindende kort. Det gælder også, selv om stikket indeholder Q♠, for 13 point er mindre end 26 [kilde S1, S12 §3.6].
- Under truslen gemmer botten 2–3 høje kort til de sidste stik i stedet for at smide dem [kilde S1].

## 6. Svær = Mellem + følgende

**Kortoptælling.** Botten husker alle spillede kort og hvem der spillede dem. Den udleder renoncer og ved, hvor Q♠ er, hvis den har givet eller fået den.

**Bytte**
- **Q♠ væk,** medmindre botten har mindst 5 andre spar [valgt, 2026-10-25; tallet i kilde S2 er 3, og det bruger Mellem stadig. Se §8].
- **Resten:** høje kort fra de farver, der har færrest lave kort (7 og under), først. Det er de farver, der senere tvinger botten til at tage stik [valgt, 2026-10-25].
- **Månehånd [hjerterfri]:** botten har A♥, K♥ og Q♥ og mindst 6 hjerter, eller A♥, K♥ og Q♥ plus en farve med 6+ kort med es. Er Q♠ i hånden, skal den være beskyttet af mindst 3 andre spar. Så beholder botten hjerter og høje kort og giver de laveste kort fra de svageste farver væk [kilde S1, S2; tallene er valgt].
- Ellers som Mellem.

**Udspil**
- **Spar, mens Q♠ er hos en kendt plads:** botten spiller spar, så den plads tvinges til at spille damen eller dukke [kilde S2]. Den spiller den højeste spar under damen (J♠, 10♠, 9♠ …) og beholder de lave [Anders, 2026-10-25; før laveste spar]. Reglen koster lidt mod botter (§8), men Anders beholder den: botterne skal blive ved med at spille spar, det er en god strategi [Anders, 2026-10-25, gengivet].
- **Billigste udspil** (i stedet for Lets "laveste kort"): blandt de kort, der ikke er farlige, spiller botten det med færrest forventede strafpoint: *chancen for at vinde stikket* × *de point, der kan lande i det* (risikomålet §2, og i hjerter de hjerter, de andre bekender med, plus dens eget). Chancen for at vinde er 0, når alle kort i farven, der stadig er ude, er højere (et sikkert exitkort), 1, når intet er højere, og ellers andelen af farvens udestående kort, der er lavere. Ved lighed vælges det laveste kort [valgt, 2026-10-25]. Det gør "spil exitkort og undgå at vinde" [kilde S1] i hele runden, ikke kun til sidst: et sikkert exitkort koster 0 og kommer først. Når hjerter er brudt, spilles fx et lavt hjerter, som med sikkerhed taber, før en klør, der kan vinde et stik, nogen smider på.
- *Fjernet 2026-10-25:* "sent i runden: spil det højeste exitkort" (erstattet af billigste udspil, som var bedre i målingen) og "sikre høje kort" [udledt] (gav intet, se §8).

**Bekende**
- **Tag stikket tidligt, når det er sikkert:** er stikket rent, og venter botten de pladser, der skal spille efter den, til at smide under 0,3 forventede point på det (risikomålet §2), tager den det med sit højeste kort i farven, ligesom Mellem gør, når den sidder sidst. Ikke i spar, mens Q♠ er ude [udledt fra S2: "tag dine es tidligt", og S1: "slip af med høje kort, før der kan smides på dem"; 0,3 er valgt, 2026-10-25].
- **Exitkort før dukning:** kan botten tabe med sikkerhed, gør den det med sit højeste exitkort.
- **Tag ikke stik til sidst:** sent i runden tager botten hellere et rent stik tidligt end at sidde med høje kort til sidst [kilde S1].

**Afkast**
- Efter Q♠ og A♠/K♠ (som Mellem) smider botten det kort, der har størst chance for at vinde et stik senere (chancen for at vinde, hvis det blev spillet ud, som i billigste udspil). Et hjerter lægges 0,6 til, og hvert kort i kortets farve trækker 0,2 fra, så korte farver tømmes først. Ved lighed smides det højeste kort [valgt, 2026-10-25]. Under en månetrussel gemmes de to højeste kort som hos Mellem. Reglen erstatter Mellems "højeste hjerter, så højeste kort i korteste farve" og den tidligere "bevar mindst to farver med lave kort", der ikke længere blev brugt.
- Smid strafkort på den plads, der skader botten mest (se slutspil).

**Ruder knægt −10 [hjerterfri, kun når reglen er slået til]** (Anders, 2026-10-25)

Svær regner J♦'s −10 med i sine forventede point: et stik med J♦ er værd stikkets point minus 10 for den, der tager det. Mellem beholder sine enkle J♦-regler (§5) og regner ikke.
- **J♦ i stikket:** Svær tager stikket, så længe *stikkets point + det, der ventes smidt på det* (risikomålet §2, 0 når den sidder sidst) er under 10. Fx J♦ med et hjerter i (netto −9), hvor Mellem dukker, fordi stikket ikke er rent. Sidst i stikket med laveste vindende ruder, ellers med højeste (den holder oftest) [valgt; højeste mod laveste målt +0,007].
- **J♦ på hånden:** Svær spiller selv J♦, når den vinder med sikkerhed (højeste ruder ude, eller sidst i stikket og højere end stikkets ruder), på samme vilkår. I udspil tæller J♦ −10 i billigste udspil, så en J♦, der er højeste ruder ude, spilles ud.
- **Behold en fanger:** mens J♦ er ude, beholder Svær sin højeste ruder over J♦. Den smides ikke af, hvis andet kan smides, og den bruges ikke til at tage et sikkert stik tidligt [valgt; målt +0,02–0,09].
- **Renonce-planen** løber ikke J♦ ud, før den er højeste ruder ude.
- *Prøvet og fravalgt 2026-10-25:* at spille høje ruder (ud eller til bekendelse) for at trække J♦ ud, når chancen for, at dens holder må bekende med den, gør det værd. Det kostede 0,04–0,08 point pr. runde: fangeren er mere værd, når J♦ senere falder af sig selv.

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
| Har ikke Q♠, Q♠ ude, uden A♠/K♠ | Spil spar ud for at jage damen [kilde S1, S2, Pagat]: højeste spar under damen først (J♠, 10♠, 9♠ …), de lave gemmes [Anders, 2026-10-25] |
| Har A♠/K♠, Q♠ ude | Smid dem ved første renonce. Spil dem kun, når damens plads har spillet i stikket, eller sidst i et stik uden damen [kilde S1, S10] |
| Q♠ spillet | Spar er en almindelig farve [kilde S2] |
| Spar dame bryder hjerter (husregel) | Ingen ændring i valg. Reglen påvirker kun, om der må spilles hjerter ud, og det står i `legal_moves` |

## 8. Måling

Anders, 2026-10-25: point pr. runde i en blandet turnering siger ikke meget, for en bot får færre point, når den spiller mod en dårlig bot. Målingen skal skille et niveaus egen styrke fra modstanderne og fra kortheld. Kravet er Svær bedre end Mellem bedre end Let, med en forskel man kan mærke ved bordet. Reglerne mærket [valgt] og [udledt] justeres først. Tal i [kilde]-regler må også justeres, men at fjerne eller vende en [kilde]-regel kræver Anders.

### Metoden

1. **Samme hånd, samme plads (duplikatspil, hovedmålet).** Hver deal spilles én gang pr. niveau og pr. plads. Let, Mellem og Svær holder præcis den samme hånd fra præcis den samme plads, mod det samme felt (tre botter af ét niveau), med samme byttretning og samme lodtrækningsfrø. Kun den målte plads skifter niveau, så forskellen på to niveauer med en hånd er deres egen. Rapporten viser, hvor ofte det stærkere niveau gør det bedre, lige så godt og dårligere med de samme kort, hvor meget det taber, når det taber, og den gennemsnitlige forskel i point pr. runde med 95 %-konfidensinterval (parret pr. hånd).
2. **Spil mod et fast felt.** Det, der afgør et rigtigt spil, er, hvem der ender lavest. Én plads af niveau X spiller hele spil mod tre botter af et fast niveau. Det samme spil (samme seed, så de samme kort runde for runde) spilles også med feltets niveau på X's plads. X skifter mellem alle pladser. Rapporten viser *vinderandel* (25 % er feltets eget niveau), *gennemsnitlig placering* 1–4, *point pr. runde i forhold til feltets bot på samme plads* og en Elo-agtig *rating* ud fra vinderandelen. Alt med 95 %-intervaller.
3. **Den blandede turnering** (pladserne roteret mellem niveauerne, point pr. runde og sejre) er beholdt som sidetal.

Værktøjerne: `tools/botlab` (Rust): `hands`, `eval`, `tournament`, `tune` (et tal eller en regel ad gangen, på samme hænder, mod standardfeltet), `regret` (finder de regler, der taber mest) og `voids`. `bin/rails 'bots:duplicate[deals,seed,field]'` og `bin/rails 'bots:tournament[spil,seed]'` (Ruby, den bot der kører i produktion). `bin/rails 'bots:parity[spil,seed]'` beviser, at Ruby og Rust træffer præcis de samme valg. Se `tools/botlab/README.md`.

Tal er justeret på seed 1 og bekræftet på seed 2, som ikke er brugt til at vælge dem.

### Resultat 2026-10-25

**Samme hånd, samme plads** (Rust, 50.000 deals × 4 pladser pr. felt; Δ = point pr. runde, lavere er bedre, ± 95 %):

| | Svær − Mellem | Mellem − Let | Svær − Let |
|---|---|---|---|
| Før (seed 1, felt Mellem) | −0,09 ± 0,02 (bedre 10 %, ens 82 %, dårligere 8 %) | −1,58 ± 0,06 | −1,66 ± 0,06 |
| Efter, felt Mellem, seed 1 | **−1,26 ± 0,03** (bedre 34 %, ens 50 %, dårligere 16 %) | −1,51 ± 0,04 | −2,78 ± 0,04 |
| Efter, felt Mellem, seed 2 | **−1,27 ± 0,03** (34 / 50 / 16 %) | −1,49 ± 0,04 | −2,76 ± 0,04 |
| Efter, felt Svær, seed 1 | **−1,34 ± 0,03** (36 / 48 / 16 %) | −1,19 ± 0,04 | −2,52 ± 0,04 |
| Efter, felt Svær, seed 2 | **−1,34 ± 0,03** (36 / 48 / 16 %) | −1,18 ± 0,04 | −2,52 ± 0,04 |

Når Svær gør det dårligere end Mellem med samme hånd (16 %), taber den i snit 6,8–7,2 point på hånden. `botlab hands --show` og `botlab trace` viser de hænder.

**Spil mod et fast felt** (Rust, 20.000 spil pr. niveau og felt, vinderandel ± 95 %):

| Felt | Let | Mellem | Svær |
|---|---|---|---|
| 3 × Let, seed 1 / 2 | 25 % | 58,8 / 58,1 % | **71,2 / 70,2 %** |
| 3 × Mellem, før (seed 1) | 10,8 % | 25 % | 27,0 % |
| 3 × Mellem, seed 1 / 2 | 11,1 / 11,0 % | 25 % | **44,6 / 44,0 %** (± 0,7) |
| 3 × Svær, før (seed 1) | 10,3 % | 22,9 % | 25 % |
| 3 × Svær, seed 1 / 2 | 7,0 / 7,1 % | 12,3 / 12,2 % | 25 % |

Mod tre Mellem ender Svær i snit på plads 1,93 (Mellem 2,50, Let 3,13) og tager 1,35 point færre pr. runde end Mellem på samme plads og med samme kort. Rating (0 = feltets niveau) mod 3 × Mellem: Let −172, Svær +151.

**Sidetal, blandet turnering** (Rust, 20.000 spil): før Svær 6,19, Mellem 6,31, Let 8,35. Efter, seed 1: Svær 5,55, Mellem 6,74, Let 8,71 (sejre 11.745 / 6.326 / 2.329). Seed 2: 5,52 / 6,71 / 8,71.

**Ruby** (produktionsbotten, `bots:duplicate`, 400 deals × 4 pladser, felt Mellem): Svær − Mellem −1,51 ± 0,33 (seed 1) og −1,38 ± 0,31 (seed 2), Mellem − Let −1,26 ± 0,42 og −1,92 ± 0,40. Samme rækkefølge som Rust. Kørslen er kort og derfor bredere.

Med J♦ −10 slået til var Svær − Mellem −0,88 ± 0,04 (samme hånd, felt Mellem), fordi Svær ikke regnede J♦'s −10 med. Det gør den nu (se nedenfor).

### Hvad der blev ændret, og hvorfor

Fundet med `regret` (hvilke regler taber mest) og bekræftet med `tune`. Tal i tabellen er, hvad det *koster* Svær at slå reglen fra (Δ point pr. runde på samme hænder, felt Mellem og Svær samlet, seed 1 / seed 2; positivt betyder, at reglen hjælper):

| Svær | Koster at slå fra |
|---|---|
| Billigste udspil (i stedet for "laveste kort") | +0,60 / +0,59 |
| Tag stikket tidligt, når det er sikkert | +0,25 / +0,25 |
| Q♠ i byttet medmindre 5+ andre spar (mod 3) | +0,19 / +0,20 |
| Afkast efter chance for at vinde senere | +0,08 / +0,08 |
| Byt fra farver med færrest lave kort | +0,08 / +0,09 |
| Byttets renoncer (Anders' modtagne kort-regel, inkl. de andre pladser) | +0,075 / +0,077 |
| – heraf giverens kort ud over den generelle regel | +0,003 / +0,006 |
| Stop månen | +0,03 / +0,03 |
| Fuld kortoptælling (mod Mellems grove) | +0,007 / +0,005 |
| Spar mod Q♠'s kendte plads [kilde S2] | −0,013 / −0,015 |
| Gå efter månen | −0,005 / −0,006 (inden for støj) |
| Sikre høje kort [udledt] (nu fjernet) | −0,004 / −0,005 |

Mellem: den grove modtagne kort-regel hjælper +0,027 / +0,030 (+0,05–0,06 mod et Mellem-felt).

**Justerede tal** (hvad det koster at gå tilbage til det gamle tal, held-out seed 2):

| Tal | Før | Efter | Svær | Mellem | Let |
|---|---|---|---|---|---|
| Risikabel | 2,0 | 1,0 | +0,073 | +0,027 | −0,024 |
| Månetrussel | 14 | 17 | +0,040 | +0,044 | – |
| "Højt kort" i risikoreglen | 10 og op | ethvert kort | – | +0,034 | +0,077 |
| Sværs afkast: træk pr. kort i farven | 0,05 | 0,2 | +0,038 | – | – |
| Sværs Q♠-grænse i byttet | 3 | 5 | +0,20 | – | – |

Prøvet uden gevinst og derfor uændret: Mellems Q♠-spor (0,2), Sværs spar-spor (0,4), renonce-planens håndstørrelse (10), Sværs "sikkert stik"-grænse (0,3; 0,2–0,4 er ens), hjerter i afkast (0,6), giverens renonce-chancer (målt) og Mellems 0,5 (0,7–1,0 er ens).

### Spar-pres med højeste spar (Anders, 2026-10-25)

Mellem og Svær jager nu Q♠ med den højeste spar under damen i stedet for den laveste (§5 udspil 2, §6, §7). Samme hånd, samme plads (Rust, 50.000 deals × 4 pladser; Δ Svær − Mellem, ± 0,03), før → efter:

| Felt, seed | Let | Mellem | Svær | Svær − Mellem |
|---|---|---|---|---|
| Mellem, 1 | 8,36 → 8,34 | 6,84 → 6,83 | 5,58 → 5,57 | −1,26 → −1,26 |
| Mellem, 2 | 8,33 → 8,31 | 6,84 → 6,83 | 5,57 → 5,56 | −1,27 → −1,27 |
| Svær, 1 | 9,60 → 9,57 | 8,42 → 8,40 | 7,08 → 7,07 | −1,34 → −1,33 |
| Svær, 2 | 9,58 → 9,57 | 8,41 → 8,39 | 7,07 → 7,06 | −1,34 → −1,34 |

Ændringen er neutral til en anelse bedre (0,01–0,02 point pr. runde for alle niveauer, inden for støj på hvert tal). Feltet bruger også den nye regel, så tallene er den nye verden mod den gamle. Afstanden mellem niveauerne er uændret.

### Svær regner J♦ −10 med (Anders, 2026-10-25)

Svær tager J♦ på stikkets netto (§6). Samme hånd, samme plads (Rust, 50.000 deals × 4 pladser; point pr. runde, Δ ± 0,03), før → efter:

| Felt, seed, J♦ −10 | Mellem | Svær | Svær − Mellem |
|---|---|---|---|
| Mellem, 1, til | 4,37 → 4,37 | 3,49 → 2,69 | **−0,88 → −1,68** |
| Mellem, 2, til | 4,36 → 4,36 | 3,50 → 2,71 | **−0,86 → −1,65** |
| Svær, 1, til | 5,48 → 6,22 | 4,63 → 4,56 | **−0,86 → −1,66** |
| Svær, 2, til | 5,49 → 6,22 | 4,60 → 4,54 | **−0,89 → −1,68** |

Uden reglen er alle tal uændrede (reglerne gælder kun, når J♦ −10 er slået til). At slå Sværs J♦-regning fra koster +0,75 point pr. runde under reglen (seed 1 og 2). I et Svær-felt tager Svær-botterne J♦ fra hinanden og fra Mellem/Let, så Mellem og Let får flere point der.

### Til Anders

- **Spar mod Q♠'s kendte plads** [kilde S2] koster Svær 0,013–0,015 point pr. runde mod botter (samme fortegn på begge seeds). Anders har besluttet, at den bliver, og at botterne presser med den højeste spar under damen (se nedenfor) [Anders, 2026-10-25].
- **Gå efter månen** er neutral (inden for støj). Den er beholdt, for mod mennesker er truslen en del af spillet.
- **Stop månen** [kilde S1, S12] betaler sig nu også for Svær (+0,03), efter at truslen er sat til 17.
- **Q♠ i byttet:** for Svær er kildens tal 3 hævet til 5 (byt damen væk, medmindre der er 5 andre spar). Det er et tal i en [kilde]-regel, ikke en fjernet regel. Mellem bruger stadig 3.
- **"Sent i runden: spil exitkort"** [kilde S1] er ikke fjernet, men gjort til en del af "billigste udspil", der spiller exitkort i hele runden. Den gamle udførelse (altid det højeste exitkort, kun de sidste 4 stik) kostede 0,1 point pr. runde mod den nye.
- **Sikre høje kort** [udledt] er fjernet, som foreslået sidst: den gav intet (−0,005).
- **Let:** risikabel = 2,0 ville være en anelse bedre for Let alene (0,02). Der er beholdt ét fælles tal, 1,0.
