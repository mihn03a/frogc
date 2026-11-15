# FROGC – Bounce Back (Godot 4)

Joc arcade 3D pentru game jam (tema **BOUNCE BACK**): o broască-avion care sare din obstacol în obstacol, 5 niveluri, 5 evoluții, un boss final și o scenă de victorie.

Tot jocul este construit **din cod**: modelele 3D low-poly, nivelurile, sunetele și muzica sunt generate de scripturi. Nu ai nevoie de asset-uri externe.

## Cum îl pornești

Proiectul e făcut și testat în **Godot 4.7.2**, ultima versiune stabilă.

1. Dacă nu ai Godot 4.7.2, descarcă-l de pe https://godotengine.org/download/windows/ (varianta „Godot Engine”, nu „.NET”). Dezarhivează zip-ul și pornește `Godot_v4.7.2-stable_win64.exe`. Nu are nevoie de instalare.
2. În Project Manager apasă **Import** (sus în stânga).
3. Alege fișierul `project.godot` din folderul `FROGC` (Documents\Godot\FROGC).
4. Apasă **Import** (sau „Import & Edit”). Prima deschidere durează câteva secunde, cât Godot pregătește fișierele.
5. Apasă **F5** sau butonul ▶ din dreapta sus. Pornește meniul principal → **PLAY**.

Dacă te întreabă de scena principală, alege `scenes/main_menu/main_menu.tscn`.

**Dacă jocul merge greu (laptop mai slab):** Project → Project Settings → Rendering → Renderer → schimbă „Rendering Method” în **gl_compatibility**, apoi repornește editorul. Jocul merge la fel, doar cu efecte de lumină mai simple.

**Pentru un .exe pe care îl dai juriului:** Project → Export → Add… → Windows Desktop. Dacă Godot cere „export templates”, apasă Download. Apoi „Export Project”.

## Audio propriu (intro și final)

Pune fișierele în folderul `assets/audio/` din proiect, cu exact aceste nume:

- `intro.mp3`: se aude o dată, când pornește jocul (în meniul principal). Apoi pornește muzica meniului.
- `victory.mp3`: se aude în scena finală de victorie.

Merg și `.ogg` sau `.wav`. Godot le importă singur când revii în editor. Dacă un fișier lipsește, jocul folosește sunetele generate automat.

## Battle: multiplayer până la 4 jucători

Din meniu alegi **BATTLE (MULTIPLAYER)**.

- **Cum dai damage:** aterizezi pe capul altei broaște, sau faci Perfect Bounce pe podea, care declanșează o undă de șoc.
- **Vieți și runde:** meciul e „cel mai bun din 3”. În fiecare rundă, fiecare broască are 3 vieți. O pierzi dacă ajungi la 0 HP sau dacă cazi din arenă. Câștigă runda ultima broască rămasă, iar meciul primul care ia 2 runde.
- **Arena se strică:** după 30 de secunde, plăcile de pe margine se înroșesc și cad, o dată la 6 secunde, din exterior spre centru.
- **Spectator:** dacă ai fost eliminat, camera urmărește jucătorii rămași. SPACE sau clic trece la următorul.
- **HOST GAME:** devii server. Pe ecran apare IP-ul tău; spune-l prietenilor.
- **JOIN:** scrii IP-ul host-ului și apeși JOIN.
- **START MATCH:** doar host-ul îl poate apăsa. Locurile goale pot fi completate cu boți.
- **PLAY VS BOTS:** joci singur împotriva a 3 boți, fără rețea.

**Conectare:**
- În același Wi-Fi sau în aceeași rețea, folosiți direct IP-ul host-ului (de forma 192.168.x.x).
- Pe internet, instalați toți **Radmin VPN** sau **ZeroTier**, intrați în aceeași rețea virtuală și folosiți IP-ul dat de program. Alternativa este să deschideți portul **UDP 7777** pe routerul host-ului.
- La prima pornire, Windows poate întreba dacă Godot are voie să folosească rețeaua. Apăsați **Allow**.

## Photo Mode

În pauză (ESC) apasă **PHOTO MODE**. Jocul îngheață și primești o cameră liberă:
- trage cu mouse-ul ca să rotești camera, iar rotița sau Q/E fac zoom;
- WASD mută camera, R/F o ridică și o coboară;
- tastele 1–6 schimbă filtrul: Normal, Vivid, Alb-negru, Noir, Dreamy, Retro;
- V schimbă poza broaștei, H ascunde textul;
- ENTER sau F12 salvează poza în **Imagini\FROGC**;
- ESC te întoarce la meniul de pauză.

## Dificultate

- Dacă **cazi** în apă, lavă sau pe grila de energie, iei damage mare și te întorci la ultima platformă. Pierzi viteza și combo-ul.
- **PERFECT SPLASH:** deasupra apei/lavei inelul de timing devine roșu. Dacă apeși SPACE la „NOW!”, iei doar jumătate din damage, îți păstrezi combo-ul și sari înapoi în sus din locul unde ai căzut.
- **Viața nu se mai reface complet** între niveluri: primești doar +35%.
- **Inelul de sub broască** e verde când ești deasupra unei platforme și roșu când ești deasupra unui pericol.
- Dificultatea se alege din Settings: EASY, NORMAL sau HARD.

## Controale

| Tastă | Acțiune |
|---|---|
| A / D (sau săgeți) | stânga / dreapta |
| W | planare (cazi încet) |
| S | picaj (cazi repede) |
| SPACE | Bounce Brace: apasă chiar înainte de impact pentru PERFECT BOUNCE |
| SHIFT | Turbo Hop (deblocat la evoluția 4) |
| ESC / P | pauză |

În arena boss-ului: WASD te mișcă, iar W înseamnă spre boss.

## Structura proiectului

```
project.godot                 setări + autoload-uri
scenes/
  main_menu/main_menu.tscn    meniu principal
  levels/level.tscn           O SINGURĂ scenă pentru toate cele 5 niveluri
  ui/evolution_screen.tscn    ecran de evoluție între niveluri
  ui/game_over.tscn           Game Over
  ui/victory.tscn             scena cinematică de victorie
scripts/
  core/game_state.gd          (autoload) scor, combo, viață, evoluție, upgrade-uri, schimbare scene
  core/audio_manager.gd       (autoload) sunete + muzică sintetizate în cod
  core/fx.gd                  (autoload) particule, shake, flash, text plutitor, materiale
  player/player.gd            controlul jucătorului + sistemul de bounce
  player/player_model.gd      modelul broaștei-avion, 5 evoluții, poze și expresii
  gameplay/level.gd           construiește nivelurile (3 lumi) + arena boss
  gameplay/enemy.gd           4 tipuri de inamici
  gameplay/projectile_pool.gd proiectile reutilizate (object pooling)
  boss/boss.gd                logica boss-ului (3 faze)
  boss/boss_model.gd          modelul boss-ului + animații (inclusiv plânsul)
  ui/hud.gd                   HUD + indicatorul de timing pentru Perfect Bounce
  ui/pause_menu.gd, main_menu.gd, evolution_screen.gd, game_over.gd, victory.gd
  ui/ui_style.gd              stilul comun pentru butoane, panouri și bare
```

Fiecare scenă `.tscn` are un singur nod cu un script. Scriptul construiește restul în `_ready()`. Din acest motiv scenele nu se strică și le poți citi ușor.

## Cum funcționează sistemele principale

**Bounce:** `player.gd` folosește `move_and_collide()`. La fiecare coliziune viteza este reflectată după normala suprafeței (`velocity -= 1.85 * v·n * n`). Pe suprafețe orizontale primești și o viteză minimă în sus. Fiecare bounce dă puncte, combo, momentum, particule și sunet.

**Perfect Bounce:** când apeși SPACE se salvează momentul (`_last_brace`). Dacă impactul are loc în fereastra `GameState.perfect_window()` (0,15–0,3 s), bounce-ul devine PERFECT: bonus de puncte, invulnerabilitate scurtă, efecte speciale. Ca să fie corect, o apăsare cu maximum 0,08 s după impact contează și ea. Indicatorul din HUD folosește un raycast pe direcția de mers. Inelul se strânge și devine verde („NOW!”) când e momentul să apeși.

**Combo:** fiecare bounce crește combo-ul. Multiplicatorul de scor este `1 + 0,5 la fiecare 5 combo` (maximum x5). Combo-ul se resetează dacă nu sari 3,5 s sau dacă primești damage.

**Damage = oportunitate:** după o lovitură primești momentum. Dacă sari în următoarele 2,5 s, primești „COMEBACK BOUNCE +300”. Podeaua (apă, lavă sau grilă de energie) îți ia viață, dar te aruncă înapoi în sus.

**Power-up-uri:** SHIELD, SUPER BOUNCE, SPEED BOOST și MAGNET. Fiecare are efect vizual, icon cu timer în HUD, sunet propriu și expirare.

**Niveluri:** `level.gd` folosește un RNG cu seed fix, deci fiecare nivel arată la fel de fiecare dată. Fiecare segment are o platformă, un arc de monede și un obstacol specific lumii:
- Steagu și Bunloc (lumea verde): copaci, muște, viespi (nivelul 2), mine.
- Tractorul și Codlea (lumea de lavă): platforme instabile care se prăbușesc, roci care cad, lilieci care trag, vulcani.
- Ghimbav (lumea neon): platforme mobile, porți laser, ciocane mecanice, drone, arena boss.

**Evoluții:** `player_model.gd → build(stage)` adaugă piese vizibile: aripi mai mari, armură și elice cu 4 pale, motoare extra cu flăcări, armură crom cu neon și halou. Fiecare evoluție crește viața și armura și deblochează o abilitate nouă.

**Boss (The Big Nic):** are 3 faze: inele de proiectile, apoi SLAM cu undă de șoc (după slam e amețit și îl poți strivi), apoi ploaie de blocuri. Îl rănești când aterizezi pe capul lui (folosește trambulinele roz) sau când îi trimiți proiectilele înapoi cu Perfect Bounce.

## Cum modifici lucruri

- **Dificultate:** constantele din vârful `player.gd` (GRAVITY, BOUNCE_UP, BASE_SPEED) și `LENGTHS` din `level.gd`.
- **Viață și armură pe evoluții:** `BASE_HP` și `ARMOR` din `game_state.gd`.
- **Sunete proprii:** în `audio_manager.gd`, după `_ready()`, înlocuiește intrări din dicționar, de exemplu `sounds["bounce"] = load("res://assets/audio/boing.ogg")`.
- **Modele proprii (.glb din Blender):** în `player_model.gd`, în `build()`, poți instanția modelul tău în loc de forme generate: `var m = load("res://assets/models/frog.glb").instantiate(); _root.add_child(m)`.
