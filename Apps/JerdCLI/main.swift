import Darwin
import JerdCLICore

// The php, composer, and laravel links run this launcher. On success PHP replaces it.
exit(CLILauncher.live().run(.current()))
