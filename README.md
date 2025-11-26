# nx-ovlreloader
On-demand respawner for nx-ovlloader

This system module works alongside nx-ovlloader to ensure it is always running. When executed, nx-ovlreloader monitors the nx-ovlloader process and automatically respawns it if it exits or is terminated.  This allows overlays to be reloaded and tested quickly without requiring a full console restart, streamlining development and improving workflow for Tesla ecosystem overlays.
