.PHONY: build run test package dmg clean

build:
	swift build --target MindFlowKit && swift build --product MindFlow

run: build
	swift run MindFlow

test:
	swift run MindFlowChecks

package:
	bash scripts/package.sh 12.9

dmg:
	bash scripts/make-dmg.sh 12.9

clean:
	rm -rf .build

count:
	@echo "Checks:"; grep -c 'check(' Checks/MindFlowChecks.swift || echo 0
	@echo "Files:"; find Sources -name '*.swift' | wc -l
	@echo "Lines:"; cat Sources/MindFlowKit/*.swift Sources/MindFlow/*.swift | wc -l