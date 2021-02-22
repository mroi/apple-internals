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
		dyld-shared-cache = {
			url = github:antons/dyld-shared-cache-big-sur;
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
	outputs = { self, nixpkgs, acextract, command-line, dyld-shared-cache, snapshot-header, snap-util }: {
		acextract =
			with import nixpkgs { system = "x86_64-darwin"; };
			let xcode12 = makeSetupHook {
				deps = [ (xcodeenv.composeXcodeWrapper { version = "12.4"; }) ];
			} "${xcbuildHook}/nix-support/setup-hook";
			in stdenv.mkDerivation {
				name = "acextract-${lib.substring 0 8 self.inputs.acextract.lastModifiedDate}";
				src = acextract;
				nativeBuildInputs = [ xcode12 ];
				preBuild = "LD=$CC";
				# FIXME: want to have submodule support for Nix flakes, workaround by explicit instantiation
				postUnpack = "rmdir source/CommandLine ; ln -s ${command-line} source/CommandLine";
				installPhase = ''
					mkdir -p $out/bin
					cp Products/Release/acextract $out/bin/
				'';
				dontStrip = true;
			};
		dyld-shared-cache =
			with import nixpkgs { system = "x86_64-darwin"; };
			stdenv.mkDerivation {
				name = "dyld-shared-cache-util-${lib.substring 0 8 self.inputs.dyld-shared-cache.lastModifiedDate}";
				src = dyld-shared-cache;
				nativeBuildInputs = [ xcbuildHook ];
				xcbuildFlags = [
					"-scheme dyld_shared_cache_util"
					"-configuration Release"
					"GCC_PREPROCESSOR_DEFINITIONS=CC_DIGEST_DEPRECATION_WARNING=\\\"\\\""
				];
				installPhase = ''
					mkdir -p $out/bin
					cp Products/Release/{dsc_extractor.bundle,dyld_shared_cache_util} $out/bin/
				'';
			};
		snap-util =
			with import nixpkgs { system = "x86_64-darwin"; };
			stdenv.mkDerivation {
				name = "snap-util-${lib.substring 0 8 self.inputs.snap-util.lastModifiedDate}";
				src = snap-util;
				nativeBuildInputs = [ (xcodeenv.composeXcodeWrapper { version = "12.4"; }) ];
				preBuild = "NIX_CFLAGS_COMPILE='-idirafter ${snapshot-header}/bsd'";
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
					codesign -s - --entitlement snapUtil.entitlements $out/bin/.snapUtil-wrapped
				'';
			};
	};
}
