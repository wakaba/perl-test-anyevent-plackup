all:

# ------ Setup ------

WGET = wget
GIT = git
PERL = perl
PERL_VERSION = latest
PERL_PATH = $(abspath local/perlbrew/perls/perl-$(PERL_VERSION)/bin)

PMB_PMTAR_REPO_URL =
PMB_PMPP_REPO_URL = 

Makefile-setupenv: Makefile.setupenv
	$(MAKE) --makefile Makefile.setupenv setupenv-update \
	    SETUPENV_MIN_REVISION=20120337

Makefile.setupenv:
	$(WGET) -O $@ https://raw.github.com/wakaba/perl-setupenv/master/Makefile.setupenv

lperl lplackup lprove local-perl perl-version perl-exec \
remotedev-test \
pmb-install pmb-update cinnamon \
local-submodules generatepm: %: Makefile-setupenv
	$(MAKE) --makefile Makefile.setupenv $@ \
	    PMB_PMTAR_REPO_URL=$(PMB_PMTAR_REPO_URL) \
	    PMB_PMPP_REPO_URL=$(PMB_PMPP_REPO_URL)

git-submodules:
	$(GIT) submodule update --init

# ------ Tests ------

PERL_ENV = PATH="$(abspath local/perl-$(PERL_VERSION)/pm/bin):$(PERL_PATH):$(PATH)" PERL5LIB="$(shell cat config/perl/libs.txt)"
PROVE = prove

test: test-deps test-main

test-deps: git-submodules pmb-install

test-main:
	$(PERL_ENV) $(PROVE) t/*.t

# ------ Packaging ------

GENERATEPM = local/generatepm/bin/generate-pm-package

dist: generatepm
	$(GENERATEPM) config/dist/test-anyevent-plackup.pi dist/ --generate-json

dist-wakaba-packages: local/wakaba-packages dist
	cp dist/*.json local/wakaba-packages/data/perl/
	cp dist/*.tar.gz local/wakaba-packages/perl/
	cd local/wakaba-packages && PERL5LIB="$(shell cat local/generatepm/config/perl/libs.txt)" $(MAKE) all

local/wakaba-packages: always
	git clone "git@github.com:wakaba/packages.git" $@ || (cd $@ && git pull)
	cd $@ && git submodule update --init

always:
