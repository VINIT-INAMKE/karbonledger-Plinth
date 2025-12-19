.PHONY: buildall blueprint clean shell

# Build all contracts
buildall:
	cabal build all

build:
	cabal build 

# Generate blueprint
blueprint:
	cabal run gen-blueprint
	@echo ""
	@echo "Blueprint ready at: blueprints/contract.json"

# Clean build artifacts
clean:
	cabal clean
	rm -rf blueprints/*.json
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
