{
	description = "tools to understand the internals of Apple’s operating systems";
	inputs = {
		acextract = {
			url = "github:bartoszj/acextract";
			flake = false;
		};
		command-line = {
			url = "github:iHTCboy/CommandLine";
			flake = false;
		};
		dsc-extractor = {
			url = "github:keith/dyld-shared-cache-extractor";
			flake = false;
		};
		snap-util = {
			url = "github:ahl/apfs";
			flake = false;
		};
	};
	outputs = { self, nixpkgs, acextract, command-line, dsc-extractor, snap-util }: {
		packages.aarch64-darwin = let
			xcode = nixpkgs.legacyPackages.aarch64-darwin.xcodeenv.composeXcodeWrapper {};
		in {

			acextract =
				with nixpkgs.legacyPackages.aarch64-darwin;
				let xcodeHook = makeSetupHook {
					name = "xcode-hook";
					propagatedBuildInputs = [ xcode ];
				} "${xcbuildHook}/nix-support/setup-hook";
				in stdenvNoCC.mkDerivation {
					name = "acextract-${lib.substring 0 8 self.inputs.acextract.lastModifiedDate}";
					src = acextract;
					nativeBuildInputs = [ xcodeHook ];
					__noChroot = true;
					preBuild = "LD=$CC";
					# FIXME: want to have submodule support for Nix flakes, workaround by explicit instantiation
					postUnpack = "rmdir source/CommandLine ; ln -s ${command-line} source/CommandLine";
					# FIXME: fix for Swift compiler crash
					patchPhase = ''
						patch -p0 <<- EOF
							--- acextract/CoreUI.h
							+++ acextract/CoreUI.h
							@@ -24,6 +24,7 @@
							 //  SOFTWARE.

							 @import Foundation;
							+@import CoreGraphics;

							 // Hierarchy:
							 // - CUICatalog:
							--- acextract/Operation.swift	2021-10-20 10:35:39.000000000 +0200
							+++ acextract/Operation.swift	2021-10-20 10:35:46.000000000 +0200
							@@ -24,6 +24,7 @@
							 //  SOFTWARE.

							 import Foundation
							+import ImageIO

							 // MARK: - Protocols
							 protocol Operation {
							@@ -152,7 +153,7 @@
							             throw ExtractOperationError.cannotCreatePDFDocument
							         }
							         // Create the pdf context
							-        let cgPage = CGPDFDocument.page(cgPDFDocument) as! CGPDFPage // swiftlint:disable:this force_cast
							+        let cgPage = cgPDFDocument.page(at: 0)!
							         var cgPageRect = cgPage.getBoxRect(.mediaBox)
							         let mutableData = NSMutableData()
							 
						EOF
					'';
					installPhase = ''
						mkdir -p $out/bin
						cp Products/Release/acextract $out/bin/
					'';
					dontStrip = true;
				};

			dsc-extractor =
				with nixpkgs.legacyPackages.aarch64-darwin;
				stdenv.mkDerivation {
					name = "dsc-extractor-${lib.substring 0 8 self.inputs.dsc-extractor.lastModifiedDate}";
					src = dsc-extractor;
					nativeBuildInputs = [ cmake ];
				};

			snap-util =
				with nixpkgs.legacyPackages.aarch64-darwin;
				let snapshot-header = fetchFromGitHub {
					owner = "apple";
					repo = "darwin-xnu";
					rev = "xnu-6153.141.1";
					hash = "sha256-/2aR6n5CbUobwbxkrGqBOAhCZLwDdIsoIOcpALhAUF8=";
				};
				in stdenvNoCC.mkDerivation {
					name = "snap-util-${lib.substring 0 8 self.inputs.snap-util.lastModifiedDate}";
					src = snap-util;
					nativeBuildInputs = [ xcode ];
					preBuild = ''
						unset DEVELOPER_DIR SDKROOT
						NIX_CFLAGS_COMPILE='-idirafter ${snapshot-header}/bsd'
					'';
					installPhase = ''
						mkdir -p $out/bin
						cp snapUtil $out/bin/.snapUtil-wrapped
						cat > $out/bin/snapUtil <<- EOF
							#!/bin/sh
							if csrutil status | grep -Fq disabled && sysctl kern.bootargs | grep -Fq amfi_get_out_of_my_way ; then
								exec -a ./snapUtil $out/bin/.snapUtil-wrapped "\$@"
							else
								echo 'snapUtil requires SIP and AMFI to be disabled:'
								echo '• boot recovery system'
								echo '• run ‘csrutil disable’'
								echo '• run ‘nvram boot-args=amfi_get_out_of_my_way=0x1’'
								exit 1
							fi
						EOF
						chmod a+x $out/bin/snapUtil
					'';
					__noChroot = true;
					postFixup = ''
						cat > snapUtil.entitlements <<- EOF
							<?xml version="1.0" encoding="UTF-8"?>
							<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
							<plist version="1.0">
							<dict>
								<key>com.apple.developer.vfs.snapshot</key>
								<true/>
								<key>com.apple.private.apfs.revert-to-snapshot</key>
								<true/>
							</dict>
							</plist>
						EOF
						codesign -s - --entitlement snapUtil.entitlements $out/bin/.snapUtil-wrapped
					'';
				};
		};
	};
}
