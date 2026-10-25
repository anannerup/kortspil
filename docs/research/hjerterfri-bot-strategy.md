# Hjerterfri-bot: strategi (research til ticket 20)

Status: research, oktober 2026. Intet her er besluttet; beslutninger tilføjes nederst efter grilling med Anders.

Mærker:
- **[kilde]** står i en kilde der er linket.
- **[udledt]** min egen slutning fra kilder eller kode.
- **[ukendt]** fandt ikke svar.

## Kilder

| # | Kilde | Type | Kvalitet |
|---|---|---|---|
| S1 | [Wikibooks: Card Games/Hearts/Strategy](https://en.wikibooks.org/wiki/Card_Games/Hearts/Strategy) | Strategiguide (fællesskab) | Middel. Konkrete tommelfingerregler. |
| S2 | [Rarepike: How to Win at Hearts](https://rarepike.com/how-to-win-at-hearts) | Strategiguide (spilside) | Middel. Overlapper S1. |
| S3 | [Carleton College comps 2024–25: "Breaking Hearts"](https://www.cs.carleton.edu/cs_comps/2425/dmusicant/breakingHearts/) | Studenterprojekt, sammenligner Hearts-AI'er | Middel. Kun én gevinstprocent oplyst. |
| S4 | [Sturtevant: Hearts-program (movingai.com)](https://www.movingai.com/hearts.html) | Forskerens egen side | God. Sturtevant er en af de mest citerede forskere i Hearts-AI. |
| S5 | [Sturtevant & White: Feature Construction for RL in Hearts (CG 2006/2007)](https://www.springerprofessional.de/feature-construction-for-reinforcement-learning-in-hearts/2891304) | Konferenceartikel, kun abstract læst | God kilde, men jeg har kun læst resuméet. |
| S6 | [Sturtevant: An Analysis of UCT in Multi-Player Games (CG 2008)](https://www.cs.du.edu/~sturtevant/papers/sturtevant2008uct.html) | Konferenceartikel, kun abstract/slides | Som S5. |
| S7 | [Long, Sturtevant, Buro, Furtak: Understanding the Success of PIMC (AAAI 2010)](https://mlanthology.org/aaai/2010/long2010aaai-understanding) | Konferenceartikel, kun abstract | Som S5. |
| S8 | [Rebstock m.fl.: Improving Search with Supervised Learning in Trick-Based Card Games (arXiv 1903.09604)](https://arxiv.org/pdf/1903.09604) | Artikel; kun citeret via søgeresultat | Svag for mig: PDF'en kunne ikke læses. Oplyser at PIMC er brugt på Hearts (Sturtevant 2008). |
| S9 | [StephenA0/Hearts-Player (GitHub)](https://github.com/StephenA0/Hearts-Player) | Open source-bot, README | Svag-middel. Kun README læst. |
| S10 | [Solitaire Bliss: Hearts](https://www.solitairebliss.com/hearts) | Spilside der beskriver sine sværhedsgrader | Middel. Konkret beskrivelse af tre niveauer. |
| S11 | [Wikipedia: Microsoft Hearts](https://en.wikipedia.org/wiki/Microsoft_Hearts) | Leksikon | Siger intet om Windows-AI'ens strategi. |
| S12 | `docs/rules/RULES.en.md` del 3 | Projektets regler | Regelkilde. |

Ikke fundet **[ukendt]**: hvordan Windows Hearts' computerspillere vælger kort; kildekoden til gnome-hearts/KDE's spillere (ikke læst); fulde tekster af S5–S8 (PDF'er gav 404 eller kunne ikke læses).

## Menneskelig strategi pr. fase

### Bytte (pass)

- Giv de farligste kort væk: Q♠ uden beskyttelse, A♠/K♠ uden lave spar, høje hjerter (A♥, K♥, Q♥). **[kilde S1, S2]**
- Q♠ kan beholdes med nok lave spar. S2 siger 3+ lave spar (fx 3♠ 5♠ 7♠); S1 siger blot "mange". Den nuværende bot kræver 4. **[kilde S1, S2; tallet 4 er botens eget, ikke fra kilde]**
- Lav en renonce (tom farve) i klør eller ruder ved at give alle kort i den korteste farve væk, helst tre af samme farve. **[kilde S1, S2]**
- Gør dig aldrig kort i spar under damen; behold lave spar (knægt og under). **[kilde S1]**
- Behold lave hjerter (2–6) til at dukke med. **[kilde S1]**
- Overvej at give 2♣ væk, så du kan smide en høj klør i første stik. **[kilde S1]**
- Læs kortene du får: mange i én farve tyder på en renonce-plan hos giveren; lave, ligegyldige kort kan betyde at giveren går efter månen. **[kilde S1, og søgeresultat]**
- Retning (venstre/højre/over/ingen): ingen af de læste kilder giver konkrete råd pr. retning. **[ukendt]** Udledt: du ved hvem der har fået dine kort, så Q♠ til venstre betyder at spilleren efter dig har den. **[udledt; S1 nævner "hvis du gav Q♠ til en spiller, kan du trygt tage stik når du spiller efter dem"]**

### Udspil (lead)

- Tidligt: spil korte farver fra toppen for at blive renonce. **[kilde S1, S2]**
- Uden A♠/K♠/Q♠: spil lave spar for at tvinge Q♠ frem ("flushing"). **[kilde S1, S2]**
- Spil ikke A♠/K♠ ud mens Q♠ er ude, medmindre du vil have den til en anden. **[kilde S2]**
- Med en lang farve af lave kort: spil lavt og tving de andre op. Med kun mellemkort: spil det næstlaveste, gem det laveste. **[kilde S2]**
- Sent i runden: undgå at vinde stik når modstanderne har ca. 3 kort tilbage, så du ikke sidder fast med udspillet. Gem lave kort i to farver til slutningen. **[kilde S1]**
- Første hjerterstik efter brud: spil lavt; i andet er mellemhjerter som regel sikre. **[kilde S1]**

### Bekende (follow)

- Duk: spil lavt for ikke at vinde stik med hjerter eller Q♠. **[kilde S2]**
- Sidst i stikket og stikket er rent (ingen strafpoint): tag det med et højt kort for at komme af med det. Er der hjerter i: spil lavt. **[kilde S2; S1 siger "sidst og tvunget til at vinde: spil det højeste"]**
- Efter de første 2–3 stik: spil ikke høje kort, medmindre du går efter månen eller sidder sidst og Q♠ stadig er ude. **[kilde S1]**
- J♦ −10 (husregel): spil lav ruder når ruder spilles ud; tag J♦ med en højere ruder hvis den kommer. **[kilde S1 — S1 skriver J♦, samme kort som Anders' bord]**

### Afkast (discard, renonce)

- Smid Q♠, høje hjerter og høje spar på stik du alligevel taber. **[kilde S1, S2]**
- Tag dine es i ikke-hjerterfarver tidligt, før hjerter kan smides på dem. **[kilde S2]**

### Månen (shoot the moon) og at stoppe den

- Forsøg kun med de fleste høje hjerter (10–A) plus en lang farve (6–7+ kort med es og flere honnører). **[kilde S1, S2]**
- Overvej det når du ligger bagud og har brug for et sving på 26. **[kilde S2]**
- Mislykket forsøg er katastrofalt; ét hjerter hos en anden ødelægger det. **[kilde S1, S2]**
- Stop det: gem 2–3 stærke kort til de sidste stik, så du kan "stjæle" et hjerter. Advarselstegn: nogen giver dig meget lave kort, eller spiller høje kort ud uden at frygte hjerter. **[kilde S1]**
- At tage ét point for at stoppe en måne er bedre end 26. **[kilde S12 §3.6]**

### Slutspil: score-bevidsthed nær 100

- Ingen af de læste guides giver konkrete råd. **[ukendt i kilderne]**
- S9's forfatter nævner som mangel at botten "ikke beskytter mod at spillet slutter, når den sandsynligvis taber". **[kilde S9]**
- Udledt: nær slutscoren skifter målet fra "få færrest point i runden" til "hvem ender lavest". Fx: hvis spilleren der fører kan skubbes over 100 med Q♠, er det den rigtige modtager; en spiller tæt på 100, der ligger bagud, vil ikke afslutte spillet; en måne kan afslutte spillet ved at give de andre 26. **[udledt]**

## Computer-tilgange

| Tilgang | Hvad | Styrke | Pris (kode/CPU) |
|---|---|---|---|
| A. Simple regler | Fx "spil højeste kort der stadig taber, ellers laveste". | S3: overraskende stærk ("very strong") af en simpel regel. **[kilde S3]** | Meget lav. Nuværende bot er her. **[udledt]** |
| B. Rige regler (~20 regler) | Renonce-plan, Q♠-styring, kortoptælling. | S3: bedst af fire typer, vandt "over 50%" af spillene mod de andre. **[kilde S3]** S9 bruger samme idé med kortoptælling og slutninger. **[kilde S9]** | Lav CPU, mellem kode. Kræver hukommelse af spillede kort. **[udledt]** |
| C. Kortoptælling + slutninger | Husk alle spillede kort; udled renoncer (en spiller der ikke bekender er renonce). | Del af B og forudsætning for D. Solitaire Bliss' "Hard" gør det. **[kilde S10]** | Lav. Kræver at botten får spillet historik. **[udledt]** |
| D. PIMC / Monte Carlo-sampling | Træk tilfældige fordelinger af de skjulte kort, der passer med det kendte; løs hver som åbent spil; vælg kortet med bedst gennemsnit. | Har slået kommercielt program: Sturtevants program vs Hearts Deluxe (højeste niveau), 90 spil, 2003: gns. 55,8 vs 75,1 point pr. spil, bytte slået fra. **[kilde S4]** Kendte svagheder: "strategy fusion" og "non-locality". **[kilde S7 via søgeresultat]** Sturtevant: "kendte problemer med Monte Carlo-håndgenerering". **[kilde S4]** | Høj kode, høj CPU (sekunder pr. træk). S3's MCTS-agent med 3 sekunder pr. træk havde "begrænset succes". **[kilde S3]** |
| E. ISMCTS / UCT | Træsøgning over informationsmængder. | Sturtevant: UCT lige så god eller bedre end tidligere algoritmer i flere spil, men Hearts-forbedringer "mest uvirksomme" og i nogle test svagere end maxn. **[kilde S6, slides]** | Høj. |
| F. Indlæring (TD/neural) | Lær en værdifunktion fra mange spil. | S5: lærende spiller slog et af de stærkeste søgebaserede Hearts-programmer. **[kilde S5, abstract]** S3's case-baserede agent (5.000 spil fra WorldOfCardGames): svagere men "sjovere at spille mod". **[kilde S3]** | Meget høj (træning, data, model i Ruby?). **[udledt]** |

Udledt samlet vurdering: til et familiebord er B+C den realistiske sweet spot — billig, forklarlig, testbar og deterministisk, og S3 tyder på at den kan være stærkere end en naiv Monte Carlo. D er mulig senere som "Svær", men koster meget og er ikke nødvendigvis stærkere uden stort arbejde. **[udledt]**

## Hvad den nuværende bot gør (app/models/hjerterfri/bot.rb)

| Fase | Nuværende bot | I forhold til kilderne |
|---|---|---|
| Bytte | Q♠ væk med under 4 lavere spar; ellers A♠/K♠ hvis den ikke har Q♠; så højeste hjerter; så højeste kort. | Dækker Q♠/høje spar/høje hjerter. Mangler: renonce-plan (giv en hel kort farve), behold lave hjerter/spar, 2♣, retning. **[udledt]** |
| Udspil | Laveste kort, helst ikke hjerter, aldrig Q♠/K♠/A♠ hvis andet findes. | Mangler: spil korte farver for renonce, spil lave spar for at jage Q♠, slutspil-kontrol. **[udledt]** |
| Bekende | Højeste kort der stadig taber; ellers sidst i stikket højeste, tidligere laveste; undgå Q♠. | Svarer til "very strong"-reglen i S3. Tager ikke højde for om stikket er rent. **[udledt]** |
| Afkast | Q♠, så højeste hjerter, så højeste kort. | Som kilderne. Mangler: smid A♠/K♠ mens Q♠ er ude; afkast for renonce. **[udledt]** |
| Månen | Forsøger aldrig, stopper aldrig bevidst. | Som S9. **[udledt]** |
| Score/slutspil | Ingen. | — |
| J♦ −10 | Ingen (kender ikke reglen; den er ikke i view). | — |
| Hukommelse | Ingen; ser kun aktuelt og sidste stik. Antager Q♠ altid ude hvis den ikke har den. | — |

## Hvad hver tilgang kræver af motoren

Nuværende view (`Round#view_for`): egen hånd, kortantal, aktuelt stik, sidste stik + vinder, `to_act`, `legal_moves`, `hearts_broken`, `pass_direction`, `own_pass`, `received_cards`, `points` (tom indtil runden er færdig), `moon_shooter`, `jack_of_diamonds_taker`. **[kilde: kode]**

| Behov | Bruges til | Findes i view i dag? |
|---|---|---|
| Alle spillede stik i runden (hvem spillede hvad) | Kortoptælling, renonce-slutninger, "er Q♠ ude", måne-detektion | Nej. Kun aktuelt + sidste stik. Data findes i motoren (`@tricks`). **[kilde: kode]** |
| Point taget i runden pr. plads (`points_taken`) | Måne-detektion/-forsøg | Nej i view, men findes på `Round` og er offentligt. **[kilde: kode]** |
| Spillets samlede score pr. plads + slutscore | Slutspil nær 100 | Nej; ligger på `Game`. **[kilde: kode]** |
| Regel-toggles (`queen_breaks_hearts`, `jack_of_diamonds_minus_ten`) | J♦-adfærd, hjerterbrud | Nej i view. **[kilde: kode]** |
| Hvem man gav til (retning + egne givne kort) | "Jeg gav Q♠ til venstre" | Ja (`pass_direction`, `own_pass`). **[kilde: kode]** |
| Tilfældighed (seed) | Variation / Monte Carlo | Bot er deterministisk; ville skulle injiceres som `random:` iht. CLAUDE.md. **[udledt]** |

Snydegaranti: botten læser kun `view_for(seat)`, som efter kodekommentaren aldrig indeholder andre pladsers kort. Al ny input (historik, score, regler) er offentlig information, så den kan tilføjes uden at give botten skjult viden. **[udledt fra kode]**

## Sværhedsgrader: muligheder

- Kommercielle spil har typisk 3–4 niveauer (Easy/Medium/Hard/Expert), uden at oplyse hvordan de adskiller sig. **[kilde: Microsoft Store-listinger via søgning]**
- Solitaire Bliss: Let = grundregler, ingen tælling; Mellem = renonce-plan, aggressiv Q♠-jagt, husker egne givne kort; Svær = tæller alle spillede kort, gætter hvem der har Q♠. **[kilde S10]**
- S3 fandt at den stærkeste agent ikke var den sjoveste; den case-baserede var "sjovere". **[kilde S3]**
- Muligheder for dette projekt **[udledt]**:
  1. Ét niveau ("god familiespiller").
  2. To–tre niveauer bygget som lag af regler (Let ⊂ Mellem ⊂ Svær), valgt pr. bord eller pr. bot af værten.
  3. Et niveau + lidt tilfældighed, så botten ikke er forudsigelig.

## Beslutninger (grilling med Anders, oktober 2026)

Afgjort i runde 1–3. Spillereglerne for botten pr. niveau står i `docs/bots/hjerterfri-strategy.md`.

- **Niveauer:** Let, Mellem og Svær. De er lag, så hvert niveau kan alt fra niveauet under.
- **Hvem vælger:** værten vælger niveau pr. bot. En ny bot starter på **Mellem**.
- **Visning:** pladsen viser niveauet, fx "Bot · Svær".
- **Botten spiller for sig selv** og prøver at få færrest point. Den ved ikke, at den aldrig kan blive vinder (se GLOSSARY.md), og tager ikke hensyn til det.
- **Kun offentlig information:** botten må kun bruge det, et menneske på samme plads kan vide. Det er egen hånd, egne byttede og modtagne kort, spillede kort, point taget i runden, den samlede score og bordets regler. Den ser aldrig andres kort.
- **Hukommelse:** Svær husker alt inden for runden (kortoptælling og renoncer). Let og Mellem husker mindre (se strategidokumentet). Svær spiller optimalt eller tæt på.
- **Let er ikke tilfældig:** den prøver at vinde med simple regler, men uden hukommelse og uden plan. Den spiller aldrig absurd.
- **Variation:** botten vælger lidt tilfældigt mellem næsten lige gode træk. Hvor stor variationen er, ligger fast pr. niveau i koden og er ikke en indstilling i UI'et. Tilfældigheden injiceres (`random:`), så tests er deterministiske.
- **Tempo:** ingen bevidst ventetid. Botten er så hurtig, som den kan være, og klientens animationer sætter tempoet. `Bot#delay` (0,8–1,2 s) skal væk.
- **Bot der overtager en plads:** når en spiller har forladt spillet, overtager botten pladsen og dens stilling og spiller på **Let**. Det er midlertidigt, og Anders vender tilbage til det.
- **Hvordan Svær bygges:** kun med regler og kortoptælling, ikke Monte Carlo. Monte Carlo er en mulig senere opgradering, og kun hvis en bot-turnering viser, at den er bedre.
- **Dokumentation:** strategien skrives ned spilneutralt, hvor det giver mening (undgå stik, renonce, kortoptælling), så den kan genbruges til nolo og sol i es-makker. Det, der kun gælder hjerterfri, markeres.
- **Byt (Mellem og Svær):** reglerne fra runde 3 er godkendt: månehånd (kun Svær), spar dame, es/konge i spar, renonce i ruder eller klør (kun ved 3 kort eller færre), høje hjerter væk og lave beholdes, og resten de højeste kort. Let bytter uden renonce-plan.
- **Månen:** Svær går kun efter månen med en klar månehånd. Mellem og Svær forsøger at stoppe en måne. Let gør ingen af delene.
- **Slutspil nær slutscoren (kun Svær):** Svær spiller på den samlede score som en rigtig spiller. Den må gerne afslutte spillet, når den selv fører, fx ved at give spar dame til en spiller tæt på 100.
- **Detaljerne om spar dame** er afgjort af agenten ud fra kilderne og dokumenteret i strategidokumentet. Anders vil ikke spørges på det niveau.
- **Husregler:** botten spiller efter bordets regler (spar dame bryder hjerter, ruder knægt −10). Mellem og Svær spiller aktivt efter ruder knægt, når reglen er slået til.
- **Måling:** en automatisk bot-turnering (seedede spil, niveau mod niveau). Svær skal have færrest point i snit og Let flest.

## Parked ideas (October 2026, not decided)

- **Tuning the rule bots by self-play:** let the bots play hundreds of thousands of spil against each other and search for the best values of the [valgt] numbers (moon hand, moon threat, "late in the runde", the Q♠ protection threshold). The rules stay readable and reusable for es-makker.
- **A bot trained by self-play** (in the style of DouZero/Pluribus, not AlphaZero, because hjerterfri has hidden cards). It needs:
  - a fast simulator, ported from the Ruby engine and tested against it
  - training with PyTorch on the Mac
  - an ONNX model run from Rails
  - an extra level, e.g. "Ekspert"

  Downside: it can't be documented or tuned by hand, and it can't be reused as rules. It goes against the decision to build Svær with rules only. Anders decided to wait.
