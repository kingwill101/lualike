CC ?= cc
AR ?= ar
CFLAGS ?= -O2 -g -Wall -Wextra -Wpedantic -std=c99

INCDIR = include
SRCDIR = src
BUILDDIR = build

SRCS = $(SRCDIR)/lualike_rt.c
OBJS = $(BUILDDIR)/lualike_rt.o
LIB = $(BUILDDIR)/liblualike_rt.a

.PHONY: all clean

all: $(LIB)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BUILDDIR)/lualike_rt.o: $(SRCS) $(INCDIR)/lualike_rt.h | $(BUILDDIR)
	$(CC) $(CFLAGS) -I$(INCDIR) -c -o $@ $<

$(LIB): $(OBJS)
	$(AR) rcs $@ $^

clean:
	rm -rf $(BUILDDIR)
