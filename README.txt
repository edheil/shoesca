Shoesca (until I think of a better name).

Shoesca is a client for the ancient telnet-based ISCA BBS
telnet://bbs.iscabbs.com/

It utilizes Wade Minter's library for accessing the bbs through the
newer, non-telnet-based 'raccdoc' interface.
http://github.com/minter/raccdoc/tree/master

To use it you need a copy of Shoes ( http://shoooes.net/ ).

Fire up Shoes, and choose "Open an app" and open the shoesca.rb
file.  You'll be presented with a login screen.  The app will save
your login credentials in a file called bbsconfig.yaml, in the same
directory as the shoesca.rb file.

The first time you run the app, it will download a copy of the
raccdoc library; subsequent runs, it will use the copy it
downloaded the first time.

Packaged, executable  versions (.exe, .dmg, and .run) are
available in the packages directory; however, they may be
buggy (the .exe in particular pops up a bogus error message
about SSLEAY32.dll).  Downloading shoes from http//shoooes.net
is preferable, esp. on Windows.

