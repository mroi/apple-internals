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


# MARK: - data extraction helpers

prefix = $$(case $(1) in \
	(macOS) ;; \
	(iOS) echo /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot ;; \
	(tvOS) echo /Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/tvOS.simruntime/Contents/Resources/RuntimeRoot ;; \
	(watchOS) echo /Applications/Xcode.app/Contents/Developer/Platforms/WatchOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/watchOS.simruntime/Contents/Resources/RuntimeRoot ;; \
	esac)

find = \
	{ \
		$(2) find /Library /System /bin /dev /private /sbin /usr ! \( -path /System/Volumes/Data -prune \) $(1) 2> /dev/null | sed 's/^/macOS /' ; \
		cd $(call prefix,iOS) ; find . $(1) | sed '1d;s/^\./iOS /' ; \
		cd $(call prefix,tvOS) ; find . $(1) | sed '1d;s/^\./tvOS /' ; \
		cd $(call prefix,watchOS) ; find . $(1) | sed '1d;s/^\./watchOS /' ; \
	}


# MARK: - generator targets for database

db_files:
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
