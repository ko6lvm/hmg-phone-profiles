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
	@rm -rf build hmg-phone-profiles.zip hmg-phone-profiles-usb.zip autoprofile.selector.zip autoprofile.selector-usb.zip package/app/AutoProfile.apk
	@echo "Clean completed."
