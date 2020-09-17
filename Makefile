MY_INTERNALS = $(HOME)/Library/Mobile\ Documents/com~apple~TextEdit/Documents/Apple\ Internals.rtf

.PHONY: all

all: internals.txt

ifneq ($(wildcard $(MY_INTERNALS)),)
internals.txt: $(MY_INTERNALS)
	textutil -cat txt "$<" -output $@
endif
