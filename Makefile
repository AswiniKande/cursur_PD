.PHONY: test shell

test:
	tclsh tests/run_all.tcl

shell:
	./bin/fc_shell
