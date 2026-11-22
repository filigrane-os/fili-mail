# Facteur (fili-mail): build and install.
#
#   make                       build the release binary
#   make test                  unit tests (the engine alone, no Qt needed to link them)
#   sudo make install          install under /usr/local (PREFIX=/usr for a system package)
#   make install DESTDIR=pkg PREFIX=/usr      stage into a directory (packagers)
#   make install-data PREFIX=~/.local         everything but the binary (launcher, icon, licences, what the shell reads)
#
# Everything the application brings to the Filigrane desktop lives here and is installed together: the program, the launcher,
# the icon, and shell/ (the module of the fili-bar, the fallback menu of the bar, the brief of Lia), which ends in
# $(DATADIR)/filigrane/shell/ where `fili-bar link-system` finds it.
#
# cxx-qt finds Qt through qmake. QMAKE overrides the search below (Qt 6 only), for example
#   make QMAKE=/opt/qt6/bin/qmake6
PREFIX ?= /usr/local
DESTDIR ?=
BINDIR ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share
CARGO ?= cargo
TARGET_DIR ?= $(if $(CARGO_TARGET_DIR),$(CARGO_TARGET_DIR),target)
QMAKE ?= $(firstword $(wildcard /usr/lib/qt6/bin/qmake6 /usr/lib64/qt6/bin/qmake6 /usr/lib/qt6/bin/qmake /usr/lib64/qt6/bin/qmake) $(shell command -v qmake6 qmake-qt6 2>/dev/null))
export QMAKE

.PHONY: all build test install install-data uninstall

all: build

build:
	$(CARGO) build --release --locked

# The engine tests link without Qt. They run in debug with the test credential store: the integration tests of tests/cli.rs
# need it (it refuses release builds), otherwise they look for a Secret Service and stop at auth_signed_out.
test:
	$(CARGO) test --locked --no-default-features --features integration-test-credentials
	python3 -I scripts/check-shell-menu.py
	python3 -I scripts/fili-api-lint --app .

install: build install-data
	install -Dm755 $(TARGET_DIR)/release/fili-mail $(DESTDIR)$(BINDIR)/fili-mail
	ln -sf fili-mail $(DESTDIR)$(BINDIR)/facteur

install-data:
	install -Dm644 data/fili-mail.desktop $(DESTDIR)$(DATADIR)/applications/fili-mail.desktop
	install -Dm644 data/icons/hicolor/scalable/apps/fili-mail.svg $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/fili-mail.svg
	install -Dm644 LICENSE $(DESTDIR)$(DATADIR)/licenses/fili-mail/LICENSE
	install -Dm644 NOTICE $(DESTDIR)$(DATADIR)/licenses/fili-mail/NOTICE
	for f in licenses/*; do install -Dm644 $$f $(DESTDIR)$(DATADIR)/licenses/fili-mail/$$(basename $$f); done
	mkdir -p $(DESTDIR)$(DATADIR)/filigrane/shell
	cp -r shell/. $(DESTDIR)$(DATADIR)/filigrane/shell/

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/fili-mail $(DESTDIR)$(BINDIR)/facteur
	rm -f $(DESTDIR)$(DATADIR)/applications/fili-mail.desktop
	rm -f $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/fili-mail.svg
	rm -rf $(DESTDIR)$(DATADIR)/licenses/fili-mail
	rm -rf $(DESTDIR)$(DATADIR)/filigrane/shell/fili-bar/mail
	rm -f $(DESTDIR)$(DATADIR)/filigrane/shell/ctl/fili-mail.json $(DESTDIR)$(DATADIR)/filigrane/shell/appmenu/fili-mail.json $(DESTDIR)$(DATADIR)/filigrane/shell/lia/fili-mail.md
