# Third-party software

This repository downloads, builds, and packages third-party software. Each
component retains its own copyright and license terms.

| Component | Role | Source |
| --- | --- | --- |
| Fritzing | Application | <https://github.com/fritzing/fritzing-app> |
| fritzing-parts | Parts library | <https://github.com/fritzing/fritzing-parts> |
| Qt | Application framework | <https://www.qt.io/> |
| zlib | Compression | <https://github.com/madler/zlib> |
| libgit2 | Parts-repository access | <https://github.com/libgit2/libgit2> |
| QuaZip | ZIP support | <https://github.com/stachenov/quazip> |
| Clipper | Polygon clipping | <https://sourceforge.net/projects/polyclipping/> |
| Boost | Header libraries | <https://www.boost.org/> |
| SVG++ | SVG parsing | <https://github.com/svgpp/svgpp> |
| ngspice | Circuit simulation | <https://ngspice.sourceforge.io/> |

Exact versions, URLs, and hashes are in `config/build-lock.json`. Generated
packages include Fritzing's license files, `BUILD-INFO.json`, and an SBOM. The
workflow also emits a corresponding-source bundle containing the Fritzing app
source and the verified dependency source archives used by the build.

