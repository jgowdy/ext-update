# ext-update

This is a shell script that handles updating manually unpacked extensions.  This is useful for extensions not available on the Chrome Web Store, for various reasons.  It relies on the CRX metadata indicating where the origin of the extension is.

To use the script:

* Create a directory like ~/.chrome-ext
* Download your desired .crx file into that directory
* Copy the script into that directory
* Run the script
* If successful, there should now be an unpacked directory for each extension
* From within your Chromium based browser (Hopefully Brave) go to Extensions
* Enable developer mode if you haven't already
* Select Load Unpacked
* Select the unpacked directory for each of your extensions
* Periodically run the script to update your extensions (add to crontab)

