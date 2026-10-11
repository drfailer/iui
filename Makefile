.PHONY: playground
.PHONY: run

playground:
	odin build test/playground -collection:olib=../

run:
	./playground
