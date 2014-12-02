dcheck
======

Check for comics and send them via mail to various users

Everything started with the Dilbert comic, hence the name dcheck (earlier dilbert.pl).

I have it running since early 2008 because I constantly forgot to check my beloved Dilbert comic strip and after some time the supported strip list expanded a bit.

It's not the best piece of code but it works - for me and my few recipients - at least.

Install
-------

dheck depends on a few Perl libraries:
* Config::General
* Getopt::Std
* LWP::UserAgent
* MIME::Lite
* XML::RSS::Parser::Lite

Install those dependencies with the package manager of your distribution.

If for whatever reason you want to install everything as a stand alone package you may want to install Perl libraries with it too.

For this you may use *helper/perl_make.sh*.

Here an example on how to use it:
```bash
wget wget http://search.cpan.org/CPAN/authors/id/E/EB/EBOSRUP/RSS-Parser-Lite-0.10.tar.gz
tar xvfz RSS-Parser-Lite-0.10.tar.gz
cd RSS-Parser-Lite-0.10
../perl_make.sh
make
make test
make install
```

Please note that you'll have to change some paths in *bin/dcheck.pl* if you do this.

Configuration
-------------

dcheck is configured via *etc/dcheck.conf*. Check this file for more information.

Manual running dcheck
---------------------

dcheck only knows one command line parameter: **-s <stripname>**.

If invoked with **-s <stripname>** dcheck only performs the task necessary for this strip.

It's especially useful for debugging.

Automation via Cron
-------------------

Not every comic is published at the same time. For me the following cronjobs work best:

```
1 10 * * *      nobody      /usr/bin/dcheck.pl
1 15 * * *      nobody      /usr/bin/dcheck.pl
```

User registration
-----------------

It would be too much hassle to implement a user registration by myself, so I just open up the old Vim and add/delete users by hand.

Probably the best way would be to setup a small Mailman installation and send the strips to the according lists, so Mailman handles the user stuffs.

