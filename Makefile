all:

# ------ Setup ------

WGET = wget
GIT = git

PMB_PMTAR_REPO_URL =
PMB_PMPP_REPO_URL = 

Makefile-setupenv: Makefile.setupenv
	$(MAKE) --makefile Makefile.setupenv setupenv-update \
	    SETUPENV_MIN_REVISION=20121008

Makefile.setupenv:
	$(WGET) -O $@ https://raw.github.com/wakaba/perl-setupenv/master/Makefile.setupenv

pmbp-install pmbp-update generatepm: %: Makefile-setupenv
	$(MAKE) --makefile Makefile.setupenv $@ \
	    PMB_PMTAR_REPO_URL=$(PMB_PMTAR_REPO_URL) \
	    PMB_PMPP_REPO_URL=$(PMB_PMPP_REPO_URL)

git-submodules:
	$(GIT) submodule update --init

deps: git-submodules pmbp-install

# ------ Tests ------

PROVE = ./prove

test: test-deps test-main

test-deps: deps

test-main:
	$(PROVE) t/*.t

# ------ Packaging ------

GENERATEPM = local/generatepm/bin/generate-pm-package

dist: generatepm
	$(GENERATEPM) config/dist/test-anyevent-plackup.pi dist/ --generate-json

dist-wakaba-packages: local/wakaba-packages dist
	cp dist/*.json local/wakaba-packages/data/perl/
	cp dist/*.tar.gz local/wakaba-packages/perl/
	cd local/wakaba-packages && PERL5LIB="$(shell cat local/generatepm/config/perl/libs.txt)" $(MAKE) all

local/wakaba-packages: always
	$(GIT) clone "git@github.com:wakaba/packages.git" $@ || (cd $@ && git pull)
	cd $@ && $(GIT) submodule update --init

always:
