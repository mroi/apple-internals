{
	description = "tools to understand the internals of Apple’s operating systems";
	inputs = {
		acextract = {
			url = github:bartoszj/acextract;
			flake = false;
		};
		command-line = {
			url = github:iHTCboy/CommandLine;
			flake = false;
		};
		snapshot-header = {
			url = "https://opensource.apple.com/tarballs/xnu/xnu-6153.141.1.tar.gz";
			flake = false;
		};
		snap-util = {
			url = github:ahl/apfs;
			flake = false;
		};
	};
	outputs = { self, nixpkgs, acextract, command-line, snapshot-header, snap-util }: {
		acextract =
			with import nixpkgs { system = "x86_64-darwin"; };
			let platformXcodeBuildHook = makeSetupHook {
				# FIXME: impurely uses platform Xcode, but there is no proper Swift support in Nix’ xcodebuild
				deps = [ (writeScriptBin "xcodebuild" ''#!/bin/sh
					LD=clang
					exec /usr/bin/xcodebuild "$@"
				'') ];
			} "${xcbuildHook}/nix-support/setup-hook";
			in stdenv.mkDerivation {
				name = "acextract-${lib.substring 0 8 self.inputs.acextract.lastModifiedDate}";
				src = acextract;
				nativeBuildInputs = [ platformXcodeBuildHook ];
				# FIXME: want to have submodule support for Nix flakes, workaround by explicit instantiation
				postUnpack = "rmdir source/CommandLine ; ln -s ${command-line} source/CommandLine";
				installPhase = ''
					mkdir -p $out/bin
					cp Products/Release/acextract $out/bin/
				'';
				dontStrip = true;
			};
		snap-util =
			with import nixpkgs { system = "x86_64-darwin"; };
			stdenv.mkDerivation {
				name = "snap-util-${lib.substring 0 8 self.inputs.snap-util.lastModifiedDate}";
				src = snap-util;
				preBuild = "NIX_CFLAGS_COMPILE='-idirafter ${snapshot-header}/bsd'";
				installPhase = ''
					mkdir -p $out/bin
					cp snapUtil $out/bin/.snapUtil-wrapped
					cat > $out/bin/snapUtil <<- EOF
						#!/bin/sh
						if csrutil status | grep -Fq disabled && sysctl kern.bootargs | grep -Fq amfi_get_out_of_my_way ; then
							exec $out/bin/.snapUtil-wrapped "\$@"
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
				postFixup = ''
					cat > snapUtil.entitlements <<- EOF
						<?xml version="1.0" encoding="UTF-8"?>
						<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
						<plist version="1.0">
						<dict>
							<key>com.apple.developer.vfs.snapshot</key>
							<true/>
						</dict>
						</plist>
					EOF
					/usr/bin/codesign -s - --entitlement snapUtil.entitlements $out/bin/.snapUtil-wrapped
				'';
			};
	};
}
