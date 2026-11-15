# FROGC – Bounce Back

O broască cu elice care nu știe să frâneze.

Am făcut jocul la un hackathon cu tema **BOUNCE BACK**, așa că totul se învârte în jurul ideii ăsteia: te lovești de ceva, sari înapoi și mergi mai departe. Dacă nimerești momentul, sari și mai sus.

Are 5 niveluri, 5 evoluții pentru broască, un boss la final (The Big Nic), multiplayer până la 4 jucători și un photo mode, că de ce nu.

| | |
|---|---|
| ![Steagu](docs/steagu.jpg) | ![Tractorul](docs/tractorul.jpg) |
| ![Ghimbav](docs/ghimbav.jpg) | ![The Big Nic](docs/boss.jpg) |
| ![Battle](docs/battle.jpg) | ![Victorie](docs/victory.jpg) |

## Cum îl pornești

Ai nevoie de [Godot 4.7.2](https://godotengine.org/download/windows/), varianta normală, nu cea .NET. Nu se instalează, doar dezarhivezi și pornești exe-ul.

1. Clonezi repo-ul (sau iei zip-ul de pe GitHub)
2. În Godot: **Import** → alegi `project.godot`
3. Apeși **F5**

Prima deschidere durează câteva secunde, cât Godot importă fișierele.

Dacă merge greu pe laptop, intră în **Settings** din meniul jocului și bifează **LOW GRAPHICS**. Asta oprește umbrele și glow-ul și ar trebui să ajungă la 60 FPS. Proiectul folosește renderer-ul *Mobile*. Am încercat și *Compatibility*, dar pe plăcile video Intel apăreau pixeli roșii pe modele, așa că am rămas la Mobile.

Ca să faci un .exe: Project → Export → Add → Windows Desktop. Prima dată Godot îți cere export templates, apeși Download.

## Cum se joacă

| Tastă | Ce face |
|---|---|
| A / D | stânga / dreapta |
| W | planezi (cazi mai încet) |
| S | picaj |
| SPACE | bounce |
| SHIFT | turbo hop (de la evoluția 4) |
| ESC | pauză |

Toată treaba e în SPACE. Sub broască e un inel care se strânge pe măsură ce te apropii de ceva. Când se face verde și scrie **NOW!**, apeși. Dacă ai nimerit, e **Perfect Bounce**: puncte în plus, sari mai sus și ai o clipă de invincibilitate.

Câteva lucruri pe care le afli oricum după primul nivel:

- Dacă te lovește ceva și sari în următoarele 2,5 secunde, primești **Comeback Bounce** (+300).
- Apa, lava și grila de energie te costă mult și te trimit înapoi la ultima platformă. Deasupra lor inelul se face roșu. Dacă apeși la NOW!, faci **Perfect Splash**: iei doar jumătate din damage, îți păstrezi combo-ul și sari înapoi de unde ai căzut.
- Combo-ul crește cu fiecare bounce și ajunge până la x5 scor. Se pierde dacă stai 3,5 secunde fără să sari sau dacă iei damage.
- Între niveluri viața nu se reface complet, primești doar +35%.
- Există 4 power-up-uri: shield, super bounce, speed și magnet.

Nivelurile poartă nume din zona Brașovului: **Steagu** și **Bunloc** (lumea verde), **Tractorul** și **Codlea** (lava), **Ghimbav** (neon, cu boss-ul).

La final te așteaptă **The Big Nic**. Are trei faze: întâi aruncă inele de proiectile, apoi lovește podeaua (după asta rămâne amețit câteva secunde), iar la final aruncă blocuri din cer. Îl lovești sărind pe capul lui de pe trambulinele roz sau trimițându-i proiectilele înapoi cu un Perfect Bounce. În arenă te miști cu WASD.

## Battle (multiplayer)

Din meniu → **Battle**. Până la 4 broaște într-o arenă care se strică pe măsură ce trece timpul.

Lovești pe cineva aterizând pe capul lui sau cu un Perfect Bounce pe podea, care face o undă de șoc. Fiecare are 3 vieți pe rundă, iar meciul se joacă best of 3. După 30 de secunde plăcile de pe margine încep să cadă, câte un rând la 6 secunde.

- **Host Game**: ești server, iar IP-ul îți apare pe ecran
- **Join**: scrii IP-ul celui care face host
- **Play vs Bots**: dacă n-ai cu cine

În aceeași rețea merge direct cu IP-ul local (192.168.x.x). Pe internet, cel mai simplu e Radmin VPN sau ZeroTier. Altfel trebuie deschis portul UDP 7777 la cel care face host. Când Windows întreabă de rețea, apeși Allow.

## Photo mode

ESC → **Photo Mode**. Jocul se oprește și poți muta camera cum vrei:

- mouse-ul rotește camera, rotița face zoom
- WASD mută camera, R/F o urcă și o coboară
- tastele 1–6 schimbă filtrul
- V schimbă poza broaștei, H ascunde textul
- ENTER salvează poza în `Imagini/FROGC`

## Fețele

Broasca și boss-ul au fețele a doi prieteni de-ai noștri, care au fost de acord. Pozele sunt în `assets/textures/`. Dacă vrei broasca originală, setezi `USE_FRIEND_FACE := false` în `player_model.gd` (sau în `boss_model.gd` pentru boss). Dacă lipsesc pozele, modelele revin singure la ochii și gura de broască.

## Muzică proprie

Dacă pui `intro.mp3` sau `victory.mp3` în `assets/audio/`, jocul le folosește la pornire și la scena de final. Merg și `.ogg` și `.wav`. Dacă nu le pui, folosește sunetele lui.

## Cum e făcut

Aproape tot e generat din cod: modelele 3D, nivelurile, sunetele și muzica. Nu există modele importate. Fiecare scenă are un singur nod cu un script care construiește restul în `_ready()`.

```
scripts/
  core/       game_state (scor, viață, salvări), audio, efecte, rețea
  player/     controlul broaștei și modelul ei
  gameplay/   generarea nivelurilor, inamici, proiectile
  boss/       The Big Nic
  battle/     multiplayer și lobby
  ui/         meniuri, HUD, photo mode
```

Câteva detalii, pentru cine e curios:

- **Bounce-ul** reflectă viteza după normala suprafeței (`v -= 1.85 * (v·n) * n`), cu un minim de viteză în sus pe suprafețele plate.
- **Perfect Bounce** ține minte când ai apăsat SPACE. Dacă impactul vine în fereastra de timp, contează. Acceptă și o apăsare puțin întârziată (0,08 s), ca să nu fie frustrant.
- **Inelul de timing** folosește un raycast pe direcția în care zbori, ca să știe cât mai e până la impact și dacă dedesubt e platformă sau pericol.
- **Nivelurile** sunt generate cu seed fix, deci arată la fel de fiecare dată.
- **Boss-ul** e un state machine simplu: fight, slam, dizzy, defeated.
- **Proiectilele** sunt refolosite dintr-un pool, ca să nu creăm noduri noi tot timpul.
- **Multiplayer-ul** e pe ENet. Fiecare broască e controlată de jucătorul ei, iar host-ul decide rundele.

Vrei să schimbi dificultatea? Constantele sunt sus în `player.gd` (GRAVITY, BOUNCE_UP, BASE_SPEED). Viața și armura pe evoluții sunt în `game_state.gd`.

## Echipa

- CG11

Făcut cu Godot 4.7.2.
