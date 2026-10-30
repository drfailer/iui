.PHONY: playground
.PHONY: run

playground:
	odin build test/playground -collection:olib=../ -debug

run:
	./playground
