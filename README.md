# Swipe Vidéos — app iPhone

Lecteur vertical façon TikTok pour les vidéos d'un dossier de l'iPhone, sous-dossiers inclus (par exemple un coffre Cryptomator). Tout reste sur le téléphone.

**Fonctions** : swipe haut/bas, toucher pour pause, double-toucher à gauche ou à droite pour −10 s / +10 s, barre de progression, son, vitesse (0,5x à 2x), ordre aléatoire. Le dossier et la liste des vidéos sont mémorisés : au lancement suivant, la lecture démarre tout de suite et le dossier est revérifié en arrière-plan. Seules la vidéo affichée et ses deux voisines sont ouvertes.

Formats lus : MP4, M4V, MOV (H.264 et HEVC). Les MKV, AVI et WebM ne sont pas lus par l'iPhone.

---

## Étape 1 — Compiler l'app sur GitHub (une fois, ~10 min)

1. Crée un compte gratuit sur **github.com**.
2. Clique sur **+** en haut à droite → **New repository**. Nom : `SwipeVideos`, visibilité **Public** (les minutes de compilation sont alors gratuites ; le code ne contient aucune donnée personnelle). Clique sur **Create repository**.
3. Sur la page du dépôt, clique sur **uploading an existing file**. Décompresse le zip sur ton PC, puis glisse **tout le contenu** du dossier `SwipeVideos` dans la page (y compris le dossier `.github`, `Sources`, `project.yml` et ce fichier). Clique sur **Commit changes**.
   - Vérifie ensuite que le dépôt contient bien `.github/workflows/build.yml`. Si le dossier `.github` n'a pas été envoyé, clique sur **Add file → Create new file**, tape `.github/workflows/build.yml` comme nom, colle le contenu du fichier et valide.
4. Ouvre l'onglet **Actions**. La compilation « Compiler l'app » démarre automatiquement (si GitHub demande d'activer les workflows, accepte). Elle dure environ 5 à 10 minutes.
5. Quand elle est verte ✅, clique dessus puis, en bas, sur **SwipeVideos-ipa** pour télécharger le zip qui contient `SwipeVideos.ipa`.

Astuce : tu peux faire cette étape directement depuis Safari sur l'iPhone (connecté à GitHub). Le zip téléchargé arrive dans Fichiers → Téléchargements ; touche-le pour obtenir `SwipeVideos.ipa`.

Si la compilation échoue (❌), ouvre-la, copie les lignes rouges du journal et envoie-les-moi.

## Étape 2 — Installer SideStore (une fois, avec le PC Windows)

SideStore permet d'installer ses propres apps avec un compte Apple gratuit et les renouvelle tout seul tous les 7 jours, sans PC après l'installation.

1. Suis le guide officiel : **https://docs.sidestore.io** (section installation Windows). Il faut l'iPhone branché par câble au PC pendant la configuration.
2. Sur l'iPhone, active le **mode développeur** : Réglages → Confidentialité et sécurité → Mode développeur → activer, puis redémarrer.
3. Utilise de préférence un identifiant Apple secondaire pour SideStore.

Limites du compte gratuit : 3 apps au maximum, SideStore compris.

## Étape 3 — Installer Swipe Vidéos

1. Ouvre **SideStore** → onglet **Mes apps** → **+**.
2. Choisis `SwipeVideos.ipa` dans Fichiers.
3. L'app apparaît sur l'écran d'accueil. SideStore la renouvellera automatiquement avant l'expiration des 7 jours (ouvre SideStore de temps en temps si besoin).

## Utilisation

1. Déverrouille ton coffre dans l'app **Cryptomator**.
2. Ouvre **Swipe Vidéos**, choisis l'ordre aléatoire si tu veux, puis **Choisir le dossier** et sélectionne le dossier des vidéos dans le coffre.
3. Swipe ! Le bouton dossier en haut à droite permet de changer de dossier ou de relancer l'analyse.

Au premier lancement, l'analyse d'un gros dossier peut prendre un moment, mais la lecture commence dès la première vidéo trouvée. Ensuite, la liste mémorisée s'affiche tout de suite.

Chaque vidéo est déchiffrée par Cryptomator au moment où tu l'approches (la suivante est préparée pendant que tu regardes la vidéo actuelle).

**Confidentialité** : l'app n'a aucun accès réseau. La liste des noms de fichiers est mémorisée dans l'app avec la protection « complète » d'iOS, c'est-à-dire chiffrée tant que l'iPhone est verrouillé. Pour l'effacer, supprime l'app.

## Mettre à jour l'app

Modifie un fichier dans le dépôt GitHub : la compilation repart automatiquement. Télécharge le nouvel `.ipa` et installe-le de nouveau via SideStore.
