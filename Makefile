.PHONY: build test run preview check clean
build:
	./scripts/build.sh
test:
	./scripts/test.sh
run: build
	open build/Kaleido.app
preview: build
	open -n build/Kaleido.app --args --preview
check: test build
	./scripts/check-bundle.sh
clean:
	swift package clean
	rm -rf build
