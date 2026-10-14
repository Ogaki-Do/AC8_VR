# Uploading to the existing private repository

Use the prepared GitHub folder as the upload source. It contains copies of the finished original sources and documents. Keep the private development workspace separate.

1. Open your existing private GitHub repository and confirm the intended branch.
2. Use **Add file → Upload files** and drag in the prepared folder's **contents**, not its enclosing folder. Include the docs, profile files, `scripts`, `data`, `plugins`, `source_code`, `.gitignore` and `.gitattributes`.
3. Review and commit the upload. GitHub Desktop is an alternative: copy contents into the repository checkout, inspect its diff, then commit/push. It can make hidden files easier to handle.
4. Open the README and installation guide to check links and nesting. Confirm tests, build products, private records and recovery journals are absent.
5. Before public release, add the exact compatible UEVR build's download/version label, choose the source license and perform the final headset check on the cleaned build.
6. Create a GitHub Release when ready using tag `v0.1.0` and title `AC8 VR 0.1.0`, and attach `AC8-VR-v0.1.0.zip`. Describe the tested configuration and known limits. The player ZIP omits maintainer source and is simpler than GitHub's automatic source archive.

See GitHub's [file-upload instructions](https://docs.github.com/en/repositories/working-with-files/managing-files/adding-a-file-to-a-repository). Nothing has been uploaded by this preparation, and the repository stays private until you change it.
