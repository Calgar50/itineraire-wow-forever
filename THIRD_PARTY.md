# Licences et mentions

**Itinéraire** est distribué sous la **GNU General Public License version 3** (fichier `LICENSE`).
Copyright (C) 2026 Calgar50.

Le dossier `Itineraire/Donnees/` reprend des données d'autres projets, sans changer leur contenu (seul le nom des
tables change, voir `outils/donnees.py` : commits épinglés, empreintes SHA-256 vérifiées).

| Fichier | Contenu | Repris de | Licence |
| --- | --- | --- | --- |
| `Donnees/Butins.lua` | butins des donjons et raids | [Dropdon](https://github.com/WoW-Forever-Addons/dropdon), tiré d'[All The Things](https://github.com/ATTWoWAddon/AllTheThings) | MIT |
| `Donnees/Objets.lua` | noms et niveaux de secours des objets | Dropdon, tiré d'All The Things | MIT |
| `Donnees/Entrees.lua` | entrées des donjons vérifiées en jeu | [DonData](https://github.com/WoW-Forever-Addons/dondata) | MIT |
| `Donnees/Recettes.lua` | recettes de métiers | [Guildon Crafts](https://github.com/WoW-Forever-Addons/guildon-crafts) : CMaNGOS classic-db, ForeverDB.net, All The Things | GPL v3 (+ MIT) |
| `Donnees/PNJ.lua` | vendeurs, entraîneurs, rares et leurs positions | [Finddon](https://github.com/WoW-Forever-Addons/finddon) : CMaNGOS classic-db, ForeverDB.net, All The Things | GPL v3 (+ MIT) |
| `Donnees/Marchandises.lua` | ce que vendent les vendeurs | Finddon : CMaNGOS classic-db, ForeverDB.net | GPL v3 |

- **CMaNGOS classic-db** (https://github.com/cmangos/classic-db), Copyright (C) le projet CMaNGOS et ses
  contributeurs, GNU GPL v3.
- **Data from ForeverDB.net (https://foreverdb.net)**, Copyright (C) 2026 ForeverDB.net, GNU GPL v3 avec obligation
  de citer la source.
- Itinéraire lit aussi en jeu, sans rien copier, les addons **Questie** / **QuestieDB** (GPL v3) et
  **Shortest Path Forever** quand ils sont installés.
- Les **plans de talents** (`Autonomie.lua`) sont écrits pour Itinéraire ; les arbres de talents de Forever (noms,
  sorts, paliers, rangs) viennent de ForeverDB (https://foreverdb.net), extraits du client du jeu ; de même pour
  les postures, formes et camouflage exigés par les techniques de guerrier, druide et voleur (rangement des barres,
  `outils/postures.py`).
- **DungeonJournal** (ExehnTV, https://www.curseforge.com/wow/addons/dungeonjournal), tous droits réservés à son
  auteur : quand il est installé, `Itineraire/DungeonJournal.lua` lit ses données en jeu (table
  `ForeverDungeonJournal_NS` : donjons, boss, butins, quêtes de donjon et leurs lieux) et ouvre ses pages.
  **Aucune donnée ni aucun code de DungeonJournal n'est copié dans ce dépôt ni dans le paquet** ; ils ne sont donc pas
  couverts par la licence GPL d'Itinéraire. Cette lecture est faite avec l'autorisation de son auteur (accord donné
  au mainteneur d'Itinéraire, novembre 2026). L'installateur télécharge DungeonJournal depuis CurseForge, sa page
  officielle, comme le ferait l'application CurseForge.

World of Warcraft et son contenu sont des marques et des créations de Blizzard Entertainment.

## Dropdon, DonData, Guildon Crafts, Finddon (code et données propres)

MIT License

Copyright (c) 2026 DonCoohd

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## All The Things

MIT License

Copyright (c) 2026 AllTheThings WoW Addon

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
