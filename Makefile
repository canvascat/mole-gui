.PHONY: all test app open clean

all: test app

test:
	bash scripts/test.sh

app:
	bash scripts/build.sh

open: app
	open build/mole-gui.app

clean:
	rm -rf build
