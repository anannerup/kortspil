# Es-makker dashboard

Live grafer over es-makker-træningen (`tools/esmakker_ai`): rating, point pr.
runde mod Svær og PassBot, den hurtige måling ved hvert mellemstadie, tab og
fart, plus GPU-forbrug. Siden henter nye tal hvert 10. sekund.

## Start

Kun Python's standardbibliotek, ingen installation. Fra repoets rod:

```
py tools\esmakker_dashboard\server.py
```

Eller fra `tools\esmakker_ai` med venv'en, så meldingerne tælles af sig selv:
`.venv\Scripts\python.exe ..\esmakker_dashboard\server.py --run searchbot`.

Åbn http://localhost:8765. Serveren lytter kun på pc'en selv (127.0.0.1),
fordi knappen kan stoppe og starte træningen.

**Knappen** øverst stopper træningen (den gemmer et checkpoint, som
`train stop`) eller starter den igen med run'ets egne indstillinger
(`train start --run NAVN`, den fortsætter fra checkpointet og lever videre,
også hvis dashboardet lukkes). Den starter aldrig en ny run og aldrig en
anden learner, mens én kører. Uddata fra en start går til `train.out.log` i
run-mappen.

| Valg | Standard | Hvad |
| --- | --- | --- |
| `--run NAVN` | `main` | Hvilken run der vises |
| `--runs-dir DIR` | `ESMAKKER_RUNS` eller `tools/esmakker_ai/runs` | Hvor runs ligger |
| `--port N` | `8765` | Port |

## Hvad den læser

Kun læsning (bortset fra knappens STOP-fil og start):

| Fil i run-mappen | Bruges til |
| --- | --- |
| `status.json` | Tilstand, tællere, fart, seneste livstegn |
| `ladder.jsonl` | "Bedre end sig selv": hvert mellemstadie mod de ældre (skrives af `ladder.py`) |
| `train.log.jsonl` | Tab og fart over tid (højst 600 punkter sendes) |
| `ratings.jsonl` | Ratingkurven og point mod Svær og PassBot |
| `snapshots/index.jsonl` | Den hurtige måling mod første bot |
| `meldinger.jsonl` | Tabellen over meldinger og nettets stik-gæt, med kontraktgættet for net med kontrakthoved (skrives af `meldinger.py`) |

GPU-tallene kommer fra `nvidia-smi`, hvis den findes.

## Meldinger

`meldinger.py` tæller ved hvert mellemstadie, hvad nettet ender som melder på,
og hvor tit det går hjem: 200 spil ved et bord med tre Svær og 200 runder
selvspil. Det tager ca. 20 sekunder pr. mellemstadie. Kører serveren i
esmakker_ai's venv (som har torch), starter den selv tællingen i baggrunden,
når der kommer et nyt mellemstadie. Ellers kan den køres i hånden:

```
cd tools\esmakker_ai
.venv\Scripts\python.exe ..\esmakker_dashboard\meldinger.py --run searchbot
```

## Sådan læses graferne

- **Bedre end sig selv**: hvert mellemstadie mod mellemstadiet 3 før (60.000
  steps), point pr. runde for det nye net på de samme kort. Fri af 0 opad =
  det er blevet bedre. Tabellen under viser det mod alle ældre: grøn sikkert
  bedre, rød sikkert dårligere.
- **Målestok: mod Svær**: kun en målestok, ikke målet.
- **Rating** (under "Den gamle rating"): fast skala, 0 = første bot, +462 = Svær.
- **Point pr. runde**: over 0 vinder botten. Usikkerheden (95 %) skal være fri
  af 0, før forskellen er sikker.
- **Tab**: logaritmisk skala, skal falde og flade ud.
- **GPU**: med actors på CPU'en svinger den og står mest stille, fordi
  læringen venter på runder. Med `actor_device=cuda` ligger den jævnt (ca.
  40 % på en RTX 3070); se `tools/esmakker_ai/README.md`, "Actors on the GPU".
