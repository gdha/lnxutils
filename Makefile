# MAKEFILE for lnxutils
name = lnxutils
specfile = $(name).spec

version := $(shell awk 'BEGIN { FS=":" } /^Version:/ { print $$2}' $(specfile) | sed -e 's/ //g' -e 's/\$$//')

prefix = /opt/ncsbin
bindir = $(prefix)/lnxutils

distversion = $(version)
rpmrelease =

.PHONY: doc

all:
	@echo "Nothing to build. Use \`make help' for more information."

help:
	@echo -e "lnxutils make targets:\n\
\n\
  install         - Install Linux Utilities to DESTDIR (may replace files)\n\
  dist            - Create tar file\n\
  rpm             - Create RPM package\n\
\n\
"

clean:
	@echo -e "\033[1m== Cleanup temporary files ==\033[0;0m"
	-rm -f $(name)-$(distversion).tar.gz

dist: clean $(name)-$(distversion).tar.gz

$(name)-$(distversion).tar.gz: $(name).spec
	@echo -e "\033[1m== Building archive $(name)-$(distversion) ==\033[0;0m"
	tar -czf $(name)-$(distversion).tar.gz --transform='s,^,$(name)-$(version)/,S' .$(bindir) \
	Makefile $(name).spec LICENSE

rpm: dist $(name).spec
	@echo -e "\033[1m== Building RPM package $(name)-$(distversion)==\033[0;0m"
	rpmbuild -ta --clean \
		--define "_rpmfilename %%{NAME}-%%{VERSION}-%%{RELEASE}.%%{ARCH}.rpm" \
		--define "debug_package %{nil}" \
		--define "_rpmdir %(pwd)" $(name)-$(distversion).tar.gz

install: 
	@echo -e "\033[1m== Installing Linux Utilities ==\033[0;0m"
	install -Dp -m0755 .$(bindir)/*.sh $(DESTDIR)$(bindir)/

