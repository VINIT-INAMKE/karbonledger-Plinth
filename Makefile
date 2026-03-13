.PHONY: buildall scripts clean shell

# Build all contracts
buildall:
	cabal build all

build:
	cabal build

# Generate script envelopes for all validators
scripts:
	cabal run gen-scripts
	@echo ""
	@echo "Script envelopes ready in: scripts/"

# Clean build artifacts
clean:
	cabal clean
	rm -rf scripts/*.plutus
	@echo "Cleaned build artifacts"

# Enter nix development shell
shell:
	nix develop

# Update cabal packages (run after modifying cabal.project)
update:
	cabal update

# Format Haskell code
format:
	find src app -name "*.hs" -exec stylish-haskell -i {} \;
	@echo "Formatted all Haskell files"

# Run HLint
lint:
	hlint src app
	@echo "Linting complete"

# Full build: clean, build, and generate blueprint
all: clean build blueprint
