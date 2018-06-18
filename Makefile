# This file is licensed under the Affero General Public License version 3 or
# later. See the COPYING file.
# @author Bernhard Posselt <dev@bernhard-posselt.com>
# @copyright Bernhard Posselt 2016
# @author Georg Ehrke <oc.list@georgehrke.com>
# @copyright Georg Ehrke 2016

# Generic Makefile for building and packaging a ownCloud app which uses npm and
# Composer.
#
# Dependencies:
# * make
# * which
# * curl: used if phpunit and composer are not installed to fetch them from the web
# * tar: for building the archive
# * npm: for building and testing everything JS
#
# If no composer.json is in the app root directory, the Composer step
# will be skipped. The same goes for the package.json which can be located in
# the app root or the js/ directory.
#
# The npm command by launches the npm build script:
#
#    npm run build
#
# The npm test command launches the npm test script:
#
#    npm run test
#
# The idea behind this is to be completely testing and build tool agnostic. All
# build tools and additional package managers should be installed locally in
# your project, since this won't pollute people's global namespace.
#
# The following npm scripts in your package.json install and update the bower
# and npm dependencies and use gulp as build system (notice how everything is
# run from the node_modules folder):
#
#    "scripts": {
#        "test": "node node_modules/gulp-cli/bin/gulp.js karma",
#        "prebuild": "npm install && node_modules/bower/bin/bower install && node_modules/bower/bin/bower update",
#        "build": "node node_modules/gulp-cli/bin/gulp.js"
#    },

app_name=$(notdir $(CURDIR))
build_tools_directory=$(CURDIR)/build/tools
source_build_directory=$(CURDIR)/build/source/notes
source_artifact_directory=$(CURDIR)/build/artifacts/source
source_package_name=$(source_artifact_directory)/$(app_name)
appstore_build_directory=$(CURDIR)/build/appstore/notes
appstore_artifact_directory=$(CURDIR)/build/artifacts/appstore
appstore_package_name=$(appstore_artifact_directory)/$(app_name)
npm=$(shell which npm 2> /dev/null)
gcp=$(shell which gcp 2> /dev/null)

ifeq (, $(gcp))
	copy_command=cp
else
	copy_command=gcp
endif

# code signing
# assumes the following:
# * the app is inside the owncloud/apps folder
# * the private key is located in ~/.owncloud/notes.key
# * the certificate is located in ~/.owncloud/notes.crt
occ=$(CURDIR)/../../occ
phpunit_oc10=$(CURDIR)/../../lib/composer/bin/phpunit
configdir=$(CURDIR)/../../config
private_key=$(HOME)/.owncloud/certificates/$(app_name).key
certificate=$(HOME)/.owncloud/certificates/$(app_name).crt
sign=php -f $(occ) integrity:sign-app --privateKey="$(private_key)" --certificate="$(certificate)"
sign_skip_msg="Skipping signing, either no key and certificate found in $(private_key) and $(certificate) or occ can not be found at $(occ)"
ifneq (,$(wildcard $(private_key)))
ifneq (,$(wildcard $(certificate)))
ifneq (,$(wildcard $(occ)))
	CAN_SIGN=true
endif
endif
endif

all: build

# Fetches the PHP and JS dependencies and compiles the JS. If no composer.json
# is present, the composer step is skipped, if no package.json or js/package.json
# is present, the npm step is skipped
.PHONY: build
build:
	make npm

# Installs npm dependencies
.PHONY: npm
npm:
	cd js && $(npm) run build

# Removes the appstore build
.PHONY: clean
clean:
	rm -rf ./build
	rm -rf css/public
	rm -rf js/public

# Same as clean but also removes dependencies installed by composer, bower and
# npm
.PHONY: distclean
distclean: clean
	rm -rf vendor
	rm -rf node_modules
	rm -rf js/vendor
	rm -rf js/node_modules

# Builds the source and appstore package
.PHONY: dist
dist:
	make source
	make appstore

# Builds the source package
.PHONY: source
source:
	rm -rf $(source_build_directory) $(source_artifact_directory)
	mkdir -p $(source_build_directory) $(source_artifact_directory)
	rsync -rv . $(source_build_directory) \
	--exclude=/.git/ \
	--exclude=/.idea/ \
	--exclude=/build/ \
	--exclude=/js/node_modules/ \
	--exclude=*.log
ifdef CAN_SIGN
	$(sign) --path "$(source_build_directory)"
else
	@echo $(sign_skip_msg)
endif
	tar -cvzf $(source_package_name).tar.gz -C $(source_build_directory)/../ $(app_name)

# Builds the source package for the app store, ignores php and js tests
.PHONY: appstore
appstore: build
	rm -rf $(appstore_build_directory) $(appstore_artifact_directory)
	mkdir -p $(appstore_build_directory) $(appstore_artifact_directory)
	$(copy_command) --parents -r \
	"appinfo" \
	"controller" \
	"css" \
	"db" \
	"img" \
	"js/vendor" \
	"js/public" \
	"l10n" \
	"service" \
	"templates" \
	"COPYING" \
	"CHANGELOG.md" \
	$(appstore_build_directory)
ifdef CAN_SIGN
	mv $(configdir)/config.php $(configdir)/config-2.php
	$(sign) --path="$(appstore_build_directory)"
	mv $(configdir)/config-2.php $(configdir)/config.php
else
	@echo $(sign_skip_msg)
endif
	tar -czf $(appstore_package_name).tar.gz -C $(appstore_build_directory)/../ $(app_name)


# Command for running JS and PHP tests. Works for package.json files in the js/
# and root directory. If phpunit is not installed systemwide, a copy is fetched
# from the internet
.PHONY: test
test:
	cd js && $(npm) run test
ifneq ("$(wildcard $(phpunit_oc10))","")
	php $(phpunit_oc10) -c phpunit.xml --coverage-clover coverage.clover
else
	phpunit -c phpunit.xml --coverage-clover coverage.clover
	# phpunit -c phpunit.integration.xml --coverage-clover build/php-unit.clover
endif
