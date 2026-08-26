# RooMate release checklist

## Before publishing any appcast

1. Build, archive, sign, notarize, and staple the release app.
2. Confirm `CFBundleShortVersionString`, `CFBundleVersion`, and `LSMinimumSystemVersion` from the archived app rather than from a release label.
3. Zip the stapled app without changing its contents.
4. Create the Sparkle signature with the existing signing credential. Do not generate a replacement credential during a routine release.
5. Upload the exact ZIP to the final HTTPS release URL.
6. Add the item to both appcast working copies with its exact build, display version, byte length, minimum macOS version, URL, and signature.
7. Run `Scripts/validate_appcast.sh appcast.xml /path/to/RooMate-version.zip`.
8. Confirm every enclosure URL returns HTTP 200, then publish the appcast.
9. Download the published feed and archive again and repeat validation against those downloaded files.
10. Test **Check for Updates** from the previous public app before announcing the release.

## V5 to V6 signing-key limitation

RooMate 4.0, 5.0, and 5.1 trust the older Sparkle public key. The released archive labeled 6.0.1 and the current source trust a newer public key. The 6.0.1 archive signature validates with the newer key but not with the key embedded in V5, so V5 cannot authenticate that automatic update.

An exhaustive local search on August 25, 2026 found the old public key in V4/V5 bundles and backups, but no recoverable copy of its private signing credential. Unless a separate offline backup is found, remaining V5 users must manually download and install the V6 app once. After that manual migration, V6 carries the current public key and can authenticate 6.0.2 build 5 and later updates.

Do not regenerate the current credential or alter an already distributed app’s embedded key. Before publishing 6.0.2, back up the current signing credential securely, validate the corrected feed, test V6.0.1-to-V6.0.2 updating, and publish clear manual-install guidance for anyone still using V5.

## Released 6.0.1 identity

The GitHub release and ZIP are labeled 6.0.1, but the app inside the released ZIP contains `CFBundleShortVersionString = 6.0` and `CFBundleVersion = 4`. The appcast must therefore use Sparkle short version 6.0 and build 4 for this unchanged archive. Do not rewrite or repackage the released ZIP; its byte length and signature cover the exact existing bytes.
