# Habit Gate development hygiene

- Keep the daily-use app at `/Applications/Habit Gate.app`.
- Build into `dist.noindex/`, as the build/install scripts do. Do not leave a second app in an indexed `dist/` folder.
- Put preview and fixture app bundles inside a `.noindex` directory, use a distinct bundle identifier, and unregister them with `lsregister -u` when finished.
- Save rollback builds as verified ZIP archives inside a private `.noindex` directory outside the repository. Do not leave unpacked backup `.app` bundles in indexed workspace folders.
- Preserve Habitify's app, Keychain credentials and the user's runtime configuration, daily ledger and weekend schedule during cleanup.
- Use targeted application unregistration. Do not reset the global Launch Services database or unrelated app associations.
