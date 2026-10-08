# RottenUI

Kit graphique commun aux applications Rotten (Rottentree, RottenText, RottenSSHrimp) :
contrôles LCL thémés, fontes, icônes et thèmes **embarqués dans les unités**. Un
programme qui utilise le kit n'a aucune ressource à déclarer dans son projet.

Licence : GPL-3.0-or-later (`LICENSE`). Fontes Monaspace et JetBrains Mono : SIL OFL 1.1 ;
icônes Tabler : MIT. Leurs notices sont dans `assets/licenses/` et embarquées avec elles
(ressources `LICENSE_MONASPACE_OFL_1_1`, `LICENSE_JETBRAINSMONO_OFL_1_1`, `LICENSE_TABLER_MIT`).

Chaîne de compilation : FPC 3.2.2 / Lazarus 4.8. Sous Linux, le widgetset GTK3 demande
Lazarus trunk (5 ou plus) ; GTK2 reste possible avec la 4.8.

## Contenu

| Unité | Rôle |
|---|---|
| `uTheme` | jetons de couleur et fontes courants, tailles choisies par l'utilisateur |
| `uThemeLoad`, `uThemeData`, `uThemePreview` | registre des thèmes (intégrés, embarqués, JSON utilisateur), application, aperçu |
| `uFontEmbed` | fontes embarquées, enregistrées pour le seul processus |
| `uIcons` (+ `uIconCatalog.inc`) | icônes Tabler en masques teintés à l'exécution, `TRtIcon` |
| `uUiKit` | `TRtDialog` et aides de mise en page (rangées, zone défilante, boutons, mémos, état) |
| `uRtMessage` | boîtes de message et de saisie |
| `uRtCombo`, `uRtCheck`, `uRtButton`, `uRtList` | liste déroulante, case à cocher, bouton, liste |
| `uTabBar`, `uMenuBar`, `uSearchBox`, `uTreeScrollBar`, `uPickDialog` | onglets, barre de menus, recherche, défilement, choix |
| `uDocTabBar` | onglets de documents pour un éditeur, pilotés par événements : témoins modifié, lecture seule et enregistrement, réordonnancement, bouton « + » |
| `uRtStatusBar` | barre de statut dessinée : panneaux de largeur fixe ou prenant la place restante, alignement, couleur de texte par panneau demandée au dessin |
| `uRtLogList` | journal borné sur `TRtListGrid` : heure en première colonne, le plus récent en haut, chaque message ramené sur une ligne |
| `uRtGauge` | jauge dessinée, à progression connue ou indéterminée (bloc qui défile) ; `TThemedGauge` en est l'alias |
| `uRtProgress` | dialogue de suivi d'un travail long : sujet, état, jauge, détail, élément en cours, Stop puis Close ; fermer en plein travail vaut Stop |
| `uRtAbout` | À propos alimenté par l'application (nom, version, lignes, liens, logo, détails) et visionneuse de licences lues dans les ressources du binaire |
| `uRtWizard` | échafaudage d'assistant posé dans un `TRtDialog` : bandeau, étapes, pages, Back/Next, validation à chaque changement de page |
| `uRtSecretEdit` | champ de saisie masqué à la main (`TRtSecretEdit`), sans champ sécurisé natif : presse-papiers et annulation fermés tant qu'il est masqué, menu contextuel réduit alors à « Paste », affichage en clair sur demande, tampon effacé sur demande et à la destruction |
| `uRtPassword` | dialogue de mot de passe sur `TRtDialog` : un champ ou nouveau + confirmation, case « Show », refus affiché sans fermer (`OnValidate`), secret rendu en copie à effacer |
| `uRtReport` | vue de rapport `TRtReportView` à poser dans une page d'onglet : barre de commandes, bilan et avertissement sur fond du thème, liste triable `TRtListGrid` ; l'application fournit boutons, textes et cellules |
| `uThemedControls`, `uThemedSplitter`, `uNoticeBanner` | bouton, case, liste, onglets et séparateur dessinés ; bandeau d'avis |
| `uSafeSave`, `uJsonGuard` | écriture atomique et lecture bornée de fichiers, garde JSON |

Ressources : `src/rottenui_fonts.res` (lié par `uFontEmbed`), `src/rottenui_icons.res`
(`uIcons`), `src/rottenui_themes.res` (`uThemeLoad`).

## Quelle famille de contrôles

Le kit en porte deux, qui se recouvrent en partie. Aucune ne remplace l'autre, et un
programme peut mêler les deux (`RtMessageDlg` sert aux trois applications) ; un même
dialogue s'en tient à une seule.

| | « Rt » : `uUiKit`, `uRt*`, `uPickDialog` | « Themed » : `uThemedControls` |
|---|---|---|
| Utilisée par | Rottentree | RottenSSHrimp, RottenText |
| Dialogue | hérite de `TRtDialog` : en-tête (serveur cible, icône), corps, barre de boutons | n'importe quel `TForm`, passé à `ThemeDialog` |
| Mise en page | par alignement, avec les aides `Make…` (rangées à libellé, zone défilante) | laissée telle quelle, positions absolues comprises |
| Contrôles natifs | recolorés par `ThemeControlTree` : champs, mémos, listes, arbres, grilles, zones défilantes, séparateurs | champs encadrés sur place, panneaux, libellés (couleur par `Tag`) |
| Boutons | `TButton` natifs ; `TRtFlatButton` plat, à icône | `TThemedButton` dessiné (`Default`, `Cancel`, `ModalResult`) |
| Case à cocher | `TRtCheckBox` : deux états, libellé sur plusieurs lignes | `TThemedCheck` : trois états (`AllowGrayed`) |
| Liste déroulante | `TRtComboBox` : liste maison qui défile et se filtre, taillée pour des centaines d'éléments | `TThemedCombo` : s'ouvre en menu, pour une poignée de choix |
| En plus | `TRtListGrid`, `TRtLogList`, `TRtStatusBar`, `TRtSegmented`, `TRtStepper`, `TPickDialog`, `TRtProgressDialog`, `TRtAboutDialog`, `TRtLicenseViewer`, `TRtWizard`, `TRtPasswordDialog`, `TRtReportView` | `TThemedTabs` |

Écran neuf construit par code, dense en données ou en longues listes : « Rt ». Formulaire
déjà posé au pixel, ou contrôle natif à remplacer sans toucher au reste : « Themed ».

La jauge `TRtGauge` (`uRtGauge`) sert aux deux familles : elle se peint seule et ne dépend
que du thème. Elle vit dans sa propre unité parce qu'utiliser `uThemedControls` embarque
aussi ses réglages Cocoa (anneau de focus des champs mot de passe), dont un programme
« Rt » n'a pas à hériter.

Le champ masqué `TRtSecretEdit` (`uRtSecretEdit`) sert lui aussi aux deux familles : c'est un
`TEdit`, que `ThemeControlTree` comme `ThemeDialog` encadrent et colorent avec les autres
champs (`MakeSecretRow` le pose dans une rangée « Rt »). Il n'emploie ni `PasswordChar` ni
`EchoMode` : sous Cocoa, ils feraient du champ un champ sécurisé natif, avec le « secure
event input » qui l'accompagne. Lire `Text` ne rend que ce qui est affiché ; le secret sort
par `GetSecret`, en copie que l'appelant efface avec `RtWipeSecret`.

## Utiliser le kit dans un projet

Dans l'IDE : *Paquet > Ouvrir un fichier paquet* (`rottenui.lpk`), puis *Utiliser > Ajouter
au projet*. Ou directement dans le `.lpi`, sans installer le paquet dans l'IDE (chemin
relatif au `.lpi`) :

```xml
<RequiredPackages>
  <Item>
    <PackageName Value="RottenUI"/>
    <DefaultFilename Value="../rottenui/rottenui.lpk" Prefer="True"/>
  </Item>
</RequiredPackages>
```

Au démarrage, après `Application.Initialize` :

```pascal
EmbeddedFontManager.RegisterFonts;   // uFontEmbed
ApplyDefaultFonts;                   // uTheme
// facultatif: tailles choisies et dossier des thèmes JSON de l'utilisateur
// (défaut: <dossier de configuration>/themes)
PrefUiFontSize := 10;
ThemesUserDir := MonDossier + PathDelim + 'themes';
// facultatif, pour un éditeur de texte: plage de taille de l'éditeur plus large
// que celle de l'interface (10 à 14 par défaut), famille choisie par l'utilisateur
EditorFontSizeMin := 6;
EditorFontSizeMax := 72;
PrefEditorFontKey := 'Krypton';
InitThemes('Rotten');                // uThemeLoad
```

## Modifier les ressources

Les `.res` sont versionnés : un projet qui utilise le kit n'a besoin ni de Python ni d'un
compilateur de ressources.

- **Ajouter une icône** : son nom Tabler dans `ICONS` de `tools/gen_icons.py`, puis
  `python tools/gen_icons.py --download` (dépendance : `resvg-py`). Les masques PNG,
  `src/uIconCatalog.inc` et `src/rottenui_icons.res` sont régénérés.
- **Fontes ou thèmes** : remplacer les fichiers de `assets/`, puis
  `python tools/gen_res.py`.
- **Contrôle** : `python tools/gen_res.py --check` échoue si un `.res` ne correspond plus
  à ses fichiers.

`gen_res.py` écrit un script `.rc` par jeu (liste lisible, versionnée) et le compile avec
`fpcres`, livré avec FPC sur toutes les plateformes. Un `.rc` déclaré directement par
`{$R x.rc}` serait confié à `windres` par FPC 3.2.2, y compris sous Linux où il manque
généralement (`compiler/rescmn.pas`, `res_elf_info`). D'où les `.res` précompilés.
