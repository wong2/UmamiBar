build:
	./Scripts/build-app.sh

run: build
	open build/UmamiBar.app

clean:
	rm -rf .build build

.PHONY: build run clean
