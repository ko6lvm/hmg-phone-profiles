.PHONY: all build test clean verify

all: build

build:
	@chmod +x build.sh
	@./build.sh

test:
	@chmod +x tests/run_all_tests.sh
	@./tests/run_all_tests.sh

verify: test

clean:
	@rm -rf build autoprofile.selector.zip package/app/AutoProfile.apk
	@echo "Clean completed."
