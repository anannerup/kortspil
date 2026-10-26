# Es-makker-bot: niveauer, træning og "Vis kort"

Besluttet med Anders (grilling, 26. oktober 2026, ticket 12). Selve spillestrategien er ikke skrevet her: den findes ved selvspil og ved regler fra kilderne, og Anders retter den ved at spille med "Vis kort".

Mærker:
- **[Anders]** besluttet af Anders.
- **[kilde]** står i en kilde (whist-litteratur; kilderne samles i `docs/research/esmakker-bot-strategy.md`).
- **[valgt]** valgt af agenten; må justeres efter målingerne.

## 1. Niveauer

| Niveau | Hvad det er | Hvem det er til |
|---|---|---|
| **Let** | Et tidligt stadie af træningen (eller en simpel regelbot). **[Anders]** | Begyndere. |
| **Mellem** | Et senere stadie af træningen, valgt efter målt styrke. **[Anders]** | |
| **Svær** | Læsbare regler, der spiller optimalt *som et menneske*: forståeligt for en makker. Først regler fra kilderne, siden forbedret med regler udledt af nettet. **[Anders]** | Den bedste makker for et menneske. |
| **Umenneskelig** | Det færdige neurale net. Sindssygt svær, må spille som intet menneske. **[Anders]** | Stærkest med Umenneskelig som makker. |

Let ⊂ Mellem ⊂ Svær gælder som i hjerterfri: et højere niveau skal slå et lavere i samme-hånd-målingen.

Es-makker er et makkerspil: spiller man uforståeligt, forstår makker det ikke og spiller ikke med **[Anders]**. Derfor er Svær regler, og derfor trænes nettet også med Svær som makker (§3).

## 2. Den første bot

Før træningen findes en bot uden logik, så es-makker kan spilles med bots nu **[Anders]**:

- Meldingsrunden: melder 9, hvis det er lovligt, ellers pas. Går aldrig med på sol.
- Alt andet (trumf, kaldt es, kat, bytte, fordækt, stik): et tilfældigt lovligt træk.
- **Banker aldrig.** Det gælder alle niveauer, også de trænede **[Anders]**.

## 3. Træning

- **Hvor:** Anders's stationære (Windows, RTX 3070), når han ikke gamer. Koden ligger i git (`tools/`), mellemstadierne ligger kun på maskinen **[Anders]**.
- **Hvordan:** selvspil som AlphaGo/DouZero: et net vurderer hvert lovligt træk, mange spil spilles parallelt, GPU'en træner **[Anders]**. Python + PyTorch **[Anders]**.
- **Motoren** porteres til Python og holdes lig Ruby-motoren med en paritetstest, som botlab'en gør for hjerterfri **[valgt]**.
- **Start og stop:** én kommando hver; træningen gemmer, hvor den er nået til, med faste intervaller og fortsætter derfra **[Anders]**.
- **Makker:** en del af spillene (start 25 %, tunes) har Svær-reglerne på de andre pladser, så nettet lærer at spille med et menneske, der spiller optimalt **[Anders]**.
- **Botten kigger aldrig:** nettet får kun det, en spiller på pladsen må vide, heller ikke under træningen. Ingen andres kort; hvem der er es-makker, først når esset falder **[Anders]**.
- Nettet forudsiger også stik pr. plads og rundens point, så "Vis kort" kan vise dem **[Anders]**.

## 4. Fra net til produktion

- **Svær:** regler udledes af nettet, så det er kode og ikke en stor fil **[Anders]**. Tabet mod nettet måles med samme-hånd-målingen.
- **Umenneskelig, Mellem, Let:** vægtene committes i repoet, hvis de er under ca. 20 MB, og regnes ud i ren Ruby. ONNX Runtime kun, hvis det måles for langsomt **[valgt; Anders: ok]**.

## 5. "Vis kort"

- Kun for admin, kun i spil mod bots (ingen andre mennesker ved bordet) **[Anders]**. Slået til fra start; kan slås fra i panelet **[Anders]**.
- Begge spil, bygget én gang i bordets fælles skal; hvert spil leverer sine egne linjer **[Anders]**.
- Viser bottens kort, og ved hver beslutning hvad botten har tænkt sig: hvad den vil melde, hvor mange stik den tror den selv og makker tager, hvem den gætter er makker, og hvor mange point den forventer for runden **[Anders]**.
- Ændrer ikke, hvad botten ved.

## 6. Svær: regler (forslag)

Forslag fra ticket 03, ikke besluttet af Anders. Kilderne S1–S18 står i `docs/research/esmakker-bot-strategy.md`; **[kilde Sx]** henviser dertil, **[udledt]** er en slutning derfra, **[valgt]** er et tal eller en regel, agenten har valgt, og som selvspillet skal justere. Alle regler gælder vores bord (REGLER §2.0). Svær banker aldrig (§2).

Målet er, at en menneskelig makker kan forudsige Svær: den spiller "et ligefremt, forståeligt spil" og følger de gængse regler for udspil og bekendelse, så kortene selv er oplysning **[kilde S6, princip 12]**. Ingen falske kort, heller ikke som modspiller **[valgt]**.

### 6.1 Kortoptælling og den skjulte makker

- Svær husker alle spillede kort, hvem der spillede dem, og hvilke pladser der har vist renonce i en farve **[kilde S3, S6 princip 18]**.
- **Makkergæt** (for melderen og modspillerne, indtil esset falder) **[valgt, ud fra S5, S12, S13]**: hver anden plads får vægten 1, og katten 3/13 (esset ligger i katten med 3/42 ≈ 7 %).
  - En plads, der viser renonce i den kaldte farve: vægt 0.
  - En plads (ikke melderen), der selv spiller trumf ud: vægt × 4.
  - En plads, der stikker eller overstikker et kort fra melderen, der ellers havde vundet stikket: vægt × 0,25.
  - Når esset falder, er makker kendt. "Vis kort" viser vægtene som procenter.
- Modspillerne bruger samme gæt om, hvem af de to andre der er makker.

### 6.2 Håndvurdering: forventede stik

Svær regner **egne stik** for hver mulig trumf (spar, hjerter, ruder, klør, trumfløs) **[kilde S9, tilpasset; tallene valgt]**:

| Del | Regel |
|---|---|
| Jokere | 1 pr. joker [kilde S1 §2.13: "en joker i udspillet giver et sikkert stik"] |
| Trumffarven (længde L) | E = 1; K = 1, hvis L ≥ 2; D = 1, hvis L ≥ 3; plus 1 pr. trumf ud over 3 [kilde S9, playing tricks] |
| Sidefarve, ikke kaldt | EK = 2, EKD = 3, ED = 1,5, E = 1, KD = 1, Kx = 0,5, K alene = 0 [kilde S9, quick tricks]. Plus 0,5 pr. kort ud over 4 i en farve med E og K, når trumf ikke er trumfløs [valgt] |
| Den kaldte farve (makker har esset) | K = 1, hvis farven har 2+ kort; KD = 1,5 [udledt: kongen bliver høj, når esset er faldet] |
| Trumfløs | jokere + quick tricks i alle fire farver + 1 pr. kort ud over 4 i en farve med EKD [valgt] |

**Forventede stik** S = egne stik + **2** for makker (det kaldte es plus ca. ét) **[valgt]**. Katten tæller ikke ved meldingen: man tager 3 op og lægger 3 væk, så den forbedrer hånden kun lidt **[Anders]**. De 2 er et startgæt, som selvspillet skal justere først.

Eksempel: trumf E K 8 6 3, sidefarve E 7 4, sidefarve K D 5, kaldt farve 9 4 2 → trumf 2 + 2 = 4, sidefarver 1 + 1 = 2, egne 6, S = 8.

### 6.3 Meldingsrunden

- **Højeste melding, Svær vil gå til** (Nmax) **[valgt]**: 8, hvis S ≥ 8; ellers det højeste N med S ≥ N + 0,5. Under 8: ingen stikmelding. Forsigtighed, fordi "at overmelde og ikke holde koster mere end at melde forsigtigt" **[kilde S3]**.
- **Meld så lavt som muligt:** Svær melder det laveste lovlige trin, der slår den nuværende melding, og kun op til Nmax. Overstik betaler 1 hver, et trin højere kun 0,5 **[udledt fra pointreglerne i S2]**.
- **"Det kan jeg selv":** melder en anden over Svær med en melding ≤ Nmax, siger Svær "det kan jeg selv" **[valgt]**.
- **Gode:** er klør den bedste trumf, eller højst 0,5 stik fra den bedste, og er S(klør) ≥ N + 1, melder Svær N gode i stedet for N. Gode fordobler både gevinst og bet, derfor 1 stiks margin **[udledt fra S2; margin valgt]**.
- **Halve:** Svær melder N halve, når hver af de tre farver, der ikke er den tænkte kaldte farve, har mindst 3 kort med mindst én af E, K, D, ingen farve er renonce, og S(trumfløs) ≥ N **[kilde S4: "3-4 gode kort i hver af de andre farver end makker-esset"; tallene valgt]**. Den kaldte farve vælges som i §6.4.
- **Vip:** kun når S ≥ N + 1 for alle fire farver og S(trumfløs) ≥ N, altså når hånden klarer meldingen med enhver trumf **[udledt fra S2; S5: vip "når man har meget stærke kort"]**. Ved vendingen stopper Svær ved det første kort, hvis trumf giver S ≥ N + 0,5 (joker: S(trumfløs)); ellers videre, og det tredje kort er trumf under alle omstændigheder **[valgt]**. Senere kort fordobler mere, men Svær jagter ikke faktoren.
- **Sol-meldinger:** se §6.7. Svær vælger blandt de lovlige meldinger (stikmeldinger op til Nmax og de sol-meldinger, hånden består testen til) den, den vurderer at have bedst mulighed for at vinde, vægtet med risikoen: størst forventet gevinst = P(hjem) × gevinst − P(bet) × tab **[Anders; P(hjem) skønnes ud fra S og sol-testen, valgt]**.
- **Ellers pas.**

### 6.4 Trumf, kaldt es, kat og fordækt

- **Trumf:** farven med størst S. Trumfløs, hvis S(trumfløs) ≥ meldingen + 1 og S(trumfløs) ≥ S(bedste farve) − 1: trumfløs fordobler gevinst og bet **[udledt fra S2; margin valgt]**. Ved en almindelig melding fordobler klør ikke, så klør vælges kun efter S **[kilde S2]**.
- **Kaldt es** **[udledt fra S15 og S9]**: blandt farverne, hvor Svær ikke har esset (vores regel: man må ikke kalde sit eget es, S2), og som ikke er trumf, vælges den korteste; ved lighed den, hvor Svær har det højeste kort (K'en bliver høj efter esset). Har Svær alle sideesser, kaldes trumfesset. Har Svær alle fire esser, kaldes et af dem, og Svær er selvmakker **[kilde S2]**.
- **Katten** **[udledt fra S9; valgt]**: Svær tager altid katten op og lægger 3 kort væk efter denne orden, til der er lagt 3:
  1. Aldrig trumf, jokere, esser eller K i den kaldte farve.
  2. Har Svær 4+ trumf: tøm den korteste sidefarve (ikke den kaldte), så den kan stikkes med trumf.
  3. Ellers: de laveste kort fra den sidefarve med færrest stik efter §6.2.
- **Fordækt:** er Svær renonce i den kaldte farve efter byttet, lægger den altid fordækt med sit laveste kort i den svageste sidefarve (aldrig trumf eller joker). Det er udspillet til makker **[kilde S1 §2.12, S2]**.
- **Halve, når Svær er esmakkeren:** vælger den farve med størst S som trumf (ikke trumfløs, S2) og lægger væk som ovenfor.

### 6.5 Stikspil som melder

0. **Gode eller svage trumf** **[Anders; grænsen valgt]**: gode trumf = mindst 5 trumf og to af E, K, D. Med gode trumf følger Svær planen nedenfor: træk trumf, spil makker ind, makker tager sine stik uden frygt for at blive stukket, og giver så udspillet tilbage til melderen. Med svage trumf spiller Svær makker ind tidligt (regel 2 før regel 1) og tager risikoen for, at makkers stik bliver stukket af trumf. Under "Afkast = Spil den her" er det netop her, makkers signal bruges **[Anders]**.
1. **Træk trumf fra toppen:** så længe modspillerne kan have trumf, og Svær har trumf, spiller den sin højeste trumf ud ("gængs spil: melderen kører sine høje trumf først") **[kilde S2, S5, S6 princip 13]**. Holder Svær ikke længere den højeste trumf ude, stopper trækket.
2. **Spil ind til makker:** derefter spilles det laveste kort i den kaldte farve, eller fordækt, så makker kommer ind og kan spille trumf igennem **[kilde S2: "lader esmakkeren komme ind, når hun har taget de trumfstik, hun kan"]**.
3. **Tag de sikre stik, så den lange farve:** kendte vindere (højeste ude i farven), så den længste sidefarve **[kilde S6 princip 1, S7]**.
4. **Joker:** spilles ud, når udspillet ellers ville give et tabt stik, eller når meldingen mangler netop det stik **[valgt]**.
5. **Ingen finesse, før meldingen er sikker:** først når *taget + sikre vindere ≥ meldingen*, må Svær finessere (kun med E-D) for overstik **[kilde S7]**.
6. **Har melderen meldt på trumf og ikke på sidefarver** (trumf ≥ 5, ingen sideesser): stik med trumf i korte farver frem for at trække al trumfen **[kilde S7]**.

### 6.6 Stikspil som makker og modspiller

Fælles regler for bekendelse **[kilde S6]**:
- **Andenhånd lavt**, medmindre Svær har en høj sekvens (så det laveste kort i den, der kan vinde).
- **Tredjehånd højt**, men kun så højt, at det vinder: laveste vindende kort; laveste af en sekvens.
- **Vinder makker stikket med sikkerhed** (højeste ude, eller sidst i stikket), lægger Svær sit laveste kort.
- **Kan Svær ikke bekende:** stik med laveste vindende trumf, hvis stikket ellers går til modparten og ikke er makkers sikre stik; ellers afkast (nedenfor).
- **Afkast er et signal, og bordet bestemmer hvilket** (bordets regel "Afkast", se nedenfor) **[Anders]**. Signalet læses af begge par: melder og makker, og de to modspillere **[Anders]**.
  - **Afkast = Renonce** (standard, sådan spiller Anders's bord): afkast i en farve betyder "jeg prøver at spille mig renonce i den her", så jeg kan stikke den med trumf senere **[Anders]**. Svær smider fra den farve, den vil være renonce i: den korteste sidefarve uden vindere, mens den har trumf tilbage **[valgt]**. Har en medspiller smidt en farve, spiller Svær den farve, så medspilleren kan stikke, så længe medspilleren kan have trumf; har en modspiller smidt den, undgår Svær den **[Anders; detaljer valgt]**.
  - **Afkast = Spil den her:** afkast i en farve betyder "spil denne til mig" **[Anders]**. Svær smider fra en farve med E eller KD, den gerne vil have spillet, og spiller den farve, en medspiller har smidt **[kilde S5, S11; detaljer valgt]**.
  - Begge: aldrig en ubeskyttet konge **[kilde S8]**.

**Som esmakker:**
- **Esset lægges første gang farven spilles** (også på fordækt) **[kilde S1, S12; S2: anbefalet, ikke tvunget]**. Svær holder det aldrig tilbage, så melderen kan regne med det.
- **I udspil, før esset er faldet:** spil esset ud og vis dig **[kilde S14]**.
- **Esmakker i forhånd:** spil som udgangspunkt trumf ud **[Anders]**.
- **Ellers:** spil trumf, så længe modspillerne kan have trumf ("er du makker, skal du alle dage spille trumf") **[kilde S5]**; derefter melderens viste farve (returnér: laveste fra 4+, højeste fra 2) **[kilde S6 princip 5]**; ellers egen længste farve.
- Når makkerskabet er kendt: "spil for to" **[kilde S5]**, dvs. melderen og makker bruger reglerne for fast makker ovenfor.

**Som modspiller:**
- **Tag dine sikre stik med det samme** (højeste ude, jokere), før melderne kan smide af **[kilde S7]**.
- **Søg ikke esset.** Uanset hvem man er makker med, skal man prøve at få point **[Anders]**.
- **Modspiller i forhånd** (første udspil): spil aldrig trumf ud. Hap et, to eller tre stik med det samme: spil dine andre esser og jokere, for du kommer nok ikke ind igen og får udspillet **[Anders]**.
- **Ellers:** spil fra din længste farve (højeste af en topsekvens, højeste fra en svag farve) **[kilde S6 princip 1–3, S8]**; spil igennem melderen op til den anden modspiller, når makker er kendt **[kilde S8]**. Ikke fra K alene øverst eller fra tenacer (ED, KB) **[kilde S7]**.
- **Sjældent trumf ud** **[kilde S7]**; undtagelse: Svær har den højeste trumf ude og kan trække to for én **[kilde S7]**.
- **Returnér din makkers farve** (den anden modspillers) som ovenfor **[kilde S6 princip 5]**.

### 6.7 Sol, ren sol, bordlægger og ren bordlægger

Rangen er vendt: es = 1 (lavest), 2, 3 … K = 13 **[kilde S2]**. Kildernes "toer" er vores es **[udledt]**.

**Sol-testen** pr. farve, med kortene c1 < c2 < … < cL **[kilde S7; tallene valgt]**:
- **Sikker farve:** renonce; eller c_i ≤ 2i − 1 for alle i (es, 3, 5, 7, 9 er sikker som en sekvens: S7's "spredte lave kort"). En farve med 4+ kort skal have esset **[kilde S7: "ikke med en lang farve uden toeren"]**.
- **Næsten sikker:** højst 2 kort og c1 ≤ 6 **[kilde S7: korte farver kan risikeres "selv uden kort under 5 eller 6"]**; eller et højt kort med mindst 2 lavere kort under, hvor de lavere er sikre **[kilde S7, Napoleon]**.
- **Farlig:** resten.
- Jokere tæller ikke imod: de kan smides på ethvert stik **[kilde S2, REGLER §2.13]**.

| Melding | Svær melder (eller går med), når |
|---|---|
| Ren bordlægger | alle farver sikre [kilde S7: åben misère kun, når "hver farve indeholder toeren, og alle kortene er lave nok"] |
| Bordlægger | alle farver sikre undtagen højst én singleton (den giver højst ét stik) |
| Ren sol | ingen farlige farver og højst én næsten sikker |
| Sol | ingen farlige farver, eller én farlig farve med højst 2 kort (sol tillader ét stik) |

**Gå med:** melder en anden en sol-melding, og består Svær testen for samme melding, går Svær med; ellers som §6.3 **[valgt]**.

**Katten ved sol** (melder først, så dem, der gik med): læg de højeste kort fra de korteste farver væk **[kilde S7: smid høje kort i korte farver]**.

**Som sol-spiller** **[kilde S7]**:
- Udspil: en singleton, ellers det laveste kort i en sikker farve. Ikke det højeste af en tabende sekvens.
- Bekend med det højeste kort, der stadig er under stikkets højeste. Kan Svær ikke komme under, lægger den sit højeste kort i farven.
- Afkast: højeste kort i korte farver og enlige mellemkort; aldrig fra lange farver. Jokere smides, når der ikke er andet farligt at smide, og aldrig gemmes til sidst **[udledt fra REGLER §2.13]**.
- **Sol tillader ét stik:** tag det tidligt med et farligt højt kort, når Svær bagefter har et sikkert kort at spille ud **[udledt]**.
- **Flere sol-spillere:** er Svær selv sikker (alle tilbageværende farver sikre), spiller den som modspiller mod de andre sol-spillere, for hver af dem afregner med hende **[udledt fra S2]**.

**Som modspiller mod sol** **[kilde S7, S8]**:
- Første udspil: fra den korteste og svageste farve, et mellemkort (6 eller 7), ikke det laveste, medmindre det er singleton. Mod bordlægger: korteste farve, før hånden lægges op.
- Bliv ved med en farve, hvor sol-spilleren er lang; skift fra en farve, hvor hun tydeligvis er sikker (lagde et meget lavt kort på et højt).
- Modspillere, der spiller efter sol-spilleren, lægger deres højeste kort under hendes; dæk ikke hendes udspil, medmindre det er meget lavt (es, 2, 3).
- Afkast: tøm én farve, højeste kort først; smid ikke en farve, sol-spilleren er renonce i.
- Returnér den farve, en modspiller først spillede ud, men ikke den, sol-spilleren selv spillede ud.
- Mod bordlægger ser modspillerne hånden: spil den farve, hvor sol-spilleren har det kort, der lettest kan tvinges ind (højeste c_i − (2i − 1)) **[udledt fra S7: "det svage punkt"]**.

### 6.8 Hvad selvspillet skal måle først

- Makkerbidraget (2 stik) i §6.2 og marginerne i §6.3 **[valgt]**.
- Om "søg esset" (§6.6) vinder eller taber mod "spil længste farve" **[kilde S5 er delt]**.
- Sol-testens grænser (§6.7).
- Grænsen for gode trumf (§6.5 regel 0).

### 6.9 Besluttet efter forslaget

- **Bordets regel "Afkast"**: Renonce (standard) eller Spil den her. Påvirker kun bots; mennesker signalerer selv. Nettet får reglen som input **[Anders]**.
- Ingen søgen efter esset; modspiller i forhånd haper stik med esser og jokere og spiller ikke trumf; esmakker i forhånd spiller trumf (§6.6) **[Anders]**.
- Stik eller sol: den melding med størst risikovægtet forventet gevinst (§6.3) **[Anders]**.
- Selvspillet må justere tallene, men ikke reglerne, uden at spørge Anders **[valgt; ikke besvaret, kan rettes]**.
