# Facteur (fili-mail): build and install.
#
#   make                       build the release binary
#   make test                  unit tests (the engine alone, no Qt needed to link them)
#   sudo make install          install under /usr/local (PREFIX=/usr for a system package)
#   make install DESTDIR=pkg PREFIX=/usr      stage into a directory (packagers)
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

.PHONY: all build test install uninstall

all: build

build:
	$(CARGO) build --release --locked

# The engine tests link without Qt. 24 of them compare with the JavaScript implementation Omamail had and need node;
# they fail without it (known, to be removed with the old UI).
test:
	$(CARGO) test --release --locked --no-default-features

install: build
	install -Dm755 $(TARGET_DIR)/release/fili-mail $(DESTDIR)$(BINDIR)/fili-mail
	ln -sf fili-mail $(DESTDIR)$(BINDIR)/facteur
	install -Dm644 data/fili-mail.desktop $(DESTDIR)$(DATADIR)/applications/fili-mail.desktop
	install -Dm644 data/icons/hicolor/scalable/apps/fili-mail.svg $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/fili-mail.svg
	install -Dm644 LICENSE $(DESTDIR)$(DATADIR)/licenses/fili-mail/LICENSE
	install -Dm644 NOTICE $(DESTDIR)$(DATADIR)/licenses/fili-mail/NOTICE

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/fili-mail $(DESTDIR)$(BINDIR)/facteur
	rm -f $(DESTDIR)$(DATADIR)/applications/fili-mail.desktop
	rm -f $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/fili-mail.svg
	rm -rf $(DESTDIR)$(DATADIR)/licenses/fili-mail
