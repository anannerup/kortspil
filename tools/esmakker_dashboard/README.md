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

Åbn http://localhost:8765. Serveren lytter på alle netkort, så siden kan også
åbnes fra en telefon på samme net via pc'ens IP.

| Valg | Standard | Hvad |
| --- | --- | --- |
| `--run NAVN` | `main` | Hvilken run der vises |
| `--runs-dir DIR` | `ESMAKKER_RUNS` eller `tools/esmakker_ai/runs` | Hvor runs ligger |
| `--port N` | `8765` | Port |

## Hvad den læser

Kun læsning, den rører aldrig træningen:

| Fil i run-mappen | Bruges til |
| --- | --- |
| `status.json` | Tilstand, tællere, fart, seneste livstegn |
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

- **Rating**: fast skala, 0 = første bot, +464 = Svær. Den første rating kommer
  ved første mellemstadie (20.000 steps) og regnes i baggrunden.
- **Point pr. runde**: over 0 vinder botten. Usikkerheden (95 %) skal være fri
  af 0, før forskellen er sikker.
- **Tab**: logaritmisk skala, skal falde og flade ud.
- **GPU**: med actors på CPU'en svinger den og står mest stille, fordi
  læringen venter på runder. Med `actor_device=cuda` ligger den jævnt (ca.
  40 % på en RTX 3070); se `tools/esmakker_ai/README.md`, "Actors on the GPU".
