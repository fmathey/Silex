# Silex

Silex est un langage de programmation compilé. Son premier backend génère du
C++, puis utilise une version maîtrisée de Zig pour produire un exécutable.

Le projet recherche une syntaxe concise et familière sans exposer les détails
d'implémentation du C++ généré.

## État du prototype

Le premier noyau accepte un point d'entrée, les fonctions, les variables
locales, les structures, les booléens, le contrôle de flux et les expressions
arithmétiques entières :

```sx
struct Position {
    x:float
    y:float = 10.0

    func multiplyX(factor:float) void {
        self.x *= factor
    }
}

func main() void {
    var position:Position
    var hit = true

    print("Hello World")

    if (hit && position.x < position.y) {
        position.multiplyX(2)
        print(position.x)
    } else {
        print("blocked")
    }

    var count = 3
    while (count > 0) {
        print(count)
        count = count - 1
    }
}

```

`let` déclare une valeur immuable et `var` une variable réaffectable. Le type est
inféré lorsque l'annotation `:type` est absente. Une `struct` est une valeur
nominale, construite en nommant tous ses champs ; ceux d'une variable `var`
peuvent être modifiés avec `.`. Les méthodes utilisent `self` explicitement ;
le compilateur infère si elles modifient leur receveur et interdit alors leur
appel sur une valeur `let`. Les opérateurs disponibles
sont `+`, `-`, `*`, `/`, les comparaisons `==`, `!=`, `<`, `<=`, `>` et `>=`,
ainsi que les opérateurs logiques `!`, `&&` et `||`. Une condition `if` exige
une expression booléenne et peut être suivie d'un bloc `else`. Une boucle
`while` réévalue une condition booléenne avant chaque itération.
Les fonctions et méthodes utilisent la signature `func name(param:type)
returnType`. Les fonctions utilisateur peuvent être appelées avant leur
définition.

Une annotation sans initialisateur utilise une valeur déterministe : `0` pour
les entiers, `0.0` pour les flottants, `false` pour `bool`, `""` pour `str`, et les valeurs par défaut de
chaque champ pour une `struct`. Les champs peuvent déclarer leur propre défaut
avec `field:type = value`. Les affectations `+=`, `-=`, `*=`, `/=` ainsi que les
instructions postfixées `++` et `--` sont disponibles pour les valeurs
numériques mutables.

Les familles numériques sont `int8` à `int64`, `uint8` à `uint64` et
`float32`/`float64`. `int` désigne `int64`, `uint` désigne `uint64` et `float`
désigne `float32`. Les
élargissements compatibles sont implicites, mais les mélanges signé/non signé
et les conversions flottant vers entier sont refusés. Les opérations entières
arrêtent le programme sur débordement au lieu de boucler ou de saturer
silencieusement.

Les instructions se terminent naturellement à la fin de leur ligne ou devant
`}`. Le point-virgule reste disponible pour placer plusieurs instructions sur
une même ligne :

```sx
let a = 1; let b = 2; print(a + b)
```

La commande `compile` produit un exécutable natif. La commande `run` compile et
exécute le programme :

```sh
silex compile path/to/Main.sx
silex run path/to/Main.sx
```

La compilation est native et optimisée par défaut. La configuration native
participe à l'identité du cache. Une cible Zig explicite permet de produire un
autre système, une autre architecture ou une autre ABI :

```sh
silex compile path/to/Main.sx --target x86_64-linux-musl
```

Une source ou un wrapper C/C++ natif peut être ajouté avec `--native`. Le
manifeste JSON nomme la dépendance, ses sources relatives et les triplets
qu'elle prend explicitement en charge :

```json
{
  "name": "example",
  "sources": ["Wrapper.cpp"],
  "targets": ["aarch64-macos-none", "x86_64-linux-musl"]
}
```

```sh
silex compile path/to/Main.sx --native path/to/dependency.json
```

Les artefacts sont regroupés dans `.silex/` sous le dossier depuis lequel la
commande est lancée. Un programme inchangé réutilise l'exécutable présent dans
le cache de compilation.

## Organisation

```text
Silex/
├── Editors/
│   └── Zed/           extension Zed et grammaire Tree-sitter
└── Toolchain/         projet Zig autonome
    ├── Sources/       implémentation de la commande silex
    ├── Tests/         programmes invalides et diagnostics attendus
    ├── Smokes/        programmes .sx compilés de bout en bout
    └── Benchmarks/    charges Silex et références C++ de même sémantique
```

## Construire la toolchain

La toolchain nécessite Zig 0.16 :

```sh
cd Toolchain
zig build
```

Le binaire de développement est produit dans `Toolchain/zig-out/bin/`. Il
utilise exactement le Zig qui l'a construit. Une distribution destinée aux
utilisateurs se fabrique et se vérifie avec :

```sh
zig build dist-check
```

Elle est placée dans `Toolchain/zig-out/dist/silex-<version>-<arch>-<os>/` et
contient `bin/silex` ainsi que le binaire et la bibliothèque Zig sous
`toolchain/zig/`. Son binaire Silex n'a aucun repli vers le Zig du poste de
fabrication. Chaque plateforme hôte doit donc fabriquer sa propre archive à
partir de cette arborescence.

Zig ne remplace pas les SDK, licences ou droits de distribution imposés par
les systèmes ciblés. Une cible ou une dépendance native peut donc rester
indisponible malgré la présence de la toolchain embarquée ; Silex doit alors la
diagnostiquer explicitement. Lorsqu'un échec n'est découvert que pendant la
compilation native, le diagnostic Silex est affiché en premier et les détails
du backend sont conservés dans `Backend.log`, au sein de l'entrée de cache de
la cible.

Les vérifications sont disponibles avec :

```sh
cd Toolchain
zig build test
zig build smoke
zig build cross-smoke
zig build cross-native-smoke
```

La mesure comparative des boucles entières vérifiées est volontairement
séparée des tests et ne fixe aucun seuil de performance. Elle alterne les deux
exécutables après échauffement, puis rapporte la médiane, le 90e percentile,
l'étendue, le delta apparié et le coût de lancement d'un processus vide :

```sh
zig build benchmark-integers
```

Le workflow `Distribution matrix` exécute ces vérifications et `dist-check`
sur Linux x86-64, macOS ARM64 et Windows x86-64 avec Zig 0.16.0. Chaque job
conserve pendant sept jours l'arborescence autonome produite. Cette matrice
valide les plateformes hôtes de distribution ; elle ne publie aucune release.

## Zed

L'extension située dans `Editors/Zed/` associe les fichiers `.sx` au langage
Silex. Elle fournit la coloration syntaxique, les paires de délimiteurs,
l'indentation, le plan des fonctions et quelques snippets.

Elle s'appuie sur la grammaire native `tree-sitter-silex` développée dans
`Editors/Zed/TreeSitter/`.

Pour l'utiliser pendant le développement, exécuter `zed: install dev extension`
dans Zed, puis sélectionner le dossier `Editors/Zed/`.
