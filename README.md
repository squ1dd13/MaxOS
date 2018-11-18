# MaxOS
some tweak thingy for mac

I sincerely doubt that anybody would want to use this, but if you do, build MaxOS, ProcessCatcher and injectd. Move MaxOS and ProcessCatcher to /Users/<you>/Library/Application Support/MaxOS. Move bootstrap.dylib from ProcessCatcher there too. Follow the instructions in the Tweaks folder. 
  
Run `sudo chmod 4755 <injectd's location>` and `sudo chown root <injectd's location>`, then launch injectd. Don't run it as root though.

Oh you will probably have to turn off SIP, but try without just in case.

## Credits
Read credits.txt
