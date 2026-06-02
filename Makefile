.PHONY: build run test clean

build:
	swift build

run:
	swift run

test:
	swift test

clean:
	swift package clean
