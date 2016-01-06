# Name of the project.
NAME = testpull
PKG = "github.com/coreos-inc/testpull/cmd/quayctl"

# Platforms on which we want to build the project.
PLATFORMS = darwin-x64 linux-x86 linux-x64 linux-arm windows-x86 windows-x64

# Additional tags and LDFLAGS to use during the compilation.
GO_BUILD_TAGS = netgo std
GO_LDFLAGS += -w -extldflags=-static

# Path to the libtorrent-go package and name of the Docker image generated by build-envs.
LIBTORRENT_GO = github.com/dmartinpro/libtorrent-go
LIBTORRENT_GO_HOME = $(shell go env GOPATH)/src/$(LIBTORRENT_GO)
LIBTORRENT_GO_DOCKER_IMAGE = dmartinpro/libtorrent-go

# Set binaries and platform specific variables.
CC = cc
CXX = c++
STRIP = strip
GO = go
GIT = git
DOCKER = docker
UPX = upx

ifneq ($(CROSS_TRIPLE),)
	CC := $(CROSS_TRIPLE)-$(CC)
	CXX := $(CROSS_TRIPLE)-$(CXX)
	STRIP := $(CROSS_TRIPLE)-strip
endif

ifeq ($(TARGET_ARCH),x86)
	GOARCH = 386
else ifeq ($(TARGET_ARCH),x64)
	GOARCH = amd64
else ifeq ($(TARGET_ARCH),arm)
	GOARCH = arm
	GOARM = 6
endif

ifeq ($(TARGET_OS), windows)
	EXT = .exe
	GOOS = windows
else ifeq ($(TARGET_OS), darwin)
	EXT =
	GOOS = darwin
	CC := $(CROSS_ROOT)/bin/$(CROSS_TRIPLE)-clang
	CXX := $(CROSS_ROOT)/bin/$(CROSS_TRIPLE)-clang++
	GO_LDFLAGS = -linkmode=external -extld=$(CC)
else ifeq ($(TARGET_OS), linux)
	EXT =
	GOOS = linux
	GO_LDFLAGS = -linkmode=external -extld=$(CC)
endif

OUTPUT_NAME = $(NAME)$(EXT)
BUILD_PATH = build/$(TARGET_OS)_$(TARGET_ARCH)

force:
	@true

libtorrent-go:
	$(GO) get -d $(LIBTORRENT_GO)
	$(MAKE) -C $(LIBTORRENT_GO_HOME) PLATFORMS='$(PLATFORMS)' build-envs
	$(MAKE) -C $(LIBTORRENT_GO_HOME) PLATFORMS='$(PLATFORMS)' alldist

$(BUILD_PATH):
	mkdir -p $(BUILD_PATH)

$(BUILD_PATH)/$(OUTPUT_NAME): $(BUILD_PATH) force
	LDFLAGS='$(LDFLAGS)' \
	CC=$(CC) CXX=$(CXX) \
	GOOS=$(GOOS) \
	GOARCH=$(GOARCH) \
	GOARM=$(GOARM) \
	CGO_ENABLED=1 \
	$(GO) build -v \
		-tags '$(GO_BUILD_TAGS)' \
		-gcflags '$(GO_GCFLAGS)' \
		-ldflags '$(GO_LDFLAGS)' \
		-o '$(BUILD_PATH)/$(OUTPUT_NAME)' \
		$(PKG)

$(NAME): $(BUILD_PATH)/$(OUTPUT_NAME)

build: force
	$(DOCKER) run --rm \
		-v $(HOME):$(HOME) \
		-e GOPATH=$(shell go env GOPATH) \
		-e PKG_CONFIG_PATH=${CROSS_ROOT}/lib/pkgconfig \
		-w $(shell pwd) \
		$(LIBTORRENT_GO_DOCKER_IMAGE):$(TARGET_OS)-$(TARGET_ARCH) \
		make dist TARGET_OS=$(TARGET_OS) TARGET_ARCH=$(TARGET_ARCH)

strip: $(BUILD_PATH)/$(OUTPUT_NAME) force
	find $(BUILD_PATH) -type f ! -name "*.exe" -exec $(STRIP) {} \;

upx: $(BUILD_PATH)/$(OUTPUT_NAME) force
	curl -L http://sourceforge.net/projects/upx/files/upx/3.91/upx-3.91-amd64_linux.tar.bz2/download | tar xj && \
  cp upx-3.91-amd64_linux/upx /usr/bin/upx && \
  rm -rf upx-3.91-amd64_linux && \
	find $(BUILD_PATH) -type f ! -name "*.exe" -a ! -name "*.so" -a ! -name "*.sha" -exec $(UPX) --lzma {} \;

checksum: $(BUILD_PATH)/$(OUTPUT_NAME) force
	shasum -b $(BUILD_PATH)/$(OUTPUT_NAME) | cut -d' ' -f1 > $(BUILD_PATH)/$(OUTPUT_NAME).sha

ifeq ($(TARGET_ARCH), arm)
dist: $(NAME) strip checksum
else ifeq ($(TARGET_OS), windows)
dist: $(NAME) strip checksum
	find $(shell go env GOPATH)/pkg/$(GOOS)_$(GOARCH) -name *.dll -exec cp -f {} $(BUILD_PATH) \;
else
dist: $(NAME) strip upx checksum
endif

alldist: force
	for i in $(PLATFORMS); do \
		$(MAKE) build \
			TARGET_OS=$$(echo $$i  | cut -f1 -d-) \
			TARGET_ARCH=$$(echo $$i  | cut -f2 -d-); \
	done

clean:
	rm -rf $(BUILD_PATH)

distclean:
	rm -rf build
