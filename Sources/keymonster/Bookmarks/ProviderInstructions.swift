import Foundation

/// The text the Palette settings' "Copy Instructions for an LLM" button puts
/// on the clipboard: everything a coding agent needs to write a provider
/// script (see `ScriptedProvider`) without reading this repo. The example is
/// a real script — a test loads and runs it — so the instructions can't drift
/// from what the loader accepts.
enum ProviderInstructions {
    static let exampleScript = """
    // uuid.js — when the query is a UUID, offer links that embed it.
    function suggest(query) {
      var uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      if (!uuid.test(query)) return []

      return [
        { title: "Order " + query, url: "https://admin.example.com/orders/" + query },
        { title: "Logs for " + query, url: "https://logs.example.com/?q=" + encodeURIComponent(query) }
      ]
    }
    """

    static func text(directory: URL = ProviderStore.defaultDirectory()) -> String {
        """
        Write a provider script for Key Monster's Palette (a command-K style launcher).

        As the user types in the Palette, every provider script is asked for extra rows to show above \
        their bookmarks. A provider is a single JavaScript file saved as:

          \(directory.path)/<name>.js

        Scripts are reloaded each time the Palette opens, so no restart is needed.

        Shape of a script:

        - Define a global function `suggest(query)`. Nothing else is required.
        - `query` is the trimmed text typed so far, never empty. It runs on every keystroke, so keep it \
        fast and synchronous.
        - Return an array of `{ title: string, url: string }` objects, shown in order. Return `[]` \
        (or nothing) when the query isn't something this provider recognises — most queries should \
        produce no rows.
        - `url` is opened when the row is chosen: an https:// url, another scheme (slack://, \
        obsidian://, mailto:), or a local path starting with / or ~/.
        - Rows missing a non-empty title or url are skipped. A script that throws contributes nothing.
        - The script runs in plain JavaScriptCore: ES2015+ language features and the standard library \
        (RegExp, JSON, String methods, Date, Math, encodeURIComponent), but no console, fetch, timers, \
        filesystem, or shell. Use `encodeURIComponent` when putting the query in a url.
        - Use a regular expression test as the first line so unrelated queries return immediately.

        Complete example (\(directory.path)/uuid.js):

        ```js
        \(exampleScript)
        ```

        Ask me what queries the provider should recognise and where the rows should link, then write \
        the file.
        """
    }
}
