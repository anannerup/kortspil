# Es-makker-bot: strategi fra kilderne (research til ticket 03)

Status: research, 26. oktober 2026. Grundlag for Svær-reglerne i `docs/bots/esmakker-strategy.md` §6. Intet her er besluttet af Anders.

Mærker:
- **[kilde Sx]** står i kilden (citat eller tæt gengivelse).
- **[udledt]** min egen slutning fra kilderne, vores regler eller en lille beregning.
- **[ukendt]** fandt ikke svar.

Vigtigt forbehold: der findes næsten ingen skreven strategi for netop es-makker. De danske kilder er regelsider og et forum. Strategien her er derfor lånt fra **klassisk whist** (samme kortspil uden meldinger), **solowhist/Napoleon** (meldinger, spil alene, misère = vores sol), **bridge** (håndvurdering, signaler) og **Schafkopf** (kaldt es og skjult makker, ligesom es-makker). Hvor jeg overfører en regel til es-makker, er overførslen [udledt], selv om reglen selv er [kilde].

## Kilder

| # | Kilde | Type | Troværdighed |
|---|---|---|---|
| S1 | Whistklubbens regelsæt, Esmakkerwhist (`docs/rules/sources/whistklubben-esmakkerwhist.txt`, [PDF](https://hilmarshelte.dk/Whistklubben/Regler_&_Vedtgter_Regelst_files/Whistregler_11.02.11.pdf)) | Klubregler | Høj for regler, ingen strategi. |
| S2 | `docs/rules/REGLER.da.md` §2.0 (Anders) | Vores bords regler | Gælder i kortspil. Én strategisætning ("gængs spil"). |
| S3 | [Madskristensen.dk: Whist](https://www.madskristensen.dk/laer-reglerne-til-whist/) (`docs/rules/sources/madskristensen-whist.txt`), afsnit "Strategi" | Dansk artikel | Lav-middel. Fem korte råd. |
| S4 | [HjerterEs.dk: Es-makker whist](https://hjerteres.dk/kortspil/es-makker-whist/) | Dansk regelside | Lav-middel. Ét strategiråd (halve). |
| S5 | [Pokernet.dk forum: "Whist-kyndige på pokernet?"](https://www.pokernet.dk/forum/whist-kyndige-paa-pokernet.html) | Forumtråd, danske es-makker-spillere | Lav. Erfarne spillere, men forskellige regler, og de er uenige. Eneste kilde til dansk es-makker-praksis ved bordet. |
| S6 | Cavendish (Henry Jones): *The Laws and Principles of Whist*, 18. udg. 1889, [Project Gutenberg #51039](https://www.gutenberg.org/ebooks/51039) | Klassisk lærebog | Høj. Standardværket om whist-spil i 1800-tallet; "18 principper". Uden meldinger og med fast makker. |
| S7 | R. F. Foster: *Foster's Complete Hoyle*, 1914, [Project Gutenberg #53881](https://www.gutenberg.org/ebooks/53881): "Solo Whist: Suggestions for good play" (inkl. Misère, Abundance, Spreads) og "Napoleon: Suggestions for good play" | Klassisk opslagsværk | Høj. Foster var den førende amerikanske whist-autoritet. |
| S8 | *Hoyle's Games Modernized* (1923), [Solo Whist, Wikisource](https://en.wikisource.org/wiki/Hoyle%27s_Games_Modernized/Solo_Whist), "A Few Maxims" | Klassisk opslagsværk | Middel-høj. |
| S9 | [Wikipedia: Hand evaluation](https://en.wikipedia.org/wiki/Hand_evaluation) (high card points, quick tricks, playing tricks, shortness points; citerer Klinger, Root, Goren) | Leksikon om bridge | Middel. Etablerede bridge-metoder, men for bridge. |
| S10 | [Wikipedia: Losing-Trick Count](https://en.wikipedia.org/wiki/Losing-Trick_Count) | Leksikon om bridge | Middel. |
| S11 | [Wikipedia: Signal (bridge)](https://en.wikipedia.org/wiki/Signal_(bridge)) | Leksikon om bridge | Middel. |
| S12 | [Pagat.com: Bavarian Schafkopf](https://www.pagat.com/schafkopf/bavarian.html) (John McLeod) | Regelside med taktik | Høj for et folkespil. Kaldt es og skjult makker. |
| S13 | [Wikibooks: Kartenspiele: Schafkopf](https://de.wikibooks.org/wiki/Kartenspiele:_Schafkopf), afsnit om taktik | Fællesskabsguide | Middel. |
| S14 | [Schafkopf-Palast: Lektion 3, "Wie ihr im Rufspiel zusammenfindet"](https://www.schafkopf-palast.de/lektion-3-wie-ihr-im-rufspiel-zusammenfindet/) | Kursusside | Lav-middel. |
| S15 | Kartlfreunde Weiterndorf: *Grundlagen Schafkopf* (PDF, [link](https://kartlfreunde.weiterndorf.info/wp-content/uploads/2018/11/Grundlagen-Schafkopf.pdf)) | Klubmateriale | Svag for mig: PDF'en kunne ikke læses; citatet kommer fra et søgeresultat. |
| S16 | [Wikipedia: Call-ace Whist](https://en.wikipedia.org/wiki/Call-ace_Whist) | Leksikon | Lav-middel. Kun regler. |
| S17 | Egen simulering (Python, 200.000 tilfældige hænder; scriptet er ikke committet) | Beregning | [udledt]; tallene er kun gennemsnit af tællemetoder, ikke af spillede stik. |
| S18 | [Cardrulesplus: How to Play Solo Whist](https://cardrulesplus.com/games/solo-whist/), kun set via søgeresultat | Spilside | Lav. |

Søgt uden held **[ukendt]**: Dansk Whist Forbund og danske whistbøger med strategi (ingen fundet online); kortdrengene.dk (siden er tom); pagat.com har ingen side om es-makker og ingen strategi på sin whist-side.

## 1. Håndvurdering og meldingsrunden

### Hvad kilderne siger

- **Meld realistisk:** "At overmelde og ikke holde koster mere end at melde forsigtigt." **[kilde S3]**
- **Sandsynlige stik frem for sikre:** "Det er bedre at foreslå [makkerspil] på to-tre sikre stik med stor sandsynlighed for flere end på præcis fire sikre." K x x, Q J 10 x og K Q "kan regnes med". **[kilde S7, Solo Whist: Proposing]**
- **Meld på bred styrke, ikke kun trumf:** i solowhist skal den, der foreslår makkerspil (ikke forhånden), melde "på generel styrke", og den, der tager imod, på trumfstyrke; ellers risikerer parret at stå "uden et stik i sidefarverne, når trumfen er trukket". **[kilde S7, Solo Whist: Proposing]**
- **Trumfstyrke:** "Fire trumf med to eller tre honnører kan kaldes stærkt; eller fem trumf, selv uden honnør. Fem trumf med to eller flere honnører er stor styrke." **[kilde S7]** Schafkopf: et farvespil anbefales "med mindst 5 trumf" **[kilde S13]**.
- **Spil alene på trumf, ikke på sidefarver:** "At melde solo på sidefarver alene, med kun en eller to trumf, er yderst farligt"; en melding på én farve kræver "mindst fem eller seks gode trumf". **[kilde S7, Solo: Calling]**
- **Tællemetoder fra bridge** **[kilde S9, S10]**:
  - *High card points:* E=4, K=3, D=2, B=1; 40 i alt. 25 point på to balancerede hænder er ca. 9 stik uden trumf; 33 er 12 stik.
  - *Quick tricks* (hurtige stik pr. farve): EK = 2, ED = 1½, E = 1, KD = 1, Kx = ½ (singleton K = 0).
  - *Playing tricks* (stik med den lange farve som trumf, uden hjælp fra makker): i den lange farve tælles E, K og D plus hvert kort ud over 3; i korte farver kun sikre vindere (E = 1, EK = 2, EKD = 3, KD = 1, KDB = 2).
  - *Shortness points* (når man har en trumftilpasning): renonce 3, singleton 2, doubleton 1 (Goren/Anderson-skalaen); andre skalaer giver renonce 5.
  - *Losing-Trick Count:* tab-stik pr. farve ud fra de tre højeste kort (højst 3 pr. farve; renonce 0, singleton uden es 1, Ex/KD 1, Kx 1½ osv.). Makkerparrets stik ≈ 24 − (egne tabere + makkers tabere). Bruges kun, når man har en trumftilpasning på 8+ kort, og overvurderer dronninger og ubeskyttede korte honnører.
- **Halve:** "giver typisk mening at melde, hvis man har 3-4 gode kort i hver af de andre farver end makker-esset" **[kilde S4]**.
- **Jokere:** "En joker i udspillet giver et sikkert stik" **[kilde S1]**.
- **Sol-meldinger (misère) er svære at vurdere:** "Den store vanskelighed ved misère er ikke at spille den, men at vurdere hvilke hænder der berettiger den." **[kilde S7]** Detaljer i §4.
- **Spil til stillingen** (Cavendish' princip 17) og risikoen ved meldinger fra forskellige pladser (S8: sikrest som første eller sidste, farligst som anden) **[kilde S6, S8]**. Ved es-makker spiller melderen altid ud, så S8's pladsargument gælder ikke direkte **[udledt]**.

### Hvad jeg udleder for es-makker

- Melderen tager stikkene sammen med **en ukendt makker, der har et bestemt es**, og med katten. Bridge-metoderne forudsætter en kendt makker med kendt styrke; her er makker en tilfældig hånd med ét es. **[udledt]**
- Tal fra S17 **[udledt]**: en tilfældig hånd har i snit 7,6 tab-stik (LTC), en hånd med et bestemt es 7,0. En hånd har i snit 0,71 jokere, og 56 % af hænderne har mindst én.
- Groft regnestykke **[udledt]**: melder med 16 HCP lader 24 HCP til de tre andre, i snit 8 hver. Makker har esset (4) plus ca. ⅓ af resten uden esset, i alt ca. 4 + 6,7 ≈ 10–11 HCP. Melder + makker ≈ 27 HCP, svarende til ca. 9 stik ifølge bridgens 25 → 9-tommelfingerregel (S9). En typisk 16-HCP-melderhånd (EKxxx i trumf, et sidees, KD i en sidefarve) har 6 egne stik efter playing tricks + quick tricks. Makker og katten skal altså bidrage med ca. 3 stik. Det er udgangspunktet for formlen i §6.
- **Gode** (klør er trumf, ×2) og en almindelig melding med klør som trumf giver samme spil; gode fordobler gevinst og bet og ligger højere på stigen. Er en melding god nok til at blive meldt, er den også god nok fordoblet, så har melderen klør som bedste trumf, skal hun melde gode **[udledt fra pointreglerne i S2]**.
- **Trumfløs** fordobler også (×2). Vælg det, når hånden tager lige så mange stik uden trumf som med **[udledt]**.
- **Lav melding betaler bedst** **[udledt fra pointreglerne i S2]**: indsatsen stiger kun 0,5 pr. trin, men hvert overstik giver 1. 8 med 10 stik giver 1 + 2 = 3, 10 med 10 stik giver 2. Bet koster indsatsen pr. manglende stik, så en høj melding koster også mere, når den går galt. Man skal altså melde så lavt som muligt og kun højere for at vinde meldingsrunden. Ved 8 er udbyttet groft *stik − 7,5*, så 8 betaler sig allerede ved ca. 8 forventede stik.
- **Vip** binder melderen til en trumf, hun ikke kender. Hånden skal klare meldingen med hver farve som trumf (og uden trumf, hvis en joker vendes), og senere kort giver større faktor (×2, ×4, ×8) både ved gevinst og bet **[udledt fra S2]**. Forummet bruger vip "når man har meget stærke kort", eller som sidste chance sent på aftenen **[kilde S5]**.

## 2. Spilføring: trumf, es, kat

### Hvad kilderne siger

- **Trumf:** "Den primære brug af trumfstyrke er at trække modstandernes trumf, så man kan få sin egen eller makkers lange farve hjem." Med fem eller flere trumf kan man spille trumf med det samme. **[kilde S6, princip 13]**
- "Gængs spil: melderen kører sine høje trumf først og lader esmakkeren komme ind, når hun har taget de trumfstik, hun kan." **[kilde S2]** Forummet: "Hvis du er med i meldingen og har første udspil: spil trumf." **[kilde S5]** Schafkopf: spillerparret begynder normalt med trumf **[kilde S12]**.
- Med EK og små trumf: spil en lille trumf først, så du beholder kontrollen og får udspillet efter tredje runde **[kilde S6]**. Foster til en melder, der spiller alene: "Har han gode farver, skal han sikre sig to runder trumf ved at spille esset." **[kilde S7]**
- **En melding på trumfstyrke:** tag stik ved at stikke med trumf frem for at trække trumf **[kilde S7]**.
- **Kom ind og træk trumf:** sidder melderne ikke med udspillet, skal de "ikke finessere, men komme ind så hurtigt som muligt og trække trumfen"; den største fare er, at modspillerne får seks stik på deres vindere, før melderne kommer til. Når trumfen er trukket, viser hver sin stærke farve ved at spille den én gang. **[kilde S7, Solo Whist: Finesse]**
- **Sekvenser, når makker sidder efter dig:** spil det højeste af sekvensen, ellers tror makker, at de højere kort sidder hos modstanderne, og bruger sit es unødigt **[kilde S7, Solo Whist: In General]**. Ved es-makker ved melderen ikke, hvor makker sidder, så reglen gælder for makker, når melderen er kendt **[udledt]**.
- **Finesse ikke før meldingen er sikker:** "Undgå generelt at finessere, indtil meldingen er sikret; brug det derefter til overstik." **[kilde S7]**
- **Hvilket es skal kaldes:** Schafkopf-praksis: vælg den farve, hvor du har færrest kort (mindst ét), og ved lighed den, hvor dit kort er højest **[kilde S15, via søgeresultat]**. Pagat og Wikibooks giver intet råd om valget **[kilde S12, S13]**.
- **Fordækt:** er melderen renonce i essets farve, kan hun lægge et kort som essets farve; uden det "kan der ikke spilles ud til makker-esset" **[kilde S1 §2.12]**. Kortet er "melderens udspil til makkeren" **[kilde S2]**.
- **Katten:** ingen kilde giver regler for, hvad man lægger væk ved es-makker **[ukendt]**. Bridge: korte farver giver stik ved at stikke med trumf, når man har trumf nok (shortness points) **[kilde S9]**.

### Hvad jeg udleder

- Kald esset i den **korteste farve, der ikke er trumf**. Makkers es tager første runde, og bagefter kan melderen stikke farven. Er melderen renonce i farven (evt. efter katten), er det endnu bedre: hun lægger fordækt og kan bruge den til at spille makker ind. Ved lighed: den farve, hvor melderen har den højeste honnør, for den bliver bedre, når makker har esset (K bliver stor efter esset) **[udledt fra S15 og S9]**. Ved es-makker må melderen være renonce i essets farve, det må man ikke i Schafkopf **[kilde S2, S12]**.
- **Katten:** læg tabere fra de korteste sidefarver væk, så en farve bliver renonce, når melderen har trumf nok til at stikke den. Læg aldrig trumf, jokere eller sikre stik væk **[udledt fra S9]**.

## 3. Kortspillet: melder, makker og modspillere

### Udspil og bekendelse (klassisk whist)

Fra Cavendish' 18 principper **[kilde S6]**:

1. Spil første gang ud fra din **stærkeste farve**; længde er vigtigst. Ikke fra en singleton i en sidefarve ("i intet tilfælde forsvarligt").
2. Spil **det højeste af en topsekvens** (D fra DB10).
3. Spil **det højeste fra en svag farve** (2–3 kort), for at styrke makker.
4. **Skift ikke farve** uden grund; fortsæt din første farve.
5. **Returnér makkers farve:** det laveste, hvis du havde fire (stærk), det højeste, hvis du har to tilbage (svag).
6. **Andenhånd lavt.** Undtagelse: en høj sekvens (lig én af den).
7. **Lig det laveste af en sekvens**, når du ikke kan tage stikket (oplysning til makker).
8. **Tredjehånd højt**, for at styrke makker; finesse kun med E-D.
9.–10. **Behold kontrollen i modstandernes farve, slip kontrollen i makkers.**
11. **Smid af fra din svageste farve.** Makker forstår første afkast som svaghed (undtagen når modstanderne har vist stor trumfstyrke).
12. **Giv oplysning ved dit spil:** spil "et ligefremt, forståeligt spil", så makker kan læse dig; falske kort kun, når makker alligevel ikke kan hjælpe.
13. **Spil trumf, når du er meget stærk i dem** (5+).
14. **Stik ikke et tvivlsomt kort** (et kort, som makker måske har det højeste af), når du er stærk i trumf.
15. **Tving modstanderen med mange trumf** til at stikke (spil farver, han er renonce i).
16. **Tving ikke makker** til at stikke, når du selv er svag i trumf.
17. Spil til stillingen.
18. Følg med i kortene og drag slutninger med det samme.

Foster om spil mod en, der melder alene eller i par **[kilde S7]** (en stærk modspiller må "se bort fra sin makker" og spille falsk, for mod et par med otte sandsynlige stik har makker intet): tag dine sikre stik med det samme, før melderne får chancen for at smide af; modspillerne skal sjældent spille trumf ud; spilleren til venstre for melderen skal ikke spille ud fra en farve med kun K øverst eller fra tenacer (ED, KB), men gerne fra DB eller 10-sekvenser; spilleren til højre skal spille trumf igennem melderen, hvis melderen ikke selv har gjort det.

Hoyle **[kilde S8]**: spil ud fra din længste farve mod en melding; spil op til makker frem for igennem ham; spil igennem den stærke hånd op til den svage; smid af fra din svageste og korteste farve, men efterlad ikke en konge ubeskyttet; med EKD i en lang farve kan man vise det ved at smide esset først.

### Signaler, som mennesker forstår

- **Cavendish:** følg reglerne for udspil og bekendelse, så er dit spil i sig selv oplysning **[kilde S6, princip 12]**. *Trumfkald* (et unødvendigt højt kort efterfulgt af et lavere) betyder "spil trumf" **[kilde S6]**; det er en gammel konvention, og jeg har intet belæg for, at danske familiespillere kender den **[udledt]**.
- **Bridge, attitude:** højt kort på makkers udspil eller som afkast = opmuntring ("spil den farve"); lavt = afvisning. Det er den mest brugte signaltype **[kilde S11]**.
- **Es-makker, dansk forum:** "Enhver makker til melder bør smide den kulør på, som han gerne vil spilles ind i." **[kilde S5]** Det strider mod Cavendish' "smid af fra svageste farve", men passer med bridgens attitudesignal, hvis afkastet er et højt kort **[udledt]**.
- **Madskristensen:** "Har du kun ét kort tilbage i en kulør, kan det være et signal værd at sende." "Tæl trumf." "Hold styr på kulørerne." **[kilde S3]**

### Den skjulte makker (es-makker og Schafkopf)

- **Modspillerne leder efter makker:** "en modspiller bør begynde med at spille den kaldte farve ud" **[kilde S12]**; ved første lejlighed "søger" man (spiller kaldt farve) **[kilde S13]**. En modspiller, der ikke søger, er nok renonce i farven **[kilde S13]**. Forummet er delt: "ikke med i meldingen og første udspil: spil ind til makker-es farve" **[kilde S5, xfaktor]** mod "hvis man ikke er med i meldingen, spiller vi aldrig makker-es-kuløren" **[kilde S5, moktar]**.
- **Makker viser sig:** i Schafkopf viser makker, at hun hører til melderen, ved at spille det kaldte es ud eller ved at spille trumf **[kilde S14, S13]**. Forummet: "er du makker, skal du alle dage spille trumf"; med en enlig trumfkonge "kan det være en fordel at vise, at du er makker, inden du spiller trumf" **[kilde S5]**. "Når makker-esset er afsløret, så spil for to." **[kilde S5]**
- **Det kaldte es spilles første gang farven kommer:** regel i S1 og S12, stærkt anbefalet men ikke regel hos os **[kilde S1, S12, S2]**.
- **Esset kan stikkes:** hos os må en, der er renonce, stikke det kaldte es **[kilde S2]**. Schafkopf: "melderens anden modspiller kan måske stikke esset" **[kilde S12]**.

### Hvad jeg udleder

- Før esset falder, ved kun makker, hvem der er makker. Melderen ved, at de andre tre hver har ca. ⅓ chance (lidt mindre, fordi esset kan ligge i katten: 3/42 ≈ 7 %). En modspiller ved, at én af de to andre er makker **[udledt]**.
- En plads, der viser renonce i den kaldte farve, er ikke makker. En plads, der stikker melderens vindende kort, er næppe makker. En plads, der spiller trumf ud uden at være melder, er sandsynligvis makker (S5's "er du makker, skal du spille trumf") **[udledt]**.
- At modspillerne søger esset koster dem ikke stik: makkers es tager stikket uanset hvornår. Det giver dem til gengæld at vide, hvem de spiller mod, og kan give en modspiller, der er renonce, chancen for at stikke esset **[udledt]**. Ulempen: melderen kan stikke farven, hvis hun er renonce uden fordækt **[udledt]**.

## 4. Sol, ren sol og bordlægger

Kilderne er misère (Solowhist, Napoleon), hvor esset er højt. Hos os er **esset lavest** ved sol, så kildernes "toer" svarer til vores **es**, og deres "lave kort" er vores es, 2, 3 … **[udledt fra S2]**.

### Hvornår man melder

- "Misère bør ikke meldes med en lang farve uden toeren." Jo længere farven er, jo mindre er faren, fordi den laveste så tit sidder alene hos en modstander. "Korte farver kan risikeres, selv uden kort under 5 eller 6, og det er en stor fordel at mangle en farve helt." **[kilde S7]**
- "Et es eller en konge, der er beskyttet to eller tre gange, er meget sikkert i misère", fordi farven sjældent spilles mere end to gange, og kortet kan smides, når melderens manglende farve spilles **[kilde S7, Napoleon]** (deres es/konge er høje kort; hos os konge og dame) **[udledt]**.
- Åben misère (spread, vores bordlægger): kun når "hver farve indeholder toeren, og alle kortene er lave nok"; spredte lave kort (2 4 6 8 10) er lige så sikre som en sekvens, når toeren er med **[kilde S7]**.
- En hånd skal ideelt set have **ingen lange farver** (4+) **[kilde S18]**.

### Sol-spillerens spil

- Udspillet er en ulempe for sol-spilleren, men viser hvor de høje kort sidder **[kilde S7]**.
- "Begynd med en singleton, eller det laveste af en sikker farve." **[kilde S7, Napoleon]** Spil ikke det højeste af en tabende sekvens (6 fra 6 5 4 3); 3'eren er bedre **[kilde S7]**.
- Bekend med et kort så lidt lavere end stikkets højeste som muligt; med to kort af samme værdi spilles det lavere, for fjerdehånd følger måske ikke farve **[kilde S7]**.
- Smid aldrig af fra lange farver. Smid de høje kort i korte farver og enlige mellemkort (5'ere, 6'ere) ved hver lejlighed **[kilde S7]**.

### Modspillernes spil mod sol

- Forhindr sol-spilleren i at smide af, og giv udspillet til den, der kan skade mest **[kilde S7]**.
- Første udspil: fra din korteste og svageste farve, et mellemkort (6 eller 7), ikke den laveste, medmindre den er singleton **[kilde S8]**. Spil de korteste farver først, for sol-spilleren er sandsynligvis kort, hvor modspillerne er lange **[kilde S7]**.
- Det svage punkt er som regel en kort farve med ét højt kort, eller en mellemlang farve uden den laveste **[kilde S7]**.
- En farve, hvor sol-spilleren er lang, skal fortsættes for at give makkerne afkast **[kilde S7, Napoleon]**. Bliv ikke ved med en farve, hvor sol-spilleren tydeligvis er sikker (hun lagde et meget lavt kort på et højt) **[kilde S7]**.
- Dæk ikke sol-spillerens eget udspil, hvis du kan undgå det, medmindre kortet er meget lavt (deres: under 4) **[kilde S7]**.
- Modspillere, der spiller efter sol-spilleren, smider deres højeste kort **[kilde S7]**.
- Afkast: tøm én farve helt, så du frit kan vælge senere; smid det højeste af farven (det fortæller makkerne, hvor resten sidder); smid ikke en farve, sol-spilleren er renonce i **[kilde S7]**. Første afkast fra korteste farve, altid det højeste kort **[kilde S7, Napoleon]**.
- Returnér som regel den farve, en modspiller først spillede ud; men ikke den farve, sol-spilleren selv spillede ud **[kilde S7]**.
- Mod en åben hånd (bordlægger) vælger modspillerne korteste farve i første udspil, før hånden lægges op **[kilde S7]**.

### Hvad jeg udleder for vores sol

- **Jokere er gode for sol-spilleren:** en joker må spilles når som helst og vinder kun, når den spilles ud **[kilde S1, S2]**. Den er derfor et sikkert kort at lægge på et stik, hun ellers ville vinde. Faren er kun at sidde med en joker til sidst og skulle spille ud med den **[udledt; samme slutning står i REGLER §2.13]**.
- **Sol tillader ét stik:** tag det tidligt, hvis det fjerner et farligt kort, og hun har et sikkert kort at spille ud bagefter **[udledt]**.
- **Flere sol-spillere:** hver afregner med alle tre andre (S2). En sol-spiller tjener på, at en anden sol-spiller bliver væltet, så når hun selv er sikker, spiller hun som modspiller mod de andre **[udledt fra S2]**.
- **Katten ved sol** går rundt (melder først); den, der byder, kan lægge høje kort fra korte farver væk **[udledt fra S7's afkastregel]**.

## 5. Det kilderne ikke dækker

- Talværdier for, hvornår man skal melde 8, 9, 10 … ved es-makker. Formlen i §6 er bygget af bridgemetoderne og et groft regnestykke og skal justeres med selvspil **[ukendt / udledt]**.
- Hvornår makker bør holde esset tilbage (vores regel tillader det). Ingen kilde **[ukendt]**.
- Strategi for "det kan jeg selv". Ingen kilde **[ukendt]**.
- Halve og vip i praksis, ud over S4's ene sætning og S5's vip-eksempel **[ukendt]**.
- Hvilke signaler danske familiespillere faktisk bruger. Forummet (S5) er det eneste spor **[ukendt]**.
