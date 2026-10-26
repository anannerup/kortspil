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

- Kun for admin, kun i spil mod bots (ingen andre mennesker ved bordet) **[Anders]**.
- Begge spil, bygget én gang i bordets fælles skal; hvert spil leverer sine egne linjer **[Anders]**.
- Viser bottens kort, og ved hver beslutning hvad botten har tænkt sig: hvad den vil melde, hvor mange stik den tror den selv og makker tager, hvem den gætter er makker, og hvor mange point den forventer for runden **[Anders]**.
- Ændrer ikke, hvad botten ved.
