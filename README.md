# The CPAN Analyzer

This is a sort of half-baked tool I've been writing since 2010, spending a
day or two a year on it.  Its job is to look at the current contents of the
CPAN and produce a snapshot of metadata that can be used to answer useful
questions.

Some of these questions are:

* how many dists depend on what
* how many dists do things we might like to forbid?
* how many dists were created by what dist-packaging tools?
* what features of the META files are actually in use?
* what's the average age of things on the CPAN?

The main program in `bin/analyze-metacpan`, which will look for a CPAN::Mini
mirror and spit out an SQLite file.  I suggest using the `--ramdisk` option,
which only works on macOS (for now?) and makes things go faster.  Also, on
macOS, you'll want it for case sensitivity.

This is really only designed for my use, it's probably not portable, it
violates encapsulation on other libraries, and is generally just a mess.  But I
use it!
