PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

statbar: statbar.swift
	swiftc -O -o $@ $<

SRCDIR := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
PLIST = $(HOME)/Library/LaunchAgents/com.statbar.plist

install: statbar install-agent
	mkdir -p "$(BINDIR)"
	cp statbar "$(BINDIR)/statbar"

install-agent:
	mkdir -p "$(HOME)/Library/LaunchAgents"
	launchctl unload "$(PLIST)" 2>/dev/null || true
	awk -v dir="$(BINDIR)" '{gsub("__BINDIR__",dir)}1' "$(SRCDIR)/com.statbar.plist" > "$(PLIST)"
	launchctl bootstrap gui/$$(id -u) "$(PLIST)" 2>/dev/null || launchctl load "$(PLIST)" 2>&1 | grep -v "already loaded" || true

uninstall:
	launchctl bootout gui/$$(id -u) "$(PLIST)" 2>/dev/null || launchctl unload "$(PLIST)" 2>/dev/null || true
	rm -f "$(PLIST)"
	rm -f "$(BINDIR)/statbar"

clean:
	rm -f statbar

run: statbar
	launchctl bootout gui/$$(id -u) "$(PLIST)" 2>/dev/null || true
	killall statbar 2>/dev/null || true
	./statbar &

.PHONY: install install-agent uninstall clean run
