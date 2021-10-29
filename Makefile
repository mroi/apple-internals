override DB := $(if $(DB),$(DB:.lz=),$(lastword $(sort internals-$(shell sw_vers -productVersion).db $(basename $(wildcard internals-*)))))
MY_INTERNALS = $(HOME)/Library/Mobile\ Documents/com~apple~TextEdit/Documents/Apple\ Internals.rtf
DB_TARGETS = db_files db_binaries db_manifests db_assets db_services
CHECK_TARGETS = check_files check_binaries check_manifests check_services

.PHONY: all check view sqlite $(DB_TARGETS) $(CHECK_TARGETS)
.INTERMEDIATE: $(DB)

all: $(DB).lz check

ifneq ($(wildcard $(MY_INTERNALS)),)
internals.txt: $(MY_INTERNALS)
	textutil -cat txt "$<" -output $@
	xattr -c $@
endif

ifneq ($(wildcard $(DB).lz),)
$(DB): $(DB).lz
	compression_tool -decode -i $< -o $@
else
$(DB):
	@$(MAKE) --silent --jobs=1 $(DB_TARGETS) | sqlite3 -bail $@

$(DB).lz: $(DB)
	compression_tool -encode -i $< -o $@
	tmutil addexclusion $@
	rm -rf dyld
endif

check: internals.txt
	@LANG=en sort --ignore-case $< | diff -uw $< -
	@$(MAKE) --silent --jobs=1 $(CHECK_TARGETS)

define VIEW
SELECT path,os FROM files;
SELECT path,os,name FROM files NATURAL JOIN assets;
SELECT path,os,dylib FROM files NATURAL JOIN linkages;
SELECT files.path,os,key,value FROM files NATURAL JOIN services, json_each(plist);
SELECT files.path,os,key,value FROM files NATURAL JOIN entitlements, json_each(plist);
endef
export VIEW

view: $(DB)
	echo "$$VIEW" | sqlite3 -bail $< | LC_COLLATE=C sort

sqlite: $(DB)
	sqlite3 $< || true


# MARK: - data extraction helpers

ACEXTRACT = $(shell nix build --no-write-lock-file .\#acextract && \
	readlink result && rm result)/bin/acextract
DSCEXTRACTOR = $(shell nix build --no-write-lock-file .\#dsc-extractor && \
	readlink result && rm result)/bin/dyld-shared-cache-extractor

dyld: /System/Library/dyld/dyld_shared_cache_$(shell uname -m) /System/DriverKit/System/Library/dyld/dyld_shared_cache_$(shell uname -m)
	for i in $+ ; do $(DSCEXTRACTOR) $$i $@ ; done > /dev/null
	find $@ -type f -print0 | xargs -0 chmod a+x

XCODE = $(lastword $(wildcard /Applications/Xcode.app /Applications/Xcode-beta.app))

prefix = $$(case $(1) in \
	(macOS) ;; \
	(macOS-dyld) echo $(dir $(realpath $(firstword $(MAKEFILE_LIST))))/dyld ;; \
	(iOS) echo $(XCODE)/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot ;; \
	(tvOS) echo $(XCODE)/Contents/Developer/Platforms/AppleTVOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/tvOS.simruntime/Contents/Resources/RuntimeRoot ;; \
	(watchOS) echo $(XCODE)/Contents/Developer/Platforms/WatchOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/watchOS.simruntime/Contents/Resources/RuntimeRoot ;; \
	esac)

find = \
	{ \
		$(2) find /Library /System /bin /dev /private /sbin /usr ! \( -path /System/Volumes/Data -prune \) $(1) 2> /dev/null | sed 's/^/macOS /' ; \
		cd $(XCODE)/Contents/Developer ; find Library Toolchains Tools usr $(1) | sed 's|^|macOS /Applications/Xcode.app/Contents/Developer/|' ; \
		test -d "$(call prefix,macOS-dyld)" && cd "$(call prefix,macOS-dyld)" && find . $(1) | sed '1d;s/^\./macOS-dyld /' ; \
		cd $(call prefix,iOS) ; find . $(1) | sed '1d;s/^\./iOS /' ; \
		cd $(call prefix,tvOS) ; find . $(1) | sed '1d;s/^\./tvOS /' ; \
		cd $(call prefix,watchOS) ; find . $(1) | sed '1d;s/^\./watchOS /' ; \
	}

file = SELECT id, $(1) FROM files WHERE os = '$$os' AND path = '$$(echo "$$path" | sed "s/'/''/g")'
, = , # for entering a literal comma as part of a function argument


# MARK: - generator targets for database

$(DB_TARGETS)::
	echo 'BEGIN IMMEDIATE TRANSACTION;'

db_files:: dyld
	if ! csrutil status | grep -Fq disabled ; then \
		printf '\033[1mdisable SIP to get complete file information\033[m\n' >&2 ; \
		echo 'FAIL;' ; \
		exit 1 ; \
	fi
	printf '\033[1mcollecting file information...\033[m\n' >&2
	echo 'DROP TABLE IF EXISTS files;'
	echo 'CREATE TABLE files (id INTEGER PRIMARY KEY, os TEXT, path TEXT, executable BOOLEAN);'
	$(call find,,sudo) | sed -E "s/'/''/g;s/([^ ]*) (.*)/INSERT INTO files (os, path) VALUES('\1', '\2');/"
	find $(HOME)/Library | sed "s|^$(HOME)|~|;s/'/''/g;s/.*/INSERT INTO files (os, path) VALUES('macOS', '&');/"
	echo 'CREATE INDEX _files_path ON files (path);'

db_binaries:: dyld
	printf '\033[1mcollecting executable information...\033[m\n' >&2
	echo 'DROP TABLE IF EXISTS linkages;'
	echo 'DROP TABLE IF EXISTS entitlements;'
	echo 'DROP TABLE IF EXISTS strings;'
	echo 'CREATE TABLE linkages (id INTEGER REFERENCES files, dylib TEXT);'
	echo 'CREATE TABLE entitlements (id INTEGER REFERENCES files, plist JSON);'
	echo 'CREATE TABLE strings (id INTEGER REFERENCES files, string TEXT);'
	$(call find,-follow -type f -perm +111) | while read -r os path ; do \
		echo "UPDATE files SET executable = true WHERE os = '$$os' AND path = '$$path';" ; \
		if test -r "$(call prefix,$$os)$$path" && file --no-dereference --brief --mime-type "$(call prefix,$$os)$$path" | grep -Fq application/x-mach-binary ; then \
			objdump --macho --dylibs-used "$(call prefix,$$os)$$path" | \
				sed "1d;s/^.//;s/ ([^)]*)$$//;s/'/''/g;s|.*|INSERT INTO linkages $(call file,'&');|" ; \
			codesign --display --xml --entitlements - "$(call prefix,$$os)$$path" 2> /dev/null | \
				plutil -convert json - -o - | \
				sed "/^<stdin>: Property List error/d;/^{}/d;s/'/''/g;s|.*|INSERT INTO entitlements $(call file,json('&'));\n|" ; \
			strings -n 8 "$(call prefix,$$os)$$path" | \
				LANG=C sed "s/'/''/g;s|.*|INSERT INTO strings $(call file,'&');|" ; \
		fi ; \
	done

db_manifests::
	printf '\033[1mcollecting Info.plist information...\033[m\n' >&2
	echo 'DROP TABLE IF EXISTS info;'
	echo 'CREATE TABLE info (id INTEGER REFERENCES files, plist JSON);'
	$(call find,-type f -name 'Info.plist') | while read -r os path ; do \
		test -r "$(call prefix,$$os)$$path" && plutil -convert json "$(call prefix,$$os)$$path" -o - | \
			sed "/: invalid object/d;s/'/''/g;s|.*|INSERT INTO info $(call file,json('&'));\n|" ; \
	done

db_assets::
	printf '\033[1mcollecting asset catalog information...\033[m\n' >&2
	echo 'DROP TABLE IF EXISTS assets;'
	echo 'CREATE TABLE assets (id INTEGER REFERENCES files, name TEXT);'
	$(call find,-type f -name '*.car') | while read -r os path ; do \
		test -r "$(call prefix,$$os)$$path" && $(ACEXTRACT) --list --input "$(call prefix,$$os)$$path" | \
			sed "1d;s/'/''/g;s|.*|INSERT INTO assets $(call file,'&');|" ; \
	done

db_services::
	printf '\033[1mcollecting launchd service information...\033[m\n' >&2
	echo 'DROP TABLE IF EXISTS services;'
	echo 'CREATE TABLE services (id INTEGER REFERENCES files, kind TEXT, plist JSON);'
	$(call find,-type f -name '*.plist' -path '*/LaunchAgents/*' -o -path '*/LaunchDaemons/*') | while read -r os path ; do \
		case "$$path" in (*/LaunchAgents/*) kind=agent ;; (*/LaunchDaemons/*) kind=daemon ;; esac ; \
		test -r "$(call prefix,$$os)$$path" && plutil -convert json "$(call prefix,$$os)$$path" -o - | \
			sed "s/'/''/g;s|.*|INSERT INTO services $(call file,'$$kind'$(,)json('&'));\n|" ; \
	done

$(DB_TARGETS)::
	echo 'COMMIT TRANSACTION;'


# MARK: - check targets for internals.txt

check_files: internals.txt $(DB)
	printf '\033[1mchecking files...\033[m\n' >&2
	grep -ow '~\?/[^,;]*' $< | sed -E 's/ \(.*\)$$//;s/^\/(etc|var)\//\/private&/' | \
		sed "s/'/''/g;s|.*|SELECT count(*), '&' FROM files WHERE path GLOB '&';|" | \
		sqlite3 $(DB) | sed -n "/^0|/{s/^0|//;p;}"

check_binaries: internals.txt $(DB)
	printf '\033[1mchecking command line tools...\033[m\n' >&2
	grep -o 'command line tools\?: [^;]*' $< | sed 's/^[^:]*: //;s/ //g;s/([^)]*)//g' | tr , '\n' | \
		sed "s/'/''/g;s|.*|SELECT count(*), '&' FROM files WHERE executable = true AND path GLOB '*/&';|" | \
		sqlite3 $(DB) | sed -n "/^0|/{s/^0|//;p;}"
	printf '\033[1mchecking frameworks...\033[m\n' >&2
	grep -ow '[[:alnum:]]*\.framework[[:alnum:]/.]*' $< | \
		sed "s|/|/*/|g;s/'/''/g;s|.*|SELECT count(*), '&' FROM files WHERE executable = true AND path GLOB '*/&/*';|" | \
		sqlite3 $(DB) | sed -n "/^0|/{s/^0|//;p;}"
	printf '\033[1mchecking servers...\033[m\n' >&2
	grep -o 'servers\?: [^;]*' $< | sed 's/^[^:]*: //;s/ //g;s/([^)]*)//g' | tr , '\n' | \
		sed "s/'/''/g;s/.*/SELECT count(*), '&' FROM strings WHERE string GLOB '*&*';/" | \
		sqlite3 $(DB) | sed -n "/^0|/{s/^0|//;p;}"

check_manifests: internals.txt $(DB)
	printf '\033[1mchecking extension points...\033[m\n' >&2
	grep -o 'extension points\?: [^;]*' $< | sed 's/^[^:]*: //;s/ //g;s/([^)]*)//g' | tr , '\n' | \
		sed "s/'/''/g;s|.*|SELECT count(*), '&' FROM info, json_each(plist, '$$.NSExtension') WHERE key = 'NSExtensionPointIdentifier' AND value = '&';|" | \
		sqlite3 $(DB) | sed -n "/^0|/{s/^0|//;p;}"

check_services: internals.txt $(DB)
	printf '\033[1mchecking launchd services...\033[m\n' >&2
	grep -o 'launchd services\?: [^;]*' $< | sed 's/^[^:]*: //;s/ //g;s/([^)]*)//g' | tr , '\n' | \
		sed "s/'/''/g;s|.*|SELECT count(*), '&' FROM services, json_each(plist) WHERE key = 'Label' AND value = '&';|" | \
		sqlite3 $(DB) | sed -n "/^0|/{s/^0|//;p;}"
	printf '\033[1mchecking special ports...\033[m\n' >&2
	grep -o '[^ ]* special port [0-9]*' $< | \
		sed -E "s/'/''/g;s/(host|task) special port ([0-9]+)/SELECT count(*), '&' FROM services, json_tree(plist, '$$.MachServices') WHERE key LIKE '\1SpecialPort' AND value = \2;/" | \
		sqlite3 $(DB) | sed -n "/^0|/{s/^0|//;p;}"
