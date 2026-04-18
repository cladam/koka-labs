CC      = gcc
CFLAGS  = -std=c2x -Wall -Wextra -pedantic
LDFLAGS =
BINDIR  = ..

PROGS   = dirinfo wordsort

.PHONY: all clean

all: $(PROGS)

dirinfo: dirinfo.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(BINDIR)/$@ $<

wordsort: wordsort.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(BINDIR)/$@ $<

clean:
	rm -f $(addprefix $(BINDIR)/,$(PROGS))
