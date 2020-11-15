MY_INTERNALS = $(HOME)/Library/Mobile\ Documents/com~apple~TextEdit/Documents/Apple\ Internals.rtf
DB = internals-$(shell sw_vers -productVersion).db
DB_TARGETS = db_files

.PHONY: all $(DB_TARGETS)

all: internals.txt $(DB)

ifneq ($(wildcard $(MY_INTERNALS)),)
internals.txt: $(MY_INTERNALS)
	textutil -cat txt "$<" -output $@
endif

$(DB):
	@$(MAKE) --silent --jobs=1 $(DB_TARGETS) | sqlite3 -bail $@

db_files:
	if ! csrutil status | grep -Fq disabled ; then \
		printf '\033[1mdisable SIP to get complete file information\033[m\n' >&2 ; \
		echo 'FAIL;' ; \
		exit 1 ; \
	fi
	printf '\033[1mcollecting file information...\033[m\n' >&2
	echo 'DROP TABLE IF EXISTS files;'
	echo 'CREATE TABLE files (id INTEGER PRIMARY KEY, os TEXT, path TEXT, executable BOOLEAN);'
	sudo find /Library /System /bin /dev /private /sbin /usr ! \( -path /System/Volumes/Data -prune \) 2> /dev/null | \
		sed "s/'/''/g;s/.*/INSERT INTO files (os, path) VALUES('macOS', '&');/"
	find $(HOME)/Library | \
		sed "s|^$(HOME)|~|;s/'/''/g;s/.*/INSERT INTO files (os, path) VALUES('macOS', '&');/"
	cd /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot ; find . | \
		sed "1d;s/\\.//;s/'/''/g;s/.*/INSERT INTO files (os, path) VALUES('iOS', '&');/"
	cd /Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/tvOS.simruntime/Contents/Resources/RuntimeRoot ; find . | \
		sed "1d;s/\\.//;s/'/''/g;s/.*/INSERT INTO files (os, path) VALUES('tvOS', '&');/"
	cd /Applications/Xcode.app/Contents/Developer/Platforms/WatchOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/watchOS.simruntime/Contents/Resources/RuntimeRoot ; find . | \
		sed "1d;s/\\.//;s/'/''/g;s/.*/INSERT INTO files (os, path) VALUES('watchOS', '&');/"
	echo 'CREATE INDEX files_path ON files (path);'
