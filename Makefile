MY_INTERNALS = $(HOME)/Library/Mobile\ Documents/com~apple~TextEdit/Documents/Apple\ Internals.rtf
DB := $(if $(DB),$(DB:.lz=),internals-$(shell sw_vers -productVersion).db)
DB_TARGETS = db_files db_binaries
CHECK_TARGETS = check_files

.PHONY: all check $(DB_TARGETS) $(CHECK_TARGETS)
.INTERMEDIATE: $(DB)

all: $(DB).lz check

ifneq ($(wildcard $(MY_INTERNALS)),)
internals.txt: $(MY_INTERNALS)
	textutil -cat txt "$<" -output $@
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


# MARK: - data extraction helpers

NIX = $(shell nix-build --no-out-link -A nixFlakes '<nixpkgs>')/bin/nix
DSCU = $(shell \
	$(NIX) --experimental-features 'nix-command flakes' build --no-write-lock-file .\#dyld-shared-cache && \
	readlink result && rm result)/bin/dyld_shared_cache_util

dyld: /System/Library/dyld/dyld_shared_cache_$(shell uname -m)
	$(DSCU) -extract $@ $<
	find $@ -type f -print0 | xargs -0 chmod a+x

prefix = $$(case $(1) in \
	(macOS) ;; \
	(macOS-dyld) echo $(dir $(realpath $(firstword $(MAKEFILE_LIST))))/dyld ;; \
	(iOS) echo /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot ;; \
	(tvOS) echo /Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/tvOS.simruntime/Contents/Resources/RuntimeRoot ;; \
	(watchOS) echo /Applications/Xcode.app/Contents/Developer/Platforms/WatchOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/watchOS.simruntime/Contents/Resources/RuntimeRoot ;; \
	esac)

find = \
	{ \
		$(2) find /Library /System /bin /dev /private /sbin /usr ! \( -path /System/Volumes/Data -prune \) $(1) 2> /dev/null | sed 's/^/macOS /' ; \
		cd /Applications/Xcode.app/Contents/Developer ; find Library Toolchains Tools usr $(1) | sed 's|^|macOS /Applications/Xcode.app/Contents/Developer/|' ; \
		test -d "$(call prefix,macOS-dyld)" && cd "$(call prefix,macOS-dyld)" && find . $(1) | sed '1d;s/^\./macOS-dyld /' ; \
		cd $(call prefix,iOS) ; find . $(1) | sed '1d;s/^\./iOS /' ; \
		cd $(call prefix,tvOS) ; find . $(1) | sed '1d;s/^\./tvOS /' ; \
		cd $(call prefix,watchOS) ; find . $(1) | sed '1d;s/^\./watchOS /' ; \
	}

file = SELECT id, $(1) FROM files WHERE os = '$$os' AND path = '$$(echo "$$path" | sed "s/'/''/g")'


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
	echo 'CREATE INDEX files_path ON files (path);'

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
			codesign --display --entitlements - "$(call prefix,$$os)$$path" 2> /dev/null | \
				sed 1d | plutil -convert json - -o - | \
				sed "/^<stdin>: Property List error/d;/^{}/d;s/'/''/g;s|.*|INSERT INTO entitlements $(call file,json('&'));\n|" ; \
			strings -n 8 "$(call prefix,$$os)$$path" | \
				LANG=C sed "s/'/''/g;s|.*|INSERT INTO strings $(call file,'&');|" ; \
		fi ; \
	done

$(DB_TARGETS)::
	echo 'COMMIT TRANSACTION;'


# MARK: - check targets for internals.txt

check_files: internals.txt $(DB)
	printf '\033[1mchecking files...\033[m\n' >&2
	grep -ow '~\?/[^,;]*' $< | sed -E 's/ \(.*\)$$//;s/^\/(etc|var)\//\/private&/' | \
		sed "s/'/''/g;s|.*|SELECT count(*), '&' FROM files WHERE path GLOB '&';|" | \
		sqlite3 $(DB) | sed -n "/^0|/{s/^0|//;p;}"
