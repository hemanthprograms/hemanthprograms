PROJECT := SnoreGuard.xcodeproj
SCHEME := SnoreGuard
# Override with e.g. `make test DESTINATION='platform=iOS Simulator,name=iPhone 15'`
DESTINATION ?= platform=iOS Simulator,name=iPhone 16

.PHONY: project build test open clean assets

project: ## Generate the Xcode project from project.yml
	xcodegen generate

build: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO build

test: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO test

open: project
	open $(PROJECT)

assets: ## Regenerate the bundled sample recording and the app icon
	python3 Tools/make_sample_audio.py
	python3 Tools/make_app_icon.py

clean:
	rm -rf $(PROJECT) DerivedData build
