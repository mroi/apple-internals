Apple Internals
===============

This repository provides tools and information to help understand and analyze the internals 
of Apple’s operating system platforms. Information is collected in a text file and 
[presented on a website](https://mroi.github.io/apple-internals). A [Nix 
flake](https://nixos.wiki/wiki/Flakes) allows to build the following externally hosted 
tools:

[**acextract**](https://github.com/bartoszj/acextract)  
Unpacks asset catalogs to individual files.

[**dyld-shared-cache-extractor**](https://github.com/keith/dyld-shared-cache-extractor)  
Extracts dynamic libraries from the dyld linker cache.

[**snapUtil**](https://github.com/ahl/apfs)  
Manages APFS snapshots.

The Makefile aggregates various kinds of information from the system in a SQLite database 
and checks the internals text file against this information. Collected details include:

* all file names of the installed macOS and the iOS, tvOS, and watchOS simulators
* linkages of binaries to libraries
* entitlements for all executables
* plain-text strings embedded in binaries
* launchd service descriptions and bundle Info.plist content
* lists of assets inside asset catalogs

To manually analyze and debug macOS, it can be helpful to temporarily [disable its security
protections](https://gist.github.com/macshome/15f995a4e849acd75caf14f2e50e7e98).

___
This work is licensed under the [MIT license](https://mit-license.org) so you can freely use 
and share as long as you retain the copyright notice and license text.
