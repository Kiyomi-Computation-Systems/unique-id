# unique-id
#
# UUIDs, versions 4 and 7, for R6RS. The libraries under src/ are plain R6RS;
# (unique-id system) alone also imports (srfi :19), for the clock. Three
# lanes run the suites:
#
#   chez   tests/test-*.sps on Chez Scheme, with SRFI-64 and SRFI-19 from
#          chez-srfi
#   guile  the same suites on Guile 3 in R6RS mode, with Guile's own SRFIs
#   tools  tools/test-*.sps, the audits' own suites and the fork suite, on
#          Chez alone
#
# Two more lanes, docs-chez and docs-guile, run the programs make check-docs
# writes from docs/.
#
# chez-srfi is a submodule pinned under vendor/. `make submodules` clones it,
# once, where the network is; `make check-pins` holds it at SRFI_PIN; `make
# deps` links it into build/ and never fetches.

# The Chez binary. A CHEZ given on the command line or in the environment
# stays as given. Otherwise scripts/require-chez --find asks `scheme` and
# `chez` (Homebrew's name for it) what each is, and takes the first on PATH
# that is Chez Scheme, else the first on PATH, else `scheme`, which
# check-chez then refuses: on a Mac, another Scheme may own `scheme`. Asked
# once, when make reads this file, and exported, so the suites that run a
# check program as a child start this same Chez.
ifeq ($(strip $(CHEZ)),)
CHEZ := $(shell scripts/require-chez --find scheme chez)
endif
export CHEZ

# The Guile binary, found the same way among `guile` and `guile-3.0`
# (Debian's and Ubuntu's name for it), and refused by check-guile unless it
# answers as Guile 3.
ifeq ($(strip $(GUILE)),)
GUILE := $(shell scripts/require-guile --find guile guile-3.0)
endif
export GUILE

# --- the pin ------------------------------------------------------------------
# chez-srfi tags no releases, so the pin is a commit. Move SRFI_PIN and the
# submodule's gitlink together: make check-pins holds them equal.
SRFI_DIR := vendor/chez-srfi
SRFI_PIN := 7879b527f267f067416552fb989135ad1b4ea436

# --- the library paths --------------------------------------------------------
# LIBDIRS is src/ and build/scheme-libs, which carries (srfi :19) for
# (unique-id system). CHEZ_LIBDIRS adds tests/, which holds
# (unique-id-testing); build/scheme-libs carries (srfi :64) too.
# TOOL_LIBDIRS is the tools lane's: tools/, which holds (unique-id-checks),
# and tests/, but not src/, which the audits read as data and never import.
# Exported, so an audit's suite can run a check program on the path it runs
# on itself.
BUILD_DIR := build
SRFI_LIBS := $(BUILD_DIR)/scheme-libs
LIBDIRS := src:$(SRFI_LIBS)
# chez_libdirs DIR: the Chez lane's library path, with DIR where tests/ is.
chez_libdirs = src:$(1):$(SRFI_LIBS)
CHEZ_LIBDIRS := $(call chez_libdirs,tests)
TOOL_LIBDIRS := tools:tests:$(SRFI_LIBS)
export TOOL_LIBDIRS

# Guile in R6RS mode, which loads STEM.sls, and prefers STEM.guile.sls, which
# check-imports and check-tests refuse. Guile searches the -L directories in
# the order given, as Chez does its libdirs, so src/ comes first, then tests/,
# then Guile's own directories.
# GUILE_ENV keeps the environment out: GUILE_LOAD_PATH and
# GUILE_LOAD_COMPILED_PATH would put other directories ahead of Guile's own,
# and Guile reads compiled files from XDG_CACHE_HOME's cache even with
# --no-auto-compile, so the cache is one under build/ that nothing writes to.
# The prelude drops the warnings Guile writes when a suite's (rnrs) replaces
# its core bindings, and with them those for two imported libraries that
# export one name, which Chez refuses outright.
GUILE_ENV := env -u GUILE_LOAD_PATH -u GUILE_LOAD_COMPILED_PATH \
             XDG_CACHE_HOME=$(abspath $(BUILD_DIR))/guile-cache
# guile_flags DIR: the Guile lane's flags, with DIR where tests/ is.
# make check-lane-order runs both lanes' paths with a stand-in (unique-id) in
# DIR, and fails unless the one in src/ wins.
guile_flags = --r6rs --no-auto-compile -L $(abspath src) -L $(abspath $(1)) \
              -l $(abspath scripts/guile-prelude.scm)
GUILE_FLAGS := $(call guile_flags,tests)

# Every suite, in one order everywhere: make 3.82 to 4.2 leave $(wildcard)
# unsorted.
SUITES := $(sort $(wildcard tests/test-*.sps))
TOOL_SUITES := $(sort $(wildcard tools/test-*.sps))

# Seconds a suite may run before timeout kills it and its lane names it HUNG.
TEST_TIMEOUT ?= 120

# GNU timeout. Homebrew's coreutils installs it as gtimeout on macOS.
TIMEOUT ?= $(or $(shell command -v timeout 2>/dev/null),$(shell command -v gtimeout 2>/dev/null),timeout)

# Open file descriptors a suite may hold, set with ulimit -n. A suite that
# leaks ports fails within about 64 calls on every Scheme; Guile closes the
# ports its collector finds, so under a higher limit it hides the leak.
FD_LIMIT ?= 64

# lane NAME, COMMAND, SUITES, DIR: one shell command, in a subshell, that
# runs each of SUITES as its own process, COMMAND /abs/path/to/SUITE, from
# the directory DIR, under GNU timeout and ulimit -n FD_LIMIT, chained with
# && so that a shell that refuses the cap runs nothing, and reports its exit
# status, or HUNG when timeout killed it (exit 124). It exits 1 if any suite
# failed or hung, or if SUITES is empty. At a terminal, --foreground keeps a
# suite in make's process group, so Ctrl-C reaches it. The Guile lane runs
# from build/guile, because Guile 3.0.9's SRFI-64 writes SUITE-NAME.log to
# the directory it runs in.
lane = ( \
  if [ -z "$(strip $(3))" ]; then \
    echo "$(1): no suites to run" >&2; \
    exit 1; \
  fi; \
  command -v $(TIMEOUT) >/dev/null 2>&1 || { \
    echo "$(1): $(TIMEOUT) not found: install GNU coreutils (brew install coreutils on macOS)" >&2; \
    exit 1; \
  }; \
  mkdir -p $(4) || exit 1; \
  passed=0; failed=0; hung=0; fg=; \
  if [ -t 0 ]; then fg=--foreground; fi; \
  for t in $(3); do \
    echo "=== $(1) $$t"; \
    ( cd $(4) && ulimit -n $(FD_LIMIT) && exec $(TIMEOUT) $$fg $(TEST_TIMEOUT) $(2) $(CURDIR)/$$t ); \
    rc=$$?; \
    if [ $$rc -eq 0 ]; then \
      echo "$(1): pass $$t"; passed=$$((passed + 1)); \
    elif [ $$rc -eq 124 ]; then \
      echo "$(1): HUNG $$t (no exit within $(TEST_TIMEOUT)s)"; hung=$$((hung + 1)); \
    else \
      echo "$(1): FAIL $$t (exit $$rc)"; failed=$$((failed + 1)); \
    fi; \
  done; \
  echo "$(1): ran $$((passed + failed + hung)), passed $$passed, failed $$failed, hung $$hung"; \
  [ $$failed -eq 0 ] && [ $$hung -eq 0 ] )

CHEZ_RUN := $(CHEZ) --libdirs $(CHEZ_LIBDIRS) --program
GUILE_RUN := $(GUILE_ENV) $(GUILE) $(GUILE_FLAGS)
GUILE_DIR := $(abspath $(BUILD_DIR))/guile
TOOL_RUN := $(CHEZ) --libdirs $(TOOL_LIBDIRS) --program

# The programs make check-docs runs: tools/doc-examples.sps writes one per page
# of docs/ into DOC_DIR, and each lane runs them as it runs a suite. Chez runs
# them on src/ and chez-srfi; Guile on src/ alone, with its own SRFIs.
DOC_DIR := $(BUILD_DIR)/doc-examples
DOCS_CHEZ_RUN := $(CHEZ) --libdirs $(LIBDIRS) --program
DOCS_GUILE_RUN := $(GUILE_ENV) $(GUILE) --r6rs --no-auto-compile -L $(abspath src) \
                  -l $(abspath scripts/guile-prelude.scm)

# docs_check: one shell command, in a subshell, that writes the programs, then
# runs them on the docs-chez and docs-guile lanes. The list of programs is read
# after the generator ran, so it is a shell variable, not a make wildcard. Every
# step runs, and it exits 1 if any failed, a generator that refused a page
# included: that page's program writes its complaints and exits 1, so each lane
# names it as failed too.
docs_check = ( status=0; \
  $(TOOL_RUN) tools/doc-examples.sps docs $(DOC_DIR) || status=1; \
  progs=$$(LC_ALL=C ls $(DOC_DIR)/*.sps 2>/dev/null); \
  $(call lane,docs-chez,$(DOCS_CHEZ_RUN),$$progs,$(CURDIR)) || status=1; \
  $(call lane,docs-guile,$(DOCS_GUILE_RUN),$$progs,$(GUILE_DIR)) || status=1; \
  exit $$status )

# One physical line: check-help reads it with awk, and fails if it ends in a
# backslash.
.PHONY: help check-help submodules check-pins check-chez check-guile deps dev dev-guile run test test-chez test-guile test-tools check-suites check-imports check-tests check-lane-order check-docs reference site-deps site check-site clean

.DEFAULT_GOAL := help

# The name column is as wide as the longest target's name.
help: ## Show this help message
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_.-]+:.*?## / \
	  { n++; name[n] = $$1; text[n] = $$2; if (length($$1) > width) width = length($$1) } \
	  END { format = "  \033[36m%-" width "s\033[0m %s\n"; \
	        for (i = 1; i <= n; i++) printf format, name[i], text[i] }' $(MAKEFILE_LIST)

# The files that tell contributors which targets to run.
CONTRIBUTOR_DOCS := CONTRIBUTING.md .github/PULL_REQUEST_TEMPLATE.md .github/ISSUE_TEMPLATE/bug_report.md

# Reads what `make help` prints, colour codes stripped, so it checks the
# listing itself. Both directions: every .PHONY target is listed, and every
# listed target is in .PHONY. A listed target left out of .PHONY silently
# stops running once a file of its name exists.
#
# Then each target the contributor docs quote must be in .PHONY: every word
# after `make` in a code span that starts with it, wrapped over lines or not,
# and on a line in a fenced block that starts with it. A file that quotes none
# fails too, since this check would then have read nothing in it.
check-help: ## Fail unless `make help` lists exactly the .PHONY targets, and the contributor docs quote no other
	@status=0; \
	if grep -qE '^\.PHONY:.*\\$$' Makefile; then \
	  echo "check-help: the .PHONY line ends in a backslash; keep it on one line" >&2; \
	  status=1; \
	fi; \
	help=$$($(MAKE) --no-print-directory help) || { \
	  echo "check-help: make help failed" >&2; \
	  exit 1; \
	}; \
	esc=$$(printf '\033'); \
	listed=$$(printf '%s\n' "$$help" | sed "s/$$esc\[[0-9;]*m//g" | awk '{ print $$1 }'); \
	phony=$$(awk '/^\.PHONY:/ { $$1 = ""; print }' Makefile); \
	for t in $$phony; do \
	  printf '%s\n' $$listed | grep -qxF "$$t" || { \
	    echo "check-help: make help does not list .PHONY target '$$t'; give it a '## ' description on its target line" >&2; \
	    status=1; \
	  }; \
	done; \
	for t in $$listed; do \
	  printf '%s\n' $$phony | grep -qxF "$$t" || { \
	    echo "check-help: make help lists '$$t', which is not in .PHONY" >&2; \
	    status=1; \
	  }; \
	done; \
	for f in $(CONTRIBUTOR_DOCS); do \
	  [ -f "$$f" ] || { echo "check-help: $$f is missing" >&2; status=1; continue; }; \
	  quoted=$$(awk '/^[ \t]*```/ { fence = !fence; next } \
	    fence { if (match($$0, /^[ \t]*make( +[a-z][a-z0-9-]*)+/)) print substr($$0, RSTART, RLENGTH); next } \
	    { text = text " " $$0 } \
	    END { while (match(text, /`make( +[a-z][a-z0-9-]*)+/)) { \
	            print substr(text, RSTART + 1, RLENGTH - 1); text = substr(text, RSTART + RLENGTH) } }' "$$f" \
	    | awk '{ for (i = 2; i <= NF; i++) print $$i }' | sort -u); \
	  [ -n "$$quoted" ] || { \
	    echo "check-help: $$f quotes no make target, so this check read nothing in it" >&2; \
	    status=1; \
	  }; \
	  for t in $$quoted; do \
	    printf '%s\n' $$phony | grep -qxF "$$t" || { \
	      echo "check-help: $$f quotes 'make $$t', and $$t is not a target" >&2; \
	      status=1; \
	    }; \
	  done; \
	done; \
	exit $$status

submodules: ## (network) Clone chez-srfi at its pin into vendor/
	git submodule update --init $(SRFI_DIR)

# The checkout is asked for its own .git first: in a submodule that was never
# cloned, `git -C` would climb to this repository and answer its commit.
# Read-only.
check-pins: ## Fail unless chez-srfi's gitlink and checkout are both SRFI_PIN, with no local edits
	@fail=0; \
	rec=$$(git ls-files -s -- $(SRFI_DIR) | awk '$$1 == "160000" && $$3 == 0 { print $$2 }'); \
	if [ "$$rec" != "$(SRFI_PIN)" ]; then \
	  echo "PIN MISMATCH: the gitlink records $(SRFI_DIR) at $${rec:-<none>}, SRFI_PIN says $(SRFI_PIN)" >&2; fail=1; \
	fi; \
	got=; [ -e "$(SRFI_DIR)/.git" ] && got=$$(git -C $(SRFI_DIR) rev-parse HEAD 2>/dev/null); \
	if [ "$$got" != "$(SRFI_PIN)" ]; then \
	  echo "PIN MISMATCH: $(SRFI_DIR) is checked out at $${got:-<absent>}, SRFI_PIN says $(SRFI_PIN)" >&2; fail=1; \
	elif [ -n "$$(git -C $(SRFI_DIR) status --porcelain --untracked-files=no)" ]; then \
	  echo "PIN DIRTY: $(SRFI_DIR) has local edits to tracked files" >&2; fail=1; \
	else \
	  echo "pin ok: $(SRFI_DIR) $(SRFI_PIN)"; \
	fi; \
	exit $$fail

# Runs $(CHEZ) once, under a time limit, and refuses one that is not Chez
# Scheme, naming what it found. deps takes it first, so every target that
# runs Chez holds it before Chez runs.
check-chez: ## Fail unless CHEZ is Chez Scheme, naming what it found
	@scripts/require-chez "$(CHEZ)"

# The same for $(GUILE), which every target that runs Guile takes first.
check-guile: ## Fail unless GUILE is Guile 3, naming what it found
	@scripts/require-guile "$(GUILE)"

# chez-srfi ships Akku's percent-encoded file names (%3a64.sls), and Chez
# finds (srfi :64) only under the decoded spelling (:64.sls), so every entry
# is linked under both and the submodule's own tree is left alone. `ln -sfn`
# replaces a link in place; the -n stops it following an existing link to a
# directory into the submodule. Guile needs none of it: it has its own.
deps: check-chez ## Link chez-srfi (SRFI-64, SRFI-19) into build/scheme-libs; never fetches
	@if [ ! -e $(SRFI_DIR)/%3a64.sls ]; then \
	  echo "deps: $(SRFI_DIR)/%3a64.sls not found, so the submodule is empty. Run 'make submodules' where the network is: make deps never fetches." >&2; \
	  exit 1; \
	fi
	@mkdir -p $(SRFI_LIBS)/srfi
	@set -e; \
	src="$(abspath $(SRFI_DIR))"; dst="$(abspath $(SRFI_LIBS))/srfi"; \
	for f in "$$src"/*; do \
	  b=$$(basename "$$f"); \
	  ln -sfn "$$f" "$$dst/$$b"; \
	  d=$$(printf '%s' "$$b" | sed 's/%3a/:/g'); \
	  [ "$$d" = "$$b" ] || ln -sfn "$$f" "$$dst/$$d"; \
	done

dev: deps ## Start a Chez REPL with src/ and chez-srfi on the library path
	$(CHEZ) --libdirs $(LIBDIRS)

dev-guile: check-guile ## Start a Guile REPL in R6RS mode with src/ on the load path
	$(GUILE_ENV) $(GUILE) --r6rs --no-auto-compile -L $(abspath src) -l $(abspath scripts/guile-prelude.scm)

run: deps ## Run a program on Chez with src/ and chez-srfi on the library path: make run PROGRAM=file.sps
	@test -n "$(PROGRAM)" || { echo "run: set PROGRAM=path/to/program.sps" >&2; exit 2; }
	$(CHEZ) --libdirs $(LIBDIRS) --program $(PROGRAM)

# The checks come first: check-chez (through deps), check-guile, check-help,
# check-suites, check-tests and, once src/ exists, check-imports, so the
# first library under src/ is audited without anyone remembering to. Then
# every lane runs, even after one fails, so a run names every failure: tools,
# chez and guile, then the docs lanes (docs-chez and docs-guile, as check-docs
# runs them); it fails if any lane did. check-lane-order is one of the checks
# that come first.
test: deps check-guile check-help check-suites check-tests check-lane-order $(if $(wildcard src),check-imports) ## Run the checks, then every lane: tools, chez, guile, and the docs examples on docs-chez and docs-guile; fail if any fails or hangs
	@status=0; failed=; \
	$(call lane,tools,$(TOOL_RUN),$(TOOL_SUITES),$(CURDIR)) || { status=1; failed="$$failed tools"; }; \
	$(call lane,chez,$(CHEZ_RUN),$(SUITES),$(CURDIR)) || { status=1; failed="$$failed chez"; }; \
	$(call lane,guile,$(GUILE_RUN),$(SUITES),$(GUILE_DIR)) || { status=1; failed="$$failed guile"; }; \
	$(call docs_check) || { status=1; failed="$$failed docs"; }; \
	if [ $$status -eq 0 ]; then echo "test: every lane passed"; else echo "test: FAIL in$$failed" >&2; fi; \
	exit $$status

test-chez: deps ## Run tests/test-*.sps on Chez; fail if one fails or hangs, or none exists
	@$(call lane,chez,$(CHEZ_RUN),$(SUITES),$(CURDIR))

test-guile: check-guile ## Run tests/test-*.sps on Guile; fail if one fails or hangs, or none exists
	@$(call lane,guile,$(GUILE_RUN),$(SUITES),$(GUILE_DIR))

test-tools: deps ## Run tools/test-*.sps, the audits' own suites and the fork suite, on Chez
	@$(call lane,tools,$(TOOL_RUN),$(TOOL_SUITES),$(CURDIR))

# Reads every suite of every lane, and the site's two suites, as data and
# fails unless each one's last datum is the shared exit form and no datum
# before it holds an exit form but (exit 1), naming each suite that breaks
# either rule (tools/check-suites.sps).
check-suites: deps ## Fail unless every tests/test-*.sps, tools/test-*.sps and site suite ends with the shared exit form
	@$(CHEZ) --libdirs $(TOOL_LIBDIRS) --program tools/check-suites.sps $(SUITES) $(TOOL_SUITES) $(SITE_SUITES)

# Reads every file under src/ and fails unless each is a plain R6RS library:
# named <name>.sls at its library name's path, first line #!r6rs and no #!
# after it, one library form, importing only (rnrs ...) but (rnrs eval),
# (unique-id ...) libraries under src/, and in (unique-id system) alone
# (srfi :19) (tools/check-imports.sps). It passes over dot files,
# #autosave# and backup~. make test runs it once src/ exists.
check-imports: deps ## Fail unless every file under src/ is a plain R6RS library importing only what it may
	@$(CHEZ) --libdirs $(TOOL_LIBDIRS) --program tools/check-imports.sps src

# Reads every file under tests/ and fails unless each is a plain R6RS library
# or program that both lanes load alike: STEM.sls or STEM.sps with no other
# dot, no (unique-id ...) library, first line #!r6rs and no #! after it,
# importing only (rnrs ...) but (rnrs eval), (srfi :64), (srfi :19), the
# (unique-id ...) libraries under src/ and the libraries under tests/
# (tools/check-tests.sps).
check-tests: deps ## Fail unless every file under tests/ is plain R6RS, importing only (rnrs ...), (srfi :64), (srfi :19), the library and tests/' own
	@$(CHEZ) --libdirs $(TOOL_LIBDIRS) --program tools/check-tests.sps tests src

# Runs tools/fixtures/lane-order/probe.sps on each lane's path, built by
# chez_libdirs and guile_flags with the stand-in (unique-id) under
# LANE_SHADOW where tests/ is. The probe passes only where src/'s (unique-id)
# wins. Each Scheme must also refuse the probe with the stand-in put first,
# or the stand-in was never found and the check proves nothing.
LANE_SHADOW := tools/fixtures/lane-order/shadow
LANE_PROBE := tools/fixtures/lane-order/probe.sps
check-lane-order: deps check-guile ## Fail unless both lanes find a library in src/ before one of the same name in tests/
	@status=0; \
	$(CHEZ) --libdirs $(call chez_libdirs,$(LANE_SHADOW)) --program $(LANE_PROBE) \
	  </dev/null >/dev/null 2>&1 \
	  || { echo "check-lane-order: the chez lane finds tests/ before src/" >&2; status=1; }; \
	$(GUILE_ENV) $(GUILE) $(call guile_flags,$(LANE_SHADOW)) $(abspath $(LANE_PROBE)) \
	  </dev/null >/dev/null 2>&1 \
	  || { echo "check-lane-order: the guile lane finds tests/ before src/" >&2; status=1; }; \
	if $(CHEZ) --libdirs $(LANE_SHADOW):$(call chez_libdirs,$(LANE_SHADOW)) \
	     --program $(LANE_PROBE) </dev/null >/dev/null 2>&1; then \
	  echo "check-lane-order: chez ran the probe with the stand-in first" >&2; status=1; \
	fi; \
	if $(GUILE_ENV) $(GUILE) -L $(abspath $(LANE_SHADOW)) $(call guile_flags,$(LANE_SHADOW)) \
	     $(abspath $(LANE_PROBE)) </dev/null >/dev/null 2>&1; then \
	  echo "check-lane-order: guile ran the probe with the stand-in first" >&2; status=1; \
	fi; \
	if [ $$status -eq 0 ]; then echo "check-lane-order: both lanes find src/ first"; fi; \
	exit $$status

# Runs every example in docs/ as a program on Chez and on Guile, and checks
# each `;; =>` result (tools/doc-examples.sps, (unique-id-doc-examples)).
check-docs: deps check-guile ## Fail unless every example in docs/ runs on Chez and on Guile and prints its `;; =>` result
	@$(call docs_check)

# --- the docs -----------------------------------------------------------------
# docs/reference.md is written from the signature comments in src/ by
# tools/reference.sps, on the tools lane's path, through a temporary file so
# that a failure leaves the old page. tools/test-unique-id-reference.sps fails
# make test while the page is stale: run this after changing a comment in src/.
reference: deps ## Write docs/reference.md from the signature comments in src/
	@$(TOOL_RUN) tools/reference.sps src tools/reference-head.md > $(BUILD_DIR)/reference.md.tmp
	@mv $(BUILD_DIR)/reference.md.tmp docs/reference.md
	@echo "reference: wrote docs/reference.md"

# docs/*.md render into build/site/ through chez-cmark-gfm, a development-only
# dependency: src/ stays plain R6RS, and make test needs no Markdown parser.
# An `akku install` tree wins when present; otherwise scripts/fetch-akku-lock
# downloads the archive Akku.lock pins, checks its sha256 and unpacks it under
# build/akku. chez-cmark-gfm loads the system's libcmark-gfm, or the pair
# CHEZ_CMARK_GFM_LIBS names.
SITE_CMARK := $(if $(wildcard .akku/lib/cmark/gfm.sls),.akku/lib,$(BUILD_DIR)/akku/chez-cmark-gfm/src)
SITE_LIBDIRS := .:$(SITE_CMARK)
export SITE_LIBDIRS
SITE_REF ?= main
SITE_SUITES := $(wildcard site/tests/site-unit.sps site/tests/site-render-unit.sps \
                          site/tests/site-check-fixtures.sps)

site-deps: ## (network, once) Get chez-cmark-gfm as Akku.lock pins it
	@if [ -f .akku/lib/cmark/gfm.sls ]; then \
	  echo "site-deps: using .akku/lib (akku install)"; \
	else \
	  AKKU_DEST=$(BUILD_DIR)/akku sh scripts/fetch-akku-lock chez-cmark-gfm; \
	fi

site: site-deps check-chez ## Render docs/ into build/site/; SITE_REF=<tag> pins repository links
	@mkdir -p $(BUILD_DIR)/site
	@SITE_REF="$(SITE_REF)" SITE_OUT=$(BUILD_DIR)/site \
	  $(CHEZ) --libdirs $(SITE_LIBDIRS) --program build-site.sps
	@cp site/style.css $(BUILD_DIR)/site/style.css
	@echo "site: $(BUILD_DIR)/site ready (open $(BUILD_DIR)/site/index.html)"

# The generator's pure parts run first, with no chez-cmark-gfm on the path;
# then the rendering, with it; then site-check.sps on each fixture tree, which
# it must pass or fail as the tree says; then the docs themselves, holding
# every page, link and anchor. SITE_DOCS names another docs tree, as the
# site's fixtures do. SITE_LIBDIRS is exported for the fixtures' suite, which
# runs site-check.sps as a child.
check-site: site-deps deps ## Test the site generator, then check every docs/ page, link and anchor
	@$(CHEZ) --libdirs .:tests:$(SRFI_LIBS) --program site/tests/site-unit.sps
	@$(CHEZ) --libdirs $(SITE_LIBDIRS):tests:$(SRFI_LIBS) --program site/tests/site-render-unit.sps
	@$(CHEZ) --libdirs .:tests:$(SRFI_LIBS) --program site/tests/site-check-fixtures.sps
	@SITE_REF="$(SITE_REF)" $(CHEZ) --libdirs $(SITE_LIBDIRS) --program site/tests/site-check.sps

clean: ## Remove build/
	rm -rf $(BUILD_DIR)
