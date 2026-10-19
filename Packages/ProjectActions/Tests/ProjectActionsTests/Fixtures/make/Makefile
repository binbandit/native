BIN := app
.PHONY: test build

all: build test ## Build and test

build: $(BIN)
	@echo build

test:
	go test ./...

build/app.o: main.c
	cc -c main.c

%.o: %.c
	cc -c $<

clean: ## Remove build output
	rm -rf build

CFLAGS ?= -O2
install: CFLAGS = -O0
